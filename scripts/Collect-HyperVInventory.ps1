<#
  Collect-HyperVInventory.ps1
  Read-only inventory of a Hyper-V host and, where the tools are present,
  its Active Directory domain, DNS and DHCP. Changes nothing.
  Run in an elevated PowerShell window (Run as administrator).
  Output: HyperV-Inventory-<computername>.txt next to this script.
#>
$ErrorActionPreference = 'Continue'
$out = Join-Path $PSScriptRoot ("HyperV-Inventory-{0}.txt" -f $env:COMPUTERNAME)

function Section($title, [scriptblock]$body) {
    "`n### $title" | Out-File $out -Append -Encoding utf8
    try { & $body 2>&1 | Out-String -Width 250 | Out-File $out -Append -Encoding utf8 }
    catch { "ERROR: $($_.Exception.Message)" | Out-File $out -Append -Encoding utf8 }
}

"Inventory of $env:COMPUTERNAME taken $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-File $out -Encoding utf8

# ---------- Host ----------
Section 'HOST SYSTEM' { Get-CimInstance Win32_ComputerSystem | Format-List Name, Domain, PartOfDomain, DomainRole, Manufacturer, Model, NumberOfProcessors, NumberOfLogicalProcessors, TotalPhysicalMemory }
Section 'HOST OS' { Get-CimInstance Win32_OperatingSystem | Format-List Caption, Version, BuildNumber, OSArchitecture, InstallDate, LastBootUpTime }
Section 'HOST CPU' { Get-CimInstance Win32_Processor | Format-List Name, NumberOfCores, NumberOfLogicalProcessors, VirtualizationFirmwareEnabled, SecondLevelAddressTranslationExtensions }
Section 'HOST DISKS' { Get-PhysicalDisk | Format-Table FriendlyName, MediaType, BusType, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, HealthStatus -AutoSize }
Section 'HOST VOLUMES' { Get-Volume | Where-Object DriveLetter | Format-Table DriveLetter, FileSystemLabel, FileSystem, @{n='SizeGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB,1)}} -AutoSize }
Section 'HOST NETWORK ADAPTERS' { Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, LinkSpeed, MacAddress, VlanID -AutoSize }
Section 'HOST IP CONFIGURATION' { Get-NetIPConfiguration | Format-List InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer }
Section 'WINDOWS FEATURES (servers only)' { Get-WindowsFeature | Where-Object Installed | Format-Table Name, DisplayName -AutoSize }
Section 'HYPER-V OPTIONAL FEATURE (clients)' { Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All | Format-List FeatureName, State }

# ---------- Hyper-V ----------
Section 'HYPER-V HOST SETTINGS' { Get-VMHost | Format-List ComputerName, LogicalProcessorCount, @{n='MemoryGB';e={[math]::Round($_.MemoryCapacity/1GB,1)}}, VirtualHardDiskPath, VirtualMachinePath, VirtualMachineMigrationEnabled, EnableEnhancedSessionMode, NumaSpanningEnabled }
Section 'VIRTUAL SWITCHES' { Get-VMSwitch | Format-Table Name, SwitchType, NetAdapterInterfaceDescription, AllowManagementOS, EmbeddedTeamingEnabled -AutoSize }
Section 'HOST VIRTUAL NICS' { Get-VMNetworkAdapter -ManagementOS | Format-Table Name, SwitchName, MacAddress, IPAddresses -AutoSize }
Section 'VIRTUAL MACHINES' { Get-VM | Sort-Object Name | Format-Table Name, State, Generation, Version, ProcessorCount, @{n='StartupGB';e={[math]::Round($_.MemoryStartup/1GB,1)}}, DynamicMemoryEnabled, AutomaticStartAction, AutomaticStopAction, CheckpointType, Uptime -AutoSize }
Section 'VM MEMORY' { Get-VM | Get-VMMemory | Format-Table VMName, DynamicMemoryEnabled, @{n='StartupMB';e={$_.Startup/1MB}}, @{n='MinMB';e={$_.Minimum/1MB}}, @{n='MaxMB';e={$_.Maximum/1MB}} -AutoSize }
Section 'VM NETWORK ADAPTERS' { Get-VM | Get-VMNetworkAdapter | Format-Table VMName, Name, SwitchName, MacAddress, @{n='IPs';e={$_.IPAddresses -join ', '}} -AutoSize }
Section 'VM VLANS' { Get-VM | Get-VMNetworkAdapterVlan | Format-Table ParentAdapter, OperationMode, AccessVlanId, NativeVlanId, AllowedVlanIdList -AutoSize }
Section 'VM DISKS' { Get-VM | Get-VMHardDiskDrive | Format-Table VMName, ControllerType, ControllerNumber, ControllerLocation, Path -AutoSize }
Section 'VIRTUAL HARD DISKS' { Get-VM | Get-VMHardDiskDrive | Where-Object Path | ForEach-Object { Get-VHD -Path $_.Path } | Format-Table Path, VhdFormat, VhdType, @{n='MaxGB';e={[math]::Round($_.Size/1GB,1)}}, @{n='UsedGB';e={[math]::Round($_.FileSize/1GB,1)}}, ParentPath -AutoSize }
Section 'VM DVD DRIVES' { Get-VM | Get-VMDvdDrive | Format-Table VMName, Path -AutoSize }
Section 'VM FIRMWARE AND SECURITY (Gen 2)' { Get-VM | Where-Object Generation -eq 2 | ForEach-Object { $f = Get-VMFirmware $_; $s = Get-VMSecurity $_; [pscustomobject]@{ VM = $_.Name; SecureBoot = $f.SecureBoot; Template = $f.SecureBootTemplate; TPM = $s.TpmEnabled; Shielded = $s.Shielded } } | Format-Table -AutoSize }
Section 'VM CHECKPOINTS' { Get-VM | Get-VMSnapshot | Format-Table VMName, Name, SnapshotType, CreationTime, ParentSnapshotName -AutoSize }
Section 'VM INTEGRATION SERVICES' { Get-VM | Get-VMIntegrationService | Format-Table VMName, Name, Enabled, PrimaryStatusDescription -AutoSize }
Section 'VM REPLICATION' { Get-VMReplication | Format-Table VMName, State, Health, Mode, PrimaryServer, ReplicaServer, FrequencySec -AutoSize }
Section 'VM NOTES' { Get-VM | Where-Object Notes | Format-List Name, Notes }

# ---------- Active Directory (needs the AD module: a domain controller or RSAT) ----------
Section 'AD DOMAIN' { Get-ADDomain | Format-List DNSRoot, NetBIOSName, DomainMode, Forest, PDCEmulator, RIDMaster, InfrastructureMaster, DistinguishedName }
Section 'AD FOREST' { Get-ADForest | Format-List Name, ForestMode, SchemaMaster, DomainNamingMaster, Domains, GlobalCatalogs, Sites, UPNSuffixes }
Section 'AD DOMAIN CONTROLLERS' { Get-ADDomainController -Filter * | Format-Table HostName, IPv4Address, Site, IsGlobalCatalog, IsReadOnly, OperatingSystem -AutoSize }
Section 'AD SITES AND SUBNETS' { Get-ADReplicationSite -Filter * | Format-Table Name; Get-ADReplicationSubnet -Filter * | Format-Table Name, Site -AutoSize }
Section 'AD TRUSTS' { Get-ADTrust -Filter * | Format-Table Name, Direction, TrustType, ForestTransitive -AutoSize }
Section 'AD ORGANIZATIONAL UNITS' { Get-ADOrganizationalUnit -Filter * | Sort-Object DistinguishedName | Format-Table Name, DistinguishedName -AutoSize }
Section 'AD COUNTS' { [pscustomobject]@{ Users = (Get-ADUser -Filter *).Count; EnabledUsers = (Get-ADUser -Filter 'Enabled -eq $true').Count; Groups = (Get-ADGroup -Filter *).Count; Computers = (Get-ADComputer -Filter *).Count } | Format-List }
Section 'AD COMPUTERS' { Get-ADComputer -Filter * -Properties OperatingSystem, IPv4Address | Sort-Object Name | Format-Table Name, OperatingSystem, IPv4Address, Enabled -AutoSize }
Section 'AD GROUPS (non built-in)' { Get-ADGroup -Filter * -Properties Description | Where-Object { $_.DistinguishedName -notmatch 'CN=Builtin|CN=Users,' } | Format-Table Name, GroupScope, GroupCategory, Description -AutoSize }
Section 'AD PRIVILEGED GROUP MEMBERS' { 'Domain Admins', 'Enterprise Admins', 'Schema Admins' | ForEach-Object { $g = $_; Get-ADGroupMember $g | Select-Object @{n='Group';e={$g}}, Name, objectClass } | Format-Table -AutoSize }
Section 'AD PASSWORD POLICY' { Get-ADDefaultDomainPasswordPolicy | Format-List MinPasswordLength, PasswordHistoryCount, MaxPasswordAge, MinPasswordAge, ComplexityEnabled, LockoutThreshold, LockoutDuration }
Section 'GROUP POLICY OBJECTS' { Get-GPO -All | Sort-Object DisplayName | Format-Table DisplayName, GpoStatus, CreationTime, ModificationTime -AutoSize }
Section 'GROUP POLICY LINKS' { Get-ADOrganizationalUnit -Filter * | ForEach-Object { $ou = $_; (Get-GPInheritance -Target $ou.DistinguishedName).GpoLinks | Select-Object @{n='OU';e={$ou.Name}}, DisplayName, Enabled, Enforced } | Format-Table -AutoSize }

# ---------- DNS and DHCP (need those roles or RSAT) ----------
Section 'DNS ZONES' { Get-DnsServerZone | Format-Table ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone, DynamicUpdate -AutoSize }
Section 'DNS FORWARDERS' { Get-DnsServerForwarder | Format-List IPAddress, UseRootHint }
Section 'DHCP SCOPES' { Get-DhcpServerv4Scope | Format-Table ScopeId, Name, StartRange, EndRange, SubnetMask, State, LeaseDuration -AutoSize }
Section 'DHCP SCOPE OPTIONS' { Get-DhcpServerv4Scope | ForEach-Object { Get-DhcpServerv4OptionValue -ScopeId $_.ScopeId | Select-Object @{n='Scope';e={$_.ScopeId}}, OptionId, Name, @{n='Value';e={$_.Value -join ', '}} } | Format-Table -AutoSize }
Section 'SMB SHARES' { Get-SmbShare | Where-Object { $_.Name -notmatch '^\w\$$|^ADMIN\$$|^IPC\$$' } | Format-Table Name, Path, Description -AutoSize }

"`nDone." | Out-File $out -Append -Encoding utf8
Write-Host "Saved to $out"
