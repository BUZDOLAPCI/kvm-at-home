[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $env:APPDATA "kvm-at-home\config.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "windows\KvmAtHome.psm1"
Import-Module $modulePath -Force

if (!(Test-Path -LiteralPath $ConfigPath)) {
    Write-Error "Config file not found: $ConfigPath. Run .\install-windows.ps1 first."
    exit 1
}

$config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
$monitors = @(Get-KvmPhysicalMonitor)
$failures = @()

try {
    $dell = $monitors | Where-Object { $_.Index -eq [int]$config.DellMonitorIndex } | Select-Object -First 1
    if ($null -eq $dell) {
        throw "Dell monitor index $($config.DellMonitorIndex) was not found. Run .\install-windows.ps1 again."
    }

    try {
        Set-KvmMonitorInput -Monitor $dell -Input $config.DellInput
    }
    catch {
        $failures += "Dell DDC switch failed: $($_.Exception.Message)"
    }

    $lgMethod = ([string]$config.LgMethod).ToLowerInvariant()
    if ($lgMethod -eq "ddc" -or $lgMethod -eq "ddc-then-signal") {
        $lg = $monitors | Where-Object { $_.Index -eq [int]$config.LgMonitorIndex } | Select-Object -First 1
        if ($null -eq $lg) {
            throw "LG monitor index $($config.LgMonitorIndex) was not found. Run .\install-windows.ps1 again."
        }

        try {
            Set-KvmMonitorInput -Monitor $lg -Input $config.LgInput
        }
        catch {
            if ($lgMethod -eq "ddc") {
                $failures += "LG DDC switch failed: $($_.Exception.Message)"
            }
        }
    }

    if ($lgMethod -eq "signal" -or $lgMethod -eq "ddc-then-signal") {
        try {
            Invoke-KvmDisplaySignalKill `
                -DisplayDevice ([string]$config.LgDisplayDevice) `
                -DelaySeconds ([int]$config.LgSignalKillDelaySeconds)
        }
        catch {
            $failures += "LG signal switch failed: $($_.Exception.Message)"
        }
    }
    elseif ($lgMethod -ne "ddc") {
        throw "Unsupported LG method '$($config.LgMethod)'. Expected ddc, signal, or ddc-then-signal."
    }

    if ($failures.Count -gt 0) {
        throw ($failures -join [Environment]::NewLine)
    }
}
finally {
    Close-KvmPhysicalMonitor -Monitor $monitors
}
