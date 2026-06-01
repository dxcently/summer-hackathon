# check-policy-windows.ps1 — read-only audit of Windows / AD password
# policy and account state on Cabal (or any Windows host).
#
# Categorical pass/warn/fail output. Same convention as the Linux
# check-policy-linux.sh — `[ ok ] / [warn] / [FAIL] / [info]` lines.
#
# What it flags:
#   - net accounts (local SAM policy):
#       MinimumPasswordLength       FAIL < HardMinLen, WARN < MinLen
#       MaximumPasswordAge          WARN > MaxAgeDays
#       MinimumPasswordAge          WARN < MinAgeDays (allows immediate cycling)
#       LockoutThreshold            FAIL = 0, WARN > 10
#       PasswordHistoryLength       WARN < 5
#   - Get-ADDefaultDomainPasswordPolicy (only on a DC w/ AD module):
#       ComplexityEnabled, ReversibleEncryption, MinPasswordLength,
#       MaxPasswordAge, MinPasswordAge, LockoutThreshold,
#       PasswordHistoryCount
#   - Local accounts:
#       Administrator (RID 500)     FAIL if enabled, WARN if name unchanged
#       Guest         (RID 501)     FAIL if enabled
#       DefaultAccount(RID 503)     WARN if enabled
#       Any account with PasswordRequired=False        -> FAIL
#       Any enabled account with PasswordNeverExpires  -> WARN
#   - AD accounts (only on a DC):
#       Built-in AD Administrator / Guest enabled state
#       krbtgt password age (> 180 days -> WARN)
#       Domain Admins membership listing + count
#       PasswordNotRequired -> FAIL
#       PasswordNeverExpires + enabled -> WARN
#   - LSA registry:
#       LimitBlankPasswordUse       FAIL if = 0
#       NoLMHash                    FAIL if = 0 (LM hashes stored)
#
# Read-only. Does not change config. Safe to run repeatedly.
#
# Usage (elevated PowerShell):
#   powershell.exe -ExecutionPolicy Bypass -File check-policy-windows.ps1
#   .\check-policy-windows.ps1 -MinLen 16 -HardMinLen 8 -MaxAgeDays 60

[CmdletBinding()]
param(
    [int]$MinLen     = 14,   # WARN if min password length < this
    [int]$HardMinLen = 6,    # FAIL if min password length < this
    [int]$MaxAgeDays = 90,   # WARN if max password age > this
    [int]$MinAgeDays = 1     # WARN if min password age < this
)

$ErrorActionPreference = 'SilentlyContinue'

# --- workdir + log --------------------------------------------------
$WorkDir = Join-Path $env:USERPROFILE '.ecitadel'
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}
try { (Get-Item $WorkDir).Attributes = 'Hidden' } catch {}

$ts  = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$out = Join-Path $WorkDir "policy-$env:COMPUTERNAME-$ts.log"

# --- counters + helpers ---------------------------------------------
$script:pass = 0; $script:warn = 0; $script:fail = 0

function Write-Line([string]$line) {
    Write-Host $line
    Add-Content -Path $out -Value $line
}
function Section([string]$s) { Write-Line ""; Write-Line "=== $s ===" }
function OK([string]$s)   { $script:pass++; Write-Line "  [ ok ]  $s" }
function Warn2([string]$s){ $script:warn++; Write-Line "  [warn]  $s" }
function Fail2([string]$s){ $script:fail++; Write-Line "  [FAIL]  $s" }
function Info2([string]$s){                Write-Line "  [info]  $s" }

# --- header ---------------------------------------------------------
Set-Content -Path $out -Value "eCitadel policy audit (windows)"
Write-Host "eCitadel policy audit (windows)"
Write-Line "host:    $env:COMPUTERNAME"
Write-Line "utc:     $((Get-Date).ToUniversalTime().ToString('s'))Z"
Write-Line "user:    $env:USERNAME"
Write-Line "thresholds: hard_min_len=$HardMinLen warn_min_len=$MinLen max_age=${MaxAgeDays}d min_age=${MinAgeDays}d"

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Warn2 "not running as Administrator — some checks will be incomplete"
}

# --- 1. net accounts (local SAM policy) -----------------------------
Section 'LOCAL SAM POLICY (net accounts)'

try {
    $na = & net accounts 2>$null
    $na | ForEach-Object { Add-Content -Path $out -Value "    $_" }

    function Get-NetField([string]$label) {
        $line = $na | Where-Object { $_ -match [regex]::Escape($label) } | Select-Object -First 1
        if ($line) { return ($line -split ':',2)[1].Trim() }
        return $null
    }

    $minLenVal  = Get-NetField 'Minimum password length'
    $maxAgeVal  = Get-NetField 'Maximum password age'
    $minAgeVal  = Get-NetField 'Minimum password age'
    $lockThrVal = Get-NetField 'Lockout threshold'
    $histVal    = Get-NetField 'Length of password history'

    if ($minLenVal -match '^\d+') {
        $n = [int]$Matches[0]
        if     ($n -lt $HardMinLen) { Fail2 "MinimumPasswordLength=$n (< $HardMinLen)" }
        elseif ($n -lt $MinLen)     { Warn2 "MinimumPasswordLength=$n (< $MinLen)" }
        else                        { OK    "MinimumPasswordLength=$n" }
    } else {
        Warn2 "MinimumPasswordLength unreadable ($minLenVal)"
    }

    if ($maxAgeVal -match 'Unlimited|Never') {
        Warn2 "MaximumPasswordAge=$maxAgeVal (never expires)"
    } elseif ($maxAgeVal -match '^(\d+)') {
        $n = [int]$Matches[1]
        if ($n -gt $MaxAgeDays) { Warn2 "MaximumPasswordAge=$n (> $MaxAgeDays)" }
        else                    { OK    "MaximumPasswordAge=$n" }
    }

    if ($minAgeVal -match '^(\d+)') {
        $n = [int]$Matches[1]
        if ($n -lt $MinAgeDays) { Warn2 "MinimumPasswordAge=$n (< $MinAgeDays — allows immediate cycling of history)" }
        else                    { OK    "MinimumPasswordAge=$n" }
    }

    if ($lockThrVal -match '^(\d+)') {
        $n = [int]$Matches[1]
        if     ($n -eq 0)  { Fail2 "LockoutThreshold=0 (no lockout — brute force open)" }
        elseif ($n -gt 10) { Warn2 "LockoutThreshold=$n (> 10)" }
        else               { OK    "LockoutThreshold=$n" }
    } elseif ($lockThrVal -match 'Never') {
        Fail2 "LockoutThreshold=Never — no lockout"
    }

    if ($histVal -match '^(\d+)') {
        $n = [int]$Matches[1]
        if ($n -lt 5) { Warn2 "PasswordHistoryLength=$n (< 5)" }
        else          { OK    "PasswordHistoryLength=$n" }
    }
} catch {
    Warn2 "net accounts failed: $($_.Exception.Message)"
}

# --- 2. AD default domain password policy ---------------------------
Section 'AD DEFAULT DOMAIN PASSWORD POLICY'

if (Get-Command Get-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue) {
    try {
        $p = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop
        Info2 "Domain: $($p.DistinguishedName)"

        if (-not $p.ComplexityEnabled) { Fail2 'ComplexityEnabled=False' }
        else                            { OK   'ComplexityEnabled=True' }

        if ($p.ReversibleEncryptionEnabled) { Fail2 'ReversibleEncryptionEnabled=True (crypto backdoor)' }
        else                                 { OK    'ReversibleEncryptionEnabled=False' }

        if     ($p.MinPasswordLength -lt $HardMinLen) { Fail2 "AD MinPasswordLength=$($p.MinPasswordLength) (< $HardMinLen)" }
        elseif ($p.MinPasswordLength -lt $MinLen)     { Warn2 "AD MinPasswordLength=$($p.MinPasswordLength) (< $MinLen)" }
        else                                           { OK    "AD MinPasswordLength=$($p.MinPasswordLength)" }

        $maxDays = [math]::Round($p.MaxPasswordAge.TotalDays)
        if     ($maxDays -le 0)            { Warn2 'AD MaxPasswordAge=never' }
        elseif ($maxDays -gt $MaxAgeDays)  { Warn2 "AD MaxPasswordAge=${maxDays}d (> $MaxAgeDays)" }
        else                                { OK    "AD MaxPasswordAge=${maxDays}d" }

        $minDays = [math]::Round($p.MinPasswordAge.TotalDays)
        if ($minDays -lt $MinAgeDays) { Warn2 "AD MinPasswordAge=${minDays}d (< $MinAgeDays)" }
        else                          { OK    "AD MinPasswordAge=${minDays}d" }

        if ($p.LockoutThreshold -eq 0)    { Fail2 'AD LockoutThreshold=0 (no lockout)' }
        elseif ($p.LockoutThreshold -gt 10){ Warn2 "AD LockoutThreshold=$($p.LockoutThreshold)" }
        else                               { OK    "AD LockoutThreshold=$($p.LockoutThreshold)" }

        if ($p.PasswordHistoryCount -lt 5) { Warn2 "AD PasswordHistoryCount=$($p.PasswordHistoryCount) (< 5)" }
        else                                { OK    "AD PasswordHistoryCount=$($p.PasswordHistoryCount)" }
    } catch {
        Info2 "Not on a DC or AD module unloaded: $($_.Exception.Message)"
    }
} else {
    Info2 'Get-ADDefaultDomainPasswordPolicy not available — skipping AD policy'
}

# --- 3. local accounts ---------------------------------------------
Section 'LOCAL ACCOUNTS'

try {
    $locals = Get-LocalUser -ErrorAction Stop
    foreach ($u in $locals | Sort-Object @{e='Enabled';desc=$true}, Name) {
        $sid = $u.SID.Value

        if ($sid -match '-500$') {
            if ($u.Enabled) { Fail2 "Administrator (RID 500, name=$($u.Name)) ENABLED — rename + disable" }
            else             { OK    "Administrator (RID 500, name=$($u.Name)) disabled" }
            if ($u.Name -eq 'Administrator') {
                Warn2 "Administrator name unchanged — rename for obfuscation"
            }

        } elseif ($sid -match '-501$') {
            if ($u.Enabled) { Fail2 "Guest (RID 501, name=$($u.Name)) ENABLED — disable" }
            else             { OK    "Guest (RID 501, name=$($u.Name)) disabled" }

        } elseif ($sid -match '-503$') {
            if ($u.Enabled) { Warn2 "DefaultAccount (RID 503) enabled" }
            else             { OK    "DefaultAccount (RID 503) disabled" }

        } elseif ($u.Name -in @('WDAGUtilityAccount','DefaultAccount')) {
            Info2 "$($u.Name) enabled=$($u.Enabled)"

        } else {
            $tag = if ($u.Enabled) { 'enabled' } else { 'disabled' }
            Info2 "user: $($u.Name) $tag sid=$sid"
            if ($u.PasswordRequired -eq $false) {
                Fail2 "$($u.Name): PasswordRequired=False"
            }
            if ($u.Enabled -and $null -eq $u.PasswordExpires) {
                Warn2 "$($u.Name): PasswordNeverExpires"
            }
        }
    }
} catch {
    Warn2 "Get-LocalUser failed: $($_.Exception.Message)"
}

# --- 4. AD accounts (only on a DC) ---------------------------------
Section 'AD ACCOUNTS'

if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
    try {
        $adAdmin = Get-ADUser -Filter 'SID -like "*-500"' -Properties Enabled,Name -ErrorAction Stop
        if ($adAdmin) {
            if ($adAdmin.Enabled) { Fail2 "AD Administrator (RID 500, name=$($adAdmin.Name)) ENABLED" }
            else                  { OK    "AD Administrator (RID 500) disabled" }
            if ($adAdmin.Name -eq 'Administrator') {
                Warn2 'AD Administrator name unchanged'
            }
        }

        $adGuest = Get-ADUser -Filter 'SID -like "*-501"' -Properties Enabled -ErrorAction SilentlyContinue
        if ($adGuest) {
            if ($adGuest.Enabled) { Fail2 "AD Guest (RID 501, name=$($adGuest.Name)) ENABLED" }
            else                  { OK    "AD Guest (RID 501) disabled" }
        }

        $krb = Get-ADUser -Identity krbtgt -Properties Enabled,PasswordLastSet -ErrorAction SilentlyContinue
        if ($krb -and $krb.PasswordLastSet) {
            $age = ((Get-Date) - $krb.PasswordLastSet).Days
            if ($age -gt 180) { Warn2 "krbtgt password is $age days old — rotate (twice, > 10h apart)" }
            else              { OK    "krbtgt password age = $age days" }
        }

        $noReq = Get-ADUser -Filter { PasswordNotRequired -eq $true } -Properties PasswordNotRequired
        if ($noReq) {
            Fail2 "AD accounts with PasswordNotRequired=True:"
            $noReq | ForEach-Object { Write-Line "      - $($_.SamAccountName)" }
        } else {
            OK 'no AD accounts with PasswordNotRequired'
        }

        $noExp = Get-ADUser -Filter { PasswordNeverExpires -eq $true -and Enabled -eq $true } `
            -Properties PasswordNeverExpires
        if ($noExp) {
            Warn2 "enabled AD accounts with PasswordNeverExpires:"
            $noExp | ForEach-Object { Write-Line "      - $($_.SamAccountName)" }
        } else {
            OK 'no enabled AD accounts with PasswordNeverExpires'
        }

        $da = Get-ADGroupMember -Identity 'Domain Admins' -Recursive -ErrorAction SilentlyContinue
        if ($da) {
            Info2 "Domain Admins ($($da.Count) member(s)):"
            $da | ForEach-Object { Write-Line "      - $($_.SamAccountName)" }
            if ($da.Count -gt 5) { Warn2 "Domain Admins has $($da.Count) members — prune to essentials" }
        }

        $ea = Get-ADGroupMember -Identity 'Enterprise Admins' -Recursive -ErrorAction SilentlyContinue
        if ($ea) {
            Info2 "Enterprise Admins ($($ea.Count) member(s)):"
            $ea | ForEach-Object { Write-Line "      - $($_.SamAccountName)" }
            if ($ea.Count -gt 1) { Warn2 "Enterprise Admins has $($ea.Count) members — should typically be 0 or 1" }
        }
    } catch {
        Info2 "AD account checks skipped: $($_.Exception.Message)"
    }
} else {
    Info2 'Get-ADUser not available (not a DC) — skipping AD account checks'
}

# --- 5. LSA / blank-password restrictions --------------------------
Section 'LSA / LOGON RESTRICTIONS'

$lsaPath = 'HKLM:\System\CurrentControlSet\Control\Lsa'

$lblank = Get-ItemProperty $lsaPath -Name LimitBlankPasswordUse -ErrorAction SilentlyContinue
if ($null -ne $lblank.LimitBlankPasswordUse) {
    if ($lblank.LimitBlankPasswordUse -eq 1) { OK   'LimitBlankPasswordUse=1' }
    else                                       { Fail2 "LimitBlankPasswordUse=$($lblank.LimitBlankPasswordUse) (blank passwords usable network-wide)" }
} else {
    Info2 'LimitBlankPasswordUse not set (default = 1)'
}

$noLM = Get-ItemProperty $lsaPath -Name NoLMHash -ErrorAction SilentlyContinue
if ($null -ne $noLM.NoLMHash) {
    if ($noLM.NoLMHash -eq 1) { OK    'NoLMHash=1 (LM hashes disabled)' }
    else                      { Fail2 "NoLMHash=$($noLM.NoLMHash) — LM hashes stored" }
} else {
    Info2 'NoLMHash not set (default = 1 on modern Windows)'
}

# --- summary -------------------------------------------------------
Section 'SUMMARY'

$total = $script:pass + $script:warn + $script:fail
Write-Line ""
Write-Line "  passed:  $($script:pass)"
Write-Line "  warn:    $($script:warn)"
Write-Line "  failed:  $($script:fail)"
Write-Line "  total:   $total"
Write-Line ""

if     ($script:fail -gt 0) { Write-Line "  [!]  $($script:fail) hard failures — see $out" }
elseif ($script:warn -gt 0) { Write-Line "  [.]  $($script:warn) warnings — see $out" }
else                         { Write-Line "  [+]  policy looks clean" }

Write-Host ""
Write-Host "Full log: $out"
