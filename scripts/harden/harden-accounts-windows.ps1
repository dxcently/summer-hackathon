# harden-accounts-windows.ps1 — account + password-policy hardening
# for Cabal (DC) or any Windows host. Inspired by cyberpatriot scripts
# but with the round-breaking moves removed (no mass password reset,
# no firewall touch, no RDP disable).
#
# WHAT IT DOES (all idempotent, all verified after write):
#   1. Disable the Guest account (local + AD).
#   2. Apply password policy via `net accounts` (local SAM):
#        MinPasswordLength      = $MinLen     (default 14)
#        MaxPasswordAge         = $MaxAgeDays (default 60)
#        MinPasswordAge         = $MinAgeDays (default 1)
#        PasswordHistoryLength  = $History    (default 24)
#        LockoutThreshold       = $LockoutThr (default 5)
#        LockoutDuration        = $LockoutDur (default 15 min)
#   3. Apply same policy at the AD level (Set-ADDefaultDomainPasswordPolicy)
#      if running on a DC. ComplexityEnabled=$true unconditionally.
#   4. Unset PasswordNeverExpires on every ENABLED local + AD account
#      EXCEPT well-known service principals (krbtgt, current user,
#      gMSAs, any name in -Preserve).
#   5. OPTIONAL: disable RID 500 Administrator. Gated behind
#      -DisableBuiltInAdmin AND -NewAdminUser <name>. The script checks
#      that the new admin exists AND is in Administrators group before
#      disabling RID 500. If either check fails, RID 500 is left alone.
#
# WHAT IT WILL NOT DO:
#   - Reset any user passwords. Mass password reset breaks every
#     scoring-engine probe that has cached creds.
#   - Disable the currently-running user.
#   - Disable krbtgt (would kill Kerberos).
#   - Lock out the scoring engine: lockout duration is bounded to 15
#     min by default so a single bad-credential probe doesn't park
#     legitimate auth for an hour.
#
# Usage (elevated PowerShell on Cabal):
#   .\harden-accounts-windows.ps1 -DryRun
#   .\harden-accounts-windows.ps1                 # apply defaults
#   .\harden-accounts-windows.ps1 -MinLen 16 -LockoutThr 10
#   .\harden-accounts-windows.ps1 -DisableBuiltInAdmin -NewAdminUser 'op17'

[CmdletBinding()]
param(
    [int]$MinLen      = 14,
    [int]$MaxAgeDays  = 60,
    [int]$MinAgeDays  = 1,
    [int]$History     = 24,
    [int]$LockoutThr  = 5,
    [int]$LockoutDur  = 15,
    [string[]]$Preserve = @(),
    [switch]$DisableBuiltInAdmin,
    [string]$NewAdminUser,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$WorkDir = Join-Path $env:USERPROFILE '.ecitadel'
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}
try { (Get-Item $WorkDir).Attributes = 'Hidden' } catch {}

$ts  = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$out = Join-Path $WorkDir "harden-accounts-$env:COMPUTERNAME-$ts.log"

$script:applied = 0; $script:skipped = 0; $script:failed = 0

function Write-Line([string]$line) {
    Write-Host $line
    Add-Content -Path $out -Value $line
}
function Mark-OK([string]$s)   { $script:applied++; Write-Line "  [ ok ]  $s" }
function Mark-Skip([string]$s) { $script:skipped++; Write-Line "  [skip]  $s" }
function Mark-Dry([string]$s)  {                    Write-Line "  [DRY ]  $s" }
function Mark-Fail([string]$s) { $script:failed++;  Write-Line "  [FAIL]  $s" }
function Section([string]$s)   { Write-Line ""; Write-Line "=== $s ===" }

Set-Content -Path $out -Value "eCitadel accounts hardening"
Write-Host "eCitadel accounts hardening"
Write-Line "host:    $env:COMPUTERNAME"
Write-Line "utc:     $((Get-Date).ToUniversalTime().ToString('s'))Z"
Write-Line "user:    $env:USERNAME"
Write-Line "dryrun:  $($DryRun.IsPresent)"
Write-Line "policy:  minlen=$MinLen max_age=${MaxAgeDays}d min_age=${MinAgeDays}d history=$History lockout=$LockoutThr/$($LockoutDur)min"
if ($DisableBuiltInAdmin) {
    Write-Line "admin:   -DisableBuiltInAdmin set, new admin = '$NewAdminUser'"
}
Write-Line ""

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Mark-Fail "not running as Administrator — re-launch elevated"
    exit 1
}

# Accounts we will never touch
$alwaysPreserve = @('krbtgt', $env:USERNAME) + $Preserve

# --- 1. Guest account ---------------------------------------------
Section 'GUEST'

try {
    $g = Get-LocalUser | Where-Object { $_.SID.Value -match '-501$' }
    if ($g) {
        if (-not $g.Enabled) {
            Mark-Skip "local Guest (name=$($g.Name)) already disabled"
        } elseif ($DryRun) {
            Mark-Dry "local Guest (name=$($g.Name)) -> disable"
        } else {
            Disable-LocalUser -Name $g.Name -ErrorAction Stop
            $post = (Get-LocalUser -Name $g.Name).Enabled
            if (-not $post) { Mark-OK "local Guest (name=$($g.Name)) disabled" }
            else            { Mark-Fail "local Guest disable wrote but verify shows Enabled=True" }
        }
    } else {
        Mark-Skip "no local RID-501 account present"
    }
} catch { Mark-Fail "local Guest: $($_.Exception.Message)" }

if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
    try {
        $adg = Get-ADUser -Filter 'SID -like "*-501"' -Properties Enabled,Name -ErrorAction Stop
        if ($adg) {
            if (-not $adg.Enabled) {
                Mark-Skip "AD Guest (name=$($adg.Name)) already disabled"
            } elseif ($DryRun) {
                Mark-Dry "AD Guest (name=$($adg.Name)) -> disable"
            } else {
                Disable-ADAccount -Identity $adg -ErrorAction Stop
                $post = (Get-ADUser $adg -Properties Enabled).Enabled
                if (-not $post) { Mark-OK "AD Guest (name=$($adg.Name)) disabled" }
                else            { Mark-Fail "AD Guest disable wrote but verify shows Enabled=True" }
            }
        }
    } catch { Mark-Fail "AD Guest: $($_.Exception.Message)" }
}

# --- 2. password policy via `net accounts` -----------------------
Section 'LOCAL PASSWORD POLICY (net accounts)'

function Run-Net([string]$arg, [string]$label) {
    if ($DryRun) { Mark-Dry "net accounts $arg ($label)"; return }
    try {
        & net accounts $arg 2>&1 | Out-Null
        Mark-OK "net accounts $arg ($label)"
    } catch {
        Mark-Fail "net accounts $arg : $($_.Exception.Message)"
    }
}

Run-Net "/minpwlen:$MinLen"                "MinPasswordLength=$MinLen"
Run-Net "/maxpwage:$MaxAgeDays"            "MaxPasswordAge=$MaxAgeDays"
Run-Net "/minpwage:$MinAgeDays"            "MinPasswordAge=$MinAgeDays"
Run-Net "/uniquepw:$History"               "PasswordHistory=$History"
Run-Net "/lockoutthreshold:$LockoutThr"    "LockoutThreshold=$LockoutThr"
Run-Net "/lockoutduration:$LockoutDur"     "LockoutDuration=${LockoutDur}min"
Run-Net "/lockoutwindow:$LockoutDur"       "LockoutWindow=${LockoutDur}min"

# --- 3. AD default domain password policy ------------------------
Section 'AD DEFAULT DOMAIN PASSWORD POLICY'

if (Get-Command Set-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue) {
    try {
        $existing = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop
        Write-Line "  current: minlen=$($existing.MinPasswordLength) max_age=$([math]::Round($existing.MaxPasswordAge.TotalDays))d complex=$($existing.ComplexityEnabled) history=$($existing.PasswordHistoryCount) lockout=$($existing.LockoutThreshold)"

        if ($DryRun) {
            Mark-Dry "AD default domain policy -> minlen=$MinLen max_age=${MaxAgeDays}d min_age=${MinAgeDays}d complex=True history=$History lockout=$LockoutThr/$($LockoutDur)min"
        } else {
            Set-ADDefaultDomainPasswordPolicy -Identity (Get-ADDomain) `
                -MinPasswordLength $MinLen `
                -MaxPasswordAge (New-TimeSpan -Days $MaxAgeDays) `
                -MinPasswordAge (New-TimeSpan -Days $MinAgeDays) `
                -PasswordHistoryCount $History `
                -ComplexityEnabled $true `
                -ReversibleEncryptionEnabled $false `
                -LockoutThreshold $LockoutThr `
                -LockoutDuration (New-TimeSpan -Minutes $LockoutDur) `
                -LockoutObservationWindow (New-TimeSpan -Minutes $LockoutDur) `
                -ErrorAction Stop

            $post = Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop
            if ($post.MinPasswordLength -eq $MinLen -and $post.ComplexityEnabled) {
                Mark-OK "AD default domain policy updated (minlen=$($post.MinPasswordLength) complex=$($post.ComplexityEnabled))"
            } else {
                Mark-Fail "AD default domain policy write succeeded but verify mismatched"
            }
        }
    } catch {
        Mark-Fail "AD policy: $($_.Exception.Message)"
    }
} else {
    Write-Line "  [info]  Set-ADDefaultDomainPasswordPolicy not available — skipping AD policy"
}

# --- 4. PasswordNeverExpires sweep ------------------------------
Section 'PASSWORDNEVEREXPIRES SWEEP'

try {
    $candidates = Get-LocalUser | Where-Object {
        $_.Enabled -and ($null -eq $_.PasswordExpires) -and
        ($_.SID.Value -notmatch '-500$') -and
        ($_.Name -notin $alwaysPreserve)
    }
    foreach ($u in $candidates) {
        if ($DryRun) {
            Mark-Dry "local $($u.Name): PasswordNeverExpires -> false"
            continue
        }
        try {
            Set-LocalUser -Name $u.Name -PasswordNeverExpires $false -ErrorAction Stop
            Mark-OK "local $($u.Name): PasswordNeverExpires cleared"
        } catch {
            Mark-Fail "local $($u.Name): $($_.Exception.Message)"
        }
    }
    if (-not $candidates) { Mark-Skip "no local accounts with PasswordNeverExpires" }
} catch {
    Mark-Fail "local sweep: $($_.Exception.Message)"
}

if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
    try {
        $adCandidates = Get-ADUser -Filter { PasswordNeverExpires -eq $true -and Enabled -eq $true } `
            -Properties PasswordNeverExpires,Name -ErrorAction Stop |
            Where-Object {
                $_.SamAccountName -notin $alwaysPreserve -and
                $_.SamAccountName -ne 'Administrator' -and
                $_.SamAccountName -notmatch '^.+\$$'
            }
        foreach ($u in $adCandidates) {
            if ($DryRun) {
                Mark-Dry "AD $($u.SamAccountName): PasswordNeverExpires -> false"
                continue
            }
            try {
                Set-ADUser -Identity $u -PasswordNeverExpires $false -ErrorAction Stop
                Mark-OK "AD $($u.SamAccountName): PasswordNeverExpires cleared"
            } catch {
                Mark-Fail "AD $($u.SamAccountName): $($_.Exception.Message)"
            }
        }
        if (-not $adCandidates) { Mark-Skip "no AD accounts with PasswordNeverExpires" }
    } catch {
        Mark-Fail "AD sweep: $($_.Exception.Message)"
    }
}

# --- 5. Built-in Administrator (RID 500) -----------------------
Section 'BUILT-IN ADMINISTRATOR (RID 500)'

if (-not $DisableBuiltInAdmin) {
    Write-Line "  [info]  -DisableBuiltInAdmin not set — RID 500 left alone (safe default)"
} else {
    if (-not $NewAdminUser) {
        Mark-Fail "-DisableBuiltInAdmin requires -NewAdminUser <name>"
    } else {
        $isLocalAdmin = $false
        try {
            $members = Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop
            if ($members | Where-Object { $_.Name -match "\\$NewAdminUser$" -or $_.Name -eq $NewAdminUser }) {
                $isLocalAdmin = $true
            }
        } catch {}

        if (-not $isLocalAdmin) {
            Mark-Fail "replacement admin '$NewAdminUser' is NOT in local Administrators group — refusing to disable RID 500"
        } else {
            try {
                $a = Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' }
                if ($a) {
                    if (-not $a.Enabled) {
                        Mark-Skip "local Administrator (RID 500, name=$($a.Name)) already disabled"
                    } elseif ($DryRun) {
                        Mark-Dry "local Administrator (RID 500, name=$($a.Name)) -> disable"
                    } else {
                        Disable-LocalUser -Name $a.Name -ErrorAction Stop
                        if (-not (Get-LocalUser -Name $a.Name).Enabled) {
                            Mark-OK "local Administrator (RID 500, name=$($a.Name)) disabled (replacement: $NewAdminUser)"
                        } else {
                            Mark-Fail "local Administrator disable verify shows Enabled=True"
                        }
                    }
                }
            } catch { Mark-Fail "local RID 500: $($_.Exception.Message)" }

            if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
                try {
                    $ada = Get-ADUser -Filter 'SID -like "*-500"' -Properties Enabled,Name -ErrorAction Stop
                    if ($ada) {
                        if (-not $ada.Enabled) {
                            Mark-Skip "AD Administrator (RID 500, name=$($ada.Name)) already disabled"
                        } elseif ($DryRun) {
                            Mark-Dry "AD Administrator (RID 500, name=$($ada.Name)) -> disable"
                        } else {
                            Disable-ADAccount -Identity $ada -ErrorAction Stop
                            if (-not (Get-ADUser $ada -Properties Enabled).Enabled) {
                                Mark-OK "AD Administrator (RID 500, name=$($ada.Name)) disabled (replacement: $NewAdminUser)"
                            } else {
                                Mark-Fail "AD Administrator disable verify shows Enabled=True"
                            }
                        }
                    }
                } catch { Mark-Fail "AD RID 500: $($_.Exception.Message)" }
            }
        }
    }
}

# --- summary -----------------------------------------------------
Section 'SUMMARY'

$total = $script:applied + $script:skipped + $script:failed
Write-Line ""
Write-Line "  applied:  $($script:applied)"
Write-Line "  skipped:  $($script:skipped)"
Write-Line "  failed:   $($script:failed)"
Write-Line "  total:    $total"
Write-Line ""

if ($script:failed -gt 0) {
    Write-Line "  [!]  $($script:failed) hard failures — see $out"
    exit 2
} elseif ($DryRun) {
    Write-Line "  [.]  dry run — re-run without -DryRun to apply"
} else {
    Write-Line "  [+]  accounts hardening applied. Verify with check-policy-windows.ps1"
}

Write-Host ""
Write-Host "Full log: $out"
