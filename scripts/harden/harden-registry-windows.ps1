# harden-registry-windows.ps1 — apply registry-based hardenings that
# are safe to use in a CCDC-style round. Inspired by the cyberpatriot
# script ecosystem (EzScript, CPWindowsScripts, etc.) but with the
# competition-breaking moves removed.
#
# WHAT THIS SCRIPT WILL NOT DO (and why):
#   - Touch the Windows Firewall. Importing a generic .wfw on Cabal
#     blocks scored ports (53/88/389/445/636/3389). Tune firewall by
#     hand against your team's scored-service list.
#   - Disable RDP. RDP is scored on Cabal.
#   - Disable SMB. SMB is scored on Cabal.
#   - Mass-reset passwords. The scoring engine has stored creds; mass
#     reset breaks every AD-backed scored service for one round.
#   - Disable Administrator without a renamed admin in place. See
#     harden-accounts-windows.ps1 for the gated path.
#
# WHAT IT WILL DO (registry only, idempotent, verifies after apply):
#   LSA:
#     NoLMHash               = 1   (don't store LM hashes)
#     LimitBlankPasswordUse  = 1   (blank passwords local-only)
#     RestrictAnonymous      = 1   (no anon SAM enumeration)
#     RestrictAnonymousSAM   = 1   (same, named pipes)
#     EveryoneIncludesAnonymous = 0
#   WDigest:
#     UseLogonCredential     = 0   (kills Mimikatz plaintext path)
#   SMB server:
#     RequireSecuritySignature = 1 (SMB signing required)
#     EnableSecuritySignature  = 1
#     SMB1                    = 0  (disable SMBv1 — SMBv2/v3 still on)
#   DNS client:
#     EnableMulticast         = 0  (disable LLMNR)
#   Auto-run:
#     NoDriveTypeAutoRun      = 0xFF
#     NoAutorun               = 1
#   UAC:
#     EnableLUA               = 1
#     ConsentPromptBehaviorAdmin = 2
#   PowerShell logging (forensic visibility, free):
#     EnableScriptBlockLogging = 1
#     EnableModuleLogging      = 1
#
# Each value is checked BEFORE write; if already at the target it's
# skipped. Every change is logged with the old + new value.
#
# Usage (elevated PowerShell on Cabal):
#   .\harden-registry-windows.ps1 -DryRun     # show what would change
#   .\harden-registry-windows.ps1             # apply
#
# Re-running is safe (idempotent). The log file records every run, so
# you can show the inject judge "here's the before/after on each key."

[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# --- workdir + log -------------------------------------------------
$WorkDir = Join-Path $env:USERPROFILE '.ecitadel'
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}
try { (Get-Item $WorkDir).Attributes = 'Hidden' } catch {}

$ts  = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssZ')
$out = Join-Path $WorkDir "harden-registry-$env:COMPUTERNAME-$ts.log"

$script:applied = 0; $script:skipped = 0; $script:failed = 0

function Write-Line([string]$line) {
    Write-Host $line
    Add-Content -Path $out -Value $line
}

# --- header ---------------------------------------------------------
Set-Content -Path $out -Value "eCitadel registry hardening"
Write-Host "eCitadel registry hardening"
Write-Line "host:    $env:COMPUTERNAME"
Write-Line "utc:     $((Get-Date).ToUniversalTime().ToString('s'))Z"
Write-Line "user:    $env:USERNAME"
Write-Line "dryrun:  $($DryRun.IsPresent)"
Write-Line ""

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Line "  [FAIL]  not running as Administrator — re-launch elevated"
    exit 1
}

$settings = @(
    # --- LSA ---
    @{ Path='HKLM:\System\CurrentControlSet\Control\Lsa';                  Name='NoLMHash';                  Type='DWord'; Target=1;   Label='LSA: NoLMHash' },
    @{ Path='HKLM:\System\CurrentControlSet\Control\Lsa';                  Name='LimitBlankPasswordUse';     Type='DWord'; Target=1;   Label='LSA: LimitBlankPasswordUse' },
    @{ Path='HKLM:\System\CurrentControlSet\Control\Lsa';                  Name='RestrictAnonymous';         Type='DWord'; Target=1;   Label='LSA: RestrictAnonymous' },
    @{ Path='HKLM:\System\CurrentControlSet\Control\Lsa';                  Name='RestrictAnonymousSAM';      Type='DWord'; Target=1;   Label='LSA: RestrictAnonymousSAM' },
    @{ Path='HKLM:\System\CurrentControlSet\Control\Lsa';                  Name='EveryoneIncludesAnonymous'; Type='DWord'; Target=0;   Label='LSA: EveryoneIncludesAnonymous' },

    # --- WDigest (anti credential-theft) ---
    @{ Path='HKLM:\System\CurrentControlSet\Control\SecurityProviders\WDigest'; Name='UseLogonCredential';   Type='DWord'; Target=0;   Label='WDigest: UseLogonCredential' },

    # --- SMB server hardening (signing required, SMBv1 off) ---
    @{ Path='HKLM:\System\CurrentControlSet\Services\LanmanServer\Parameters';  Name='RequireSecuritySignature'; Type='DWord'; Target=1; Label='SMB server: RequireSecuritySignature' },
    @{ Path='HKLM:\System\CurrentControlSet\Services\LanmanServer\Parameters';  Name='EnableSecuritySignature';  Type='DWord'; Target=1; Label='SMB server: EnableSecuritySignature' },
    @{ Path='HKLM:\System\CurrentControlSet\Services\LanmanServer\Parameters';  Name='SMB1';                     Type='DWord'; Target=0; Label='SMB server: SMB1 (disable)' },

    # --- SMB client signing ---
    @{ Path='HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters'; Name='RequireSecuritySignature'; Type='DWord'; Target=1; Label='SMB client: RequireSecuritySignature' },
    @{ Path='HKLM:\System\CurrentControlSet\Services\LanmanWorkstation\Parameters'; Name='EnableSecuritySignature';  Type='DWord'; Target=1; Label='SMB client: EnableSecuritySignature' },

    # --- DNS client: kill LLMNR (AD DNS via DC still works) ---
    @{ Path='HKLM:\Software\Policies\Microsoft\Windows NT\DNSClient';      Name='EnableMulticast';           Type='DWord'; Target=0;   Label='DNSClient: EnableMulticast (LLMNR off)' },

    # --- Autorun ---
    @{ Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='NoDriveTypeAutoRun';   Type='DWord'; Target=255; Label='Explorer: NoDriveTypeAutoRun=0xFF' },
    @{ Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Name='NoAutorun';            Type='DWord'; Target=1;   Label='Explorer: NoAutorun=1' },

    # --- UAC ---
    @{ Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'; Name='EnableLUA';              Type='DWord'; Target=1;   Label='UAC: EnableLUA=1' },
    @{ Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'; Name='ConsentPromptBehaviorAdmin'; Type='DWord'; Target=2; Label='UAC: ConsentPromptBehaviorAdmin=2' },

    # --- PowerShell logging (forensic visibility — free win) ---
    @{ Path='HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; Name='EnableScriptBlockLogging'; Type='DWord'; Target=1; Label='PS: ScriptBlockLogging' },
    @{ Path='HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging';      Name='EnableModuleLogging';      Type='DWord'; Target=1; Label='PS: ModuleLogging' }
)

function Set-RegSetting {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)]          $Target,
        [Parameter(Mandatory)] [string]$Label,
        [switch]$DryRun
    )

    $cur = $null
    if (Test-Path $Path) {
        $cur = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    }

    if ($cur -eq $Target) {
        Write-Line "  [skip]  $Label already = $Target"
        $script:skipped++
        return
    }

    $currentRepr = if ($null -eq $cur) { '<missing>' } else { "$cur" }

    if ($DryRun) {
        Write-Line "  [DRY ]  $Label : $currentRepr -> $Target"
        return
    }

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Target -PropertyType $Type -Force | Out-Null

        $post = (Get-ItemProperty -Path $Path -Name $Name).$Name
        if ($post -eq $Target) {
            Write-Line "  [ ok ]  $Label : $currentRepr -> $Target  (verified)"
            $script:applied++
        } else {
            Write-Line "  [FAIL]  $Label : write succeeded but verify reads $post (expected $Target)"
            $script:failed++
        }
    } catch {
        Write-Line "  [FAIL]  $Label : $($_.Exception.Message)"
        $script:failed++
    }
}

foreach ($s in $settings) {
    Set-RegSetting -Path $s.Path -Name $s.Name -Type $s.Type -Target $s.Target -Label $s.Label -DryRun:$DryRun
}

Write-Line ""
Write-Line "=== SUMMARY ==="
Write-Line "  applied:  $($script:applied)"
Write-Line "  skipped:  $($script:skipped)  (already at target)"
Write-Line "  failed:   $($script:failed)"
Write-Line ""

if ($script:failed -gt 0) {
    Write-Line "  [!]  $($script:failed) hard failures — investigate before round resumes"
    exit 2
} elseif ($DryRun) {
    Write-Line "  [.]  dry run — re-run without -DryRun to apply"
} else {
    Write-Line "  [+]  registry hardening applied"
    Write-Line ""
    Write-Line "  Note: some changes (LLMNR, WDigest, SMB signing, autorun)"
    Write-Line "        need a logoff or reboot to fully take effect. Verify"
    Write-Line "        with check-policy-windows.ps1 after."
}

Write-Host ""
Write-Host "Full log: $out"
