[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $env:APPDATA "kvm-at-home\config.json"),
    [switch] $NoHotkey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$monitorPattern = "U5226KW"
$inputA = "0x11"
$inputB = "0x12"

if ($PSVersionTable.ContainsKey("Platform") -and $PSVersionTable.Platform -ne "Win32NT") {
    throw "install-windows.ps1 must be run on Windows."
}

$modulePath = Join-Path $PSScriptRoot "windows\KvmAtHome.psm1"
Import-Module $modulePath -Force

function Read-MonitorIndex {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Monitors,

        [int] $Default = -1
    )

    while ($true) {
        $prompt = if ($Default -ge 0) {
            "Select the Dell U5226KW physical monitor index [$Default]"
        }
        else {
            "Select the Dell U5226KW physical monitor index"
        }

        $raw = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($raw) -and $Default -ge 0) {
            return $Default
        }

        $index = 0
        if ([int]::TryParse($raw, [ref]$index)) {
            $match = $Monitors | Where-Object { $_.Index -eq $index } | Select-Object -First 1
            if ($null -ne $match) {
                return $index
            }
        }

        Write-Host "Enter one of the monitor indexes shown above."
    }
}

function New-KvmHotkeyShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string] $SwitchScriptPath
    )

    $shortcutDirectory = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    New-Item -ItemType Directory -Force -Path $shortcutDirectory | Out-Null

    $shortcutPath = Join-Path $shortcutDirectory "KVM-at-Home.lnk"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = (Get-Command powershell.exe).Source
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$SwitchScriptPath`""
    $shortcut.WorkingDirectory = Split-Path -Parent $SwitchScriptPath
    $shortcut.Hotkey = "CTRL+ALT+P"
    $shortcut.Description = "Toggle Dell U5226KW between HDMI 1 and HDMI 2"
    $shortcut.Save()

    return $shortcutPath
}

Write-Host "=== U5226KW KVM Windows Installer ==="
Write-Host ""
Write-Host "Detected physical monitors:"

$monitors = @(Get-KvmPhysicalMonitor)
if ($monitors.Count -eq 0) {
    throw "Windows did not expose any DDC/CI physical monitors."
}

try {
    foreach ($monitor in $monitors) {
        $width = $monitor.Right - $monitor.Left
        $height = $monitor.Bottom - $monitor.Top
        Write-Host ("  {0}) {1} on {2} - {3}x{4} at {5},{6}" -f `
            $monitor.Index, `
            $monitor.Description, `
            $monitor.DisplayDevice, `
            $width, `
            $height, `
            $monitor.Left, `
            $monitor.Top)
    }

    $candidates = @($monitors | Where-Object { $_.Description -match $monitorPattern })
    if ($candidates.Count -eq 1) {
        $monitorIndex = [int]$candidates[0].Index
    }
    else {
        $defaultIndex = if ($candidates.Count -gt 0) { [int]$candidates[0].Index } else { -1 }
        $monitorIndex = Read-MonitorIndex -Monitors $monitors -Default $defaultIndex
    }

    $selected = $monitors | Where-Object { $_.Index -eq $monitorIndex } | Select-Object -First 1
    if ($null -eq $selected) {
        throw "Selected monitor index $monitorIndex is unavailable."
    }

    $current = Get-KvmMonitorInput -Monitor $selected
    $resolvedA = ConvertTo-KvmUInt32 -Value $inputA
    $resolvedB = ConvertTo-KvmUInt32 -Value $inputB
    if ($current.Current -ne $resolvedA -and $current.Current -ne $resolvedB) {
        throw ("Current input 0x{0:x2} is outside the HDMI 1/2 pair." -f $current.Current)
    }

    $config = [ordered]@{
        MonitorIndex = $monitorIndex
        MonitorDescription = [string]$selected.Description
        InputA = $inputA
        InputB = $inputB
    }

    $configDirectory = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
    $config | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8

    $shortcutPath = $null
    if (!$NoHotkey) {
        $switchScriptPath = (Resolve-Path (Join-Path $PSScriptRoot "kvm-switch.ps1")).Path
        $shortcutPath = New-KvmHotkeyShortcut -SwitchScriptPath $switchScriptPath
    }

    Write-Host ""
    Write-Host "Config written to: $ConfigPath"
    Write-Host ("Monitor: {0}" -f $selected.Description)
    Write-Host ("Current source: 0x{0:x2}" -f $current.Current)
    Write-Host "Configured pair: HDMI 1 (0x11) <-> HDMI 2 (0x12)"
    if ($null -ne $shortcutPath) {
        Write-Host "Shortcut registered: Ctrl+Alt+P -> $shortcutPath"
    }
}
finally {
    Close-KvmPhysicalMonitor -Monitor $monitors
}
