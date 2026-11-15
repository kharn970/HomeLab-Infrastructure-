<#
  Collect-DomainInventory.ps1
  Read-only. Runs on the Hyper-V host and uses PowerShell Direct to query
  Active Directory, DNS, DHCP and Group Policy inside the domain controller VM,
  plus basic identity info from every running VM. Changes nothing.
  Prompts once for domain admin credentials.
  Output: Domain-Inventory.txt next to this script.
#>
param([string]$DcVm = 'DC01')  # Hyper-V VM name of the domain controller to query
$out = Join-Path $PSScriptRoot 'Domain-Inventory.txt'
"Domain inventory via $DcVm, taken $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-File $out -Encoding utf8

$cred = Get-Credential -Message "Domain admin account for the domain hosted on $DcVm"

$dcBlock = {
    $ErrorActionPreference = 'Continue'
    function S($t, [scriptblock]$b) { "`n### $t"; try { & $b 2>&1 | Out-String -Width 250 } catch { "ERROR: $($_.Exception.Message)" } }
    Import-Module ActiveDirectory, GroupPolicy, DnsServer, DhcpServer -ErrorAction SilentlyContinue
    S 'DC OS' { Get-CimInstance Win32_OperatingSystem | Format-List CSName, Caption, Version, InstallDate }
    S 'DC NETWORK' { Get-NetIPConfiguration | Format-List InterfaceAlias, IPv4Address, @{n='Gateway';e={$_.IPv4DefaultGateway.NextHop}}, @{n='DNS';e={$_.DNSServer.ServerAddresses -join ', '}} }
    S 'DC INSTALLED ROLES' { Get-WindowsFeature | Where-Object { $_.Installed -and $_.FeatureType -eq 'Role' } | Format-Table Name, DisplayName -AutoSize }
    S 'AD DOMAIN' { Get-ADDomain | Format-List DNSRoot, NetBIOSName, DomainMode, Forest, PDCEmulator, RIDMaster, InfrastructureMaster, DistinguishedName }
    S 'AD FOREST' { Get-ADForest | Format-List Name, ForestMode, SchemaMaster, DomainNamingMaster, Domains, GlobalCatalogs, Sites, UPNSuffixes }
    S 'AD DOMAIN CONTROLLERS' { Get-ADDomainController -Filter * | Format-Table HostName, IPv4Address, Site, IsGlobalCatalog, IsReadOnly, OperatingSystem -AutoSize }
    S 'AD REPLICATION' { Get-ADReplicationPartnerMetadata -Target (Get-ADDomain).DNSRoot -Scope Domain | Format-Table Server, Partner, LastReplicationSuccess, LastReplicationResult -AutoSize }
    S 'AD SITES AND SUBNETS' { Get-ADReplicationSite -Filter * | Format-Table Name; Get-ADReplicationSubnet -Filter * | Format-Table Name, Site -AutoSize }
    S 'AD RECYCLE BIN' { Get-ADOptionalFeature -Filter 'Name -like "Recycle Bin*"' | Format-List Name, EnabledScopes }
    S 'AD ORGANIZATIONAL UNITS' { Get-ADOrganizationalUnit -Filter * | Sort-Object DistinguishedName | Format-Table Name, DistinguishedName -AutoSize }
    S 'AD COUNTS' { [pscustomobject]@{ Users = @(Get-ADUser -Filter *).Count; EnabledUsers = @(Get-ADUser -Filter 'Enabled -eq $true').Count; Groups = @(Get-ADGroup -Filter *).Count; Computers = @(Get-ADComputer -Filter *).Count } | Format-List }
    S 'AD USERS' { Get-ADUser -Filter * -Properties Title, Department, LastLogonDate | Sort-Object DistinguishedName | Format-Table SamAccountName, Name, Enabled, Title, Department, @{n='OU';e={($_.DistinguishedName -split ',',2)[1]}} -AutoSize }
    S 'AD COMPUTERS' { Get-ADComputer -Filter * -Properties OperatingSystem, IPv4Address | Sort-Object Name | Format-Table Name, OperatingSystem, IPv4Address, Enabled, @{n='OU';e={($_.DistinguishedName -split ',',2)[1]}} -AutoSize }
    S 'AD GROUPS (custom)' { Get-ADGroup -Filter * -Properties Description, Members | Where-Object { $_.DistinguishedName -notmatch 'CN=Builtin|CN=Users,' } | Format-Table Name, GroupScope, GroupCategory, @{n='Members';e={$_.Members.Count}}, Description -AutoSize }
    S 'AD PRIVILEGED GROUP MEMBERS' { 'Domain Admins','Enterprise Admins','Schema Admins' | ForEach-Object { $g = $_; Get-ADGroupMember $g | Select-Object @{n='Group';e={$g}}, Name, objectClass } | Format-Table -AutoSize }
    S 'AD PASSWORD POLICY' { Get-ADDefaultDomainPasswordPolicy | Format-List MinPasswordLength, PasswordHistoryCount, MaxPasswordAge, MinPasswordAge, ComplexityEnabled, LockoutThreshold, LockoutDuration, LockoutObservationWindow }
    S 'FINE-GRAINED PASSWORD POLICIES' { Get-ADFineGrainedPasswordPolicy -Filter * | Format-Table Name, Precedence, MinPasswordLength, AppliesTo -AutoSize }
    S 'GROUP POLICY OBJECTS' { Get-GPO -All | Sort-Object DisplayName | Format-Table DisplayName, GpoStatus, CreationTime, ModificationTime -AutoSize }
    S 'GROUP POLICY LINKS' { $t = @((Get-ADDomain).DistinguishedName) + @(Get-ADOrganizationalUnit -Filter * | ForEach-Object DistinguishedName); $t | ForEach-Object { $d = $_; (Get-GPInheritance -Target $d).GpoLinks | Select-Object @{n='LinkedTo';e={$d}}, DisplayName, Enabled, Enforced, Order } | Format-Table -AutoSize }
    S 'DNS ZONES' { Get-DnsServerZone | Format-Table ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone, DynamicUpdate, ReplicationScope -AutoSize }
    S 'DNS FORWARDERS' { Get-DnsServerForwarder | Format-List IPAddress, UseRootHint }
    S 'DNS A RECORDS (domain zone)' { Get-DnsServerResourceRecord -ZoneName (Get-ADDomain).DNSRoot -RRType A | Where-Object HostName -notmatch '^(@|DomainDnsZones|ForestDnsZones)$' | Format-Table HostName, @{n='IP';e={$_.RecordData.IPv4Address}} -AutoSize }
    S 'DHCP SERVER AUTHORIZED' { Get-DhcpServerInDC | Format-Table DnsName, IPAddress -AutoSize }
    S 'DHCP SCOPES' { Get-DhcpServerv4Scope | Format-Table ScopeId, Name, StartRange, EndRange, SubnetMask, State, LeaseDuration -AutoSize }
    S 'DHCP SCOPE OPTIONS' { Get-DhcpServerv4Scope | ForEach-Object { $s = $_.ScopeId; Get-DhcpServerv4OptionValue -ScopeId $s | Select-Object @{n='Scope';e={$s}}, OptionId, Name, @{n='Value';e={$_.Value -join ', '}} } | Format-Table -AutoSize }
    S 'DHCP RESERVATIONS' { Get-DhcpServerv4Scope | ForEach-Object { Get-DhcpServerv4Reservation -ScopeId $_.ScopeId } | Format-Table IPAddress, Name, ClientId -AutoSize }
    S 'DC SHARES' { Get-SmbShare | Where-Object { $_.Name -notmatch '^\w\$$|^ADMIN\$$|^IPC\$$' } | Format-Table Name, Path -AutoSize }
    S 'DC TIME SOURCE' { w32tm /query /source; w32tm /query /configuration | Select-String 'Type|NtpServer' }
}

"`n================ DOMAIN CONTROLLER: $DcVm ================" | Out-File $out -Append -Encoding utf8
try { Invoke-Command -VMName $DcVm -Credential $cred -ScriptBlock $dcBlock -ErrorAction Stop | Out-File $out -Append -Encoding utf8 }
catch { "ERROR connecting to ${DcVm}: $($_.Exception.Message)" | Out-File $out -Append -Encoding utf8 }

"`n================ RUNNING VMs: guest identity ================" | Out-File $out -Append -Encoding utf8
foreach ($vm in Get-VM | Where-Object State -eq 'Running') {
    try {
        Invoke-Command -VMName $vm.Name -Credential $cred -ErrorAction Stop -ScriptBlock {
            $cs = Get-CimInstance Win32_ComputerSystem; $os = Get-CimInstance Win32_OperatingSystem
            $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127|169\.254)' }).IPAddress -join ', '
            $dns = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses).ServerAddresses | Select-Object -Unique
            [pscustomobject]@{ GuestHostname = $cs.Name; Domain = $cs.Domain; PartOfDomain = $cs.PartOfDomain; Role = $cs.DomainRole; OS = $os.Caption; Build = $os.BuildNumber; IPv4 = $ip; DNS = $dns -join ', ' }
        } | Select-Object @{n='VM';e={$vm.Name}}, GuestHostname, Domain, PartOfDomain, Role, OS, Build, IPv4, DNS | Format-List | Out-String -Width 250 | Out-File $out -Append -Encoding utf8
    } catch { "VM $($vm.Name): could not connect ($($_.Exception.Message))" | Out-File $out -Append -Encoding utf8 }
}
"`nDone." | Out-File $out -Append -Encoding utf8
Write-Host "Saved to $out"
