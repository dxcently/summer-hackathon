<#
windows-triage.ps1 — read-only first-run triage for Cabal
(Windows Server 2022 / Domain Controller / DNS for rrintel.internal).

Usage (in PowerShell as Administrator on Cabal):
    powershell.exe -ExecutionPolicy Bypass -File windows-triage.ps1

Output: $env:USERPROFILE\.ecitadel\triage-$env:COMPUTERNAME-<utc-timestamp>.log

This script ONLY reads. It does not change any system state.
Safe to run multiple times; each run produces a new log file you can
diff against the previous one to spot deltas.

Section banners use the same format as linux-triage.sh so a single
diff workflow can cover all four boxes.
#>

$ErrorActionPreference = 'Continue'
$ts  = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$WorkDir = Join-Path $env:USERPROFILE '.ecitadel'
if (-not (Test-Path $WorkDir)) {
    $null = New-Item -ItemType Directory -Path $WorkDir -Force
    # Mark hidden so it stays out of Explorer's casual view.
    try { (Get-Item $WorkDir).Attributes = 'Hidden' } catch { }
}
$Out = Join-Path $WorkDir "triage-$env:COMPUTERNAME-$ts.log"

function Write-Section {
    param([string]$Title)
    "`n`n=== $Title ===" | Out-File -FilePath $Out -Append -Encoding utf8
}

function Run {
    param(
        [string]$Label,
        [scriptblock]$Cmd
    )
    "`n--- $Label ---" | Out-File -FilePath $Out -Append -Encoding utf8
    "`$ $($Cmd.ToString().Trim())"  | Out-File -FilePath $Out -Append -Encoding utf8
    try {
        & $Cmd 2>&1 |
            Out-String -Width 240 |
            Out-File -FilePath $Out -Append -Encoding utf8
    } catch {
        "[error] $($_.Exception.Message)" | Out-File -FilePath $Out -Append -Encoding utf8
    }
}

# --- header -----------------------------------------------------------
$os       = Get-CimInstance Win32_OperatingSystem
$uptimeHr = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
$isAdmin  = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
@(
    "eCitadel triage report"
    "host:        $env:COMPUTERNAME"
    "utc:         $((Get-Date).ToUniversalTime())"
    "os:          $($os.Caption) ($($os.Version))"
    "uptime:      $uptimeHr hours"
    "runner:      $env:USERDOMAIN\$env:USERNAME (admin: $isAdmin)"
) | Out-File -FilePath $Out -Encoding utf8

# --- LOCAL USERS / GROUPS --------------------------------------------
Write-Section 'LOCAL USERS / GROUPS'
Run 'local users'                 { Get-LocalUser | Format-Table Name,Enabled,LastLogon,Description -AutoSize }
Run 'local administrators group'  { Get-LocalGroupMember -Group 'Administrators' }
Run 'local remote desktop users'  { Get-LocalGroupMember -Group 'Remote Desktop Users' -ErrorAction SilentlyContinue }

# --- ACTIVE DIRECTORY -------------------------------------------------
Write-Section 'ACTIVE DIRECTORY'
Run 'domain info' {
    Get-ADDomain | Select-Object Forest,DNSRoot,DomainMode,NetBIOSName,PDCEmulator
}
Run 'all AD users with status' {
    Get-ADUser -Filter * -Properties Enabled,LastLogonDate,PasswordLastSet,whenCreated,Description |
        Sort-Object whenCreated -Descending |
        Format-Table Name,SamAccountName,Enabled,whenCreated,PasswordLastSet,LastLogonDate -AutoSize
}
Run 'AD users created in last 7 days' {
    $cutoff = (Get-Date).AddDays(-7)
    Get-ADUser -Filter * -Properties whenCreated,Description |
        Where-Object { $_.whenCreated -gt $cutoff } |
        Format-Table Name,SamAccountName,whenCreated,Description -AutoSize
}
Run 'Domain Admins members'        { Get-ADGroupMember -Identity 'Domain Admins' }
Run 'Enterprise Admins members'    { Get-ADGroupMember -Identity 'Enterprise Admins' -ErrorAction SilentlyContinue }
Run 'Schema Admins members'        { Get-ADGroupMember -Identity 'Schema Admins' -ErrorAction SilentlyContinue }
Run 'Administrators (built-in) members' { Get-ADGroupMember -Identity 'Administrators' }
Run 'Account Operators members'    { Get-ADGroupMember -Identity 'Account Operators' -ErrorAction SilentlyContinue }
Run 'AD computers' {
    Get-ADComputer -Filter * -Properties OperatingSystem,LastLogonDate |
        Format-Table Name,OperatingSystem,LastLogonDate -AutoSize
}
Run 'AD users with non-expiring passwords' {
    Search-ADAccount -PasswordNeverExpires |
        Format-Table Name,SamAccountName,Enabled -AutoSize
}
Run 'AD users with SPNs (Kerberoast surface)' {
    Get-ADUser -Filter 'ServicePrincipalName -like "*"' -Properties ServicePrincipalName |
        Format-Table Name,SamAccountName,ServicePrincipalName -AutoSize
}

# --- SERVICES ---------------------------------------------------------
Write-Section 'SERVICES'
Run 'running services' {
    Get-Service | Where-Object Status -eq 'Running' |
        Sort-Object Name |
        Format-Table Name,DisplayName,StartType -AutoSize
}
Run 'auto-start non-Microsoft services' {
    Get-CimInstance Win32_Service |
        Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName -notmatch 'System32|Program Files \(x86\)\\Microsoft|Program Files\\Microsoft' } |
        Format-Table Name,DisplayName,State,StartMode,PathName -AutoSize
}

# --- SCHEDULED TASKS --------------------------------------------------
Write-Section 'SCHEDULED TASKS'
Run 'enabled non-Microsoft scheduled tasks' {
    Get-ScheduledTask |
        Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '\\Microsoft\\' } |
        Format-Table TaskName,TaskPath,State,Author -AutoSize
}
Run 'tasks running as SYSTEM' {
    Get-ScheduledTask |
        Where-Object { $_.Principal.UserId -eq 'SYSTEM' -and $_.TaskPath -notmatch '\\Microsoft\\' } |
        Format-Table TaskName,TaskPath,State -AutoSize
}

# --- PERSISTENCE VECTORS ---------------------------------------------
Write-Section 'PERSISTENCE VECTORS'
Run 'HKLM Run keys'      { Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue }
Run 'HKLM RunOnce'       { Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -ErrorAction SilentlyContinue }
Run 'HKCU Run keys'      { Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue }
Run 'startup commands (Win32_StartupCommand)' {
    Get-CimInstance Win32_StartupCommand | Format-List Name,Command,Location,User
}
Run 'WMI event filters' {
    Get-CimInstance -Namespace root/subscription -ClassName __EventFilter -ErrorAction SilentlyContinue |
        Format-List Name,Query,QueryLanguage
}
Run 'WMI event consumers' {
    Get-CimInstance -Namespace root/subscription -ClassName CommandLineEventConsumer -ErrorAction SilentlyContinue |
        Format-List Name,CommandLineTemplate,RunInteractively
}
Run 'WMI filter-to-consumer bindings' {
    Get-CimInstance -Namespace root/subscription -ClassName __FilterToConsumerBinding -ErrorAction SilentlyContinue |
        Format-List Filter,Consumer
}

# --- NETWORK ----------------------------------------------------------
Write-Section 'NETWORK'
Run 'IP config'                   { Get-NetIPConfiguration -Detailed | Format-List InterfaceAlias,IPv4Address,DNSServer,IPv4DefaultGateway }
Run 'TCP listeners' {
    Get-NetTCPConnection -State Listen |
        Sort-Object LocalPort |
        Format-Table LocalAddress,LocalPort,@{n='ProcId';e={$_.OwningProcess}},@{n='Process';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} -AutoSize
}
Run 'UDP listeners' {
    Get-NetUDPEndpoint |
        Format-Table LocalAddress,LocalPort,@{n='ProcId';e={$_.OwningProcess}},@{n='Process';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} -AutoSize
}
Run 'established connections' {
    Get-NetTCPConnection -State Established |
        Sort-Object RemoteAddress |
        Format-Table LocalAddress,LocalPort,RemoteAddress,RemotePort,@{n='Process';e={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} -AutoSize
}
Run 'firewall profile state'      { Get-NetFirewallProfile | Format-Table Name,Enabled,DefaultInboundAction,DefaultOutboundAction -AutoSize }

# --- DNS / AD-INTEGRATED ZONE ----------------------------------------
Write-Section 'DNS'
Run 'DNS server zones'            { Get-DnsServerZone | Format-Table ZoneName,ZoneType,DynamicUpdate,IsAutoCreated -AutoSize }
Run 'rrintel.internal records'    { Get-DnsServerResourceRecord -ZoneName 'rrintel.internal' | Format-Table HostName,RecordType,RecordData -AutoSize }
Run 'DNS resolves locally'        { Resolve-DnsName -Server 127.0.0.1 -Name 'rrintel.internal' }

# --- FILE SHARES ------------------------------------------------------
Write-Section 'SMB SHARES + SESSIONS'
Run 'SMB shares'                  { Get-SmbShare | Format-Table Name,Path,Description -AutoSize }
Run 'SMB sessions'                { Get-SmbSession | Format-Table ClientComputerName,ClientUserName,NumOpens -AutoSize }
Run 'SMB server config'           { Get-SmbServerConfiguration | Select EnableSMB1Protocol,EnableSMB2Protocol,RequireSecuritySignature }
Run 'SmbShare permissions' {
    foreach ($s in (Get-SmbShare).Name) {
        "## $s"
        Get-SmbShareAccess -Name $s -ErrorAction SilentlyContinue
    }
}

# --- SESSIONS + RDP ---------------------------------------------------
Write-Section 'INTERACTIVE SESSIONS'
Run 'qwinsta'                     { qwinsta }
Run 'logged-on users (last 50 events, type 2/10)' {
    Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4624] and EventData[Data[@Name='LogonType']='2' or Data[@Name='LogonType']='10']]" -MaxEvents 50 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated,@{n='Account';e={$_.Properties[5].Value}},@{n='Type';e={$_.Properties[8].Value}} -AutoSize
}

# --- DEFENDER ---------------------------------------------------------
Write-Section 'DEFENDER'
Run 'Defender status'             { Get-MpComputerStatus | Format-List AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,IoavProtectionEnabled,BehaviorMonitorEnabled,AntivirusSignatureLastUpdated }
Run 'Defender preference'         { Get-MpPreference | Format-List DisableRealtimeMonitoring,DisableScriptScanning,ExclusionPath,ExclusionProcess,ExclusionExtension }
Run 'Defender threat history'     { Get-MpThreatDetection -ErrorAction SilentlyContinue | Format-Table InitialDetectionTime,ThreatID,Resources -AutoSize }

# --- RECENT EVENTS ----------------------------------------------------
Write-Section 'RECENT SECURITY EVENTS'
Run 'last 30 successful logons (4624)' {
    Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4624]]" -MaxEvents 30 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated,@{n='Account';e={$_.Properties[5].Value}},@{n='LogonType';e={$_.Properties[8].Value}},@{n='SourceIP';e={$_.Properties[18].Value}} -AutoSize
}
Run 'last 30 failed logons (4625)' {
    Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4625]]" -MaxEvents 30 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated,@{n='Account';e={$_.Properties[5].Value}},@{n='SourceIP';e={$_.Properties[19].Value}} -AutoSize
}
Run 'last 20 AD user-created (4720)' {
    Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4720]]" -MaxEvents 20 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated,@{n='NewAccount';e={$_.Properties[0].Value}},@{n='Creator';e={$_.Properties[4].Value}} -AutoSize
}
Run 'last 20 AD group-member-added (4732 + 4756)' {
    Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4732 or EventID=4756)]]" -MaxEvents 20 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated,Id,Message -Wrap
}
Run 'last 20 service installs (7045 - System)' {
    Get-WinEvent -LogName System -FilterXPath "*[System[EventID=7045]]" -MaxEvents 20 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated,@{n='Service';e={$_.Properties[0].Value}},@{n='Path';e={$_.Properties[1].Value}},@{n='Account';e={$_.Properties[4].Value}} -AutoSize
}

# --- RECENTLY MODIFIED FILES -----------------------------------------
Write-Section 'RECENTLY MODIFIED FILES (last 7 days)'
$cutoff7 = (Get-Date).AddDays(-7)
Run 'C:\ProgramData recent files' {
    Get-ChildItem 'C:\ProgramData' -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff7 } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 50 |
        Format-Table LastWriteTime,Length,FullName -AutoSize
}
Run 'C:\Users\Public recent files' {
    Get-ChildItem 'C:\Users\Public' -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff7 } |
        Format-Table LastWriteTime,Length,FullName -AutoSize
}
Run 'C:\Windows\Temp recent files' {
    Get-ChildItem 'C:\Windows\Temp' -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $cutoff7 } |
        Format-Table LastWriteTime,Length,FullName -AutoSize
}

# --- AUDIT POLICY -----------------------------------------------------
Write-Section 'AUDIT POLICY'
Run 'audit policy (auditpol /get)' { auditpol /get /category:* }

# --- DONE -------------------------------------------------------------
Write-Section 'DONE'
"`nReport written to: $Out" | Out-File -FilePath $Out -Append -Encoding utf8

Write-Host "Triage complete."
Write-Host "Report: $Out"
Write-Host ""
Write-Host "Suggested next steps:"
Write-Host "  1. Copy the report off the box to your shared notes."
Write-Host "     ls $WorkDir"
Write-Host "  2. Diff against the next run with: Compare-Object (gc prev.log) (gc this.log)"
Write-Host "  3. Cross-check findings against docs/02-hardening.md (Cabal section)"
