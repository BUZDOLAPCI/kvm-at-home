[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $env:APPDATA "kvm-at-home\config.json"),
    [switch] $NoHotkey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.ContainsKey("Platform") -and $PSVersionTable.Platform -ne "Win32NT") {
    throw "install-windows.ps1 must be run on Windows."
}

$modulePath = Join-Path $PSScriptRoot "windows\KvmAtHome.psm1"
Import-Module $modulePath -Force

function Read-WithDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt,

        [Parameter(Mandatory = $true)]
        [string] $Default
    )

    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value.Trim()
}

function Read-ValidatedChoice {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt,

        [Parameter(Mandatory = $true)]
        [string] $Default,

        [Parameter(Mandatory = $true)]
        [string[]] $Allowed
    )

    while ($true) {
        $value = (Read-WithDefault -Prompt $Prompt -Default $Default).ToLowerInvariant()
        if ($Allowed -contains $value) {
            return $value
        }

        Write-Host "Enter one of: $($Allowed -join ', ')"
    }
}

function Read-MonitorIndex {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt,

        [Parameter(Mandatory = $true)]
        [object[]] $Monitors,

        [int] $Default = -1
    )

    while ($true) {
        $defaultText = if ($Default -ge 0) { [string]$Default } else { "" }
        $raw = if ($defaultText) {
            Read-WithDefault -Prompt $Prompt -Default $defaultText
        }
        else {
            Read-Host $Prompt
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

function Read-VcpInput {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt,

        [Parameter(Mandatory = $true)]
        [string] $Default
    )

    while ($true) {
        $value = Read-WithDefault -Prompt $Prompt -Default $Default
        try {
            [void](ConvertTo-KvmUInt32 $value)
            return $value
        }
        catch {
            Write-Host "Enter a decimal value or a hex value like 0x0f."
        }
    }
}

function Read-PositiveInt {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prompt,

        [Parameter(Mandatory = $true)]
        [string] $Default
    )

    while ($true) {
        $value = Read-WithDefault -Prompt $Prompt -Default $Default
        $parsed = 0
        if ([int]::TryParse($value, [ref]$parsed) -and $parsed -gt 0) {
            return $parsed
        }

        Write-Host "Enter a positive whole number."
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
    $shortcut.Description = "Switch KVM-at-Home monitors to the other computer"
    $shortcut.Save()

    return $shortcutPath
}

Write-Host "=== KVM-at-Home Windows Installer ==="
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

    Write-Host ""
    $computer = Read-ValidatedChoice `
        -Prompt "Which physical computer is this? Computer 2 is the Windows boot you are on now" `
        -Default "2" `
        -Allowed @("1", "2")

    if ($computer -eq "2") {
        $defaultDellInput = "0x0f"
        $defaultLgInput = "0x01"
        $defaultLgMethod = "signal"
    }
    else {
        $defaultDellInput = "0x11"
        $defaultLgInput = "0x0f"
        $defaultLgMethod = "signal"
    }

    Write-Host ""
    $dellDefaultCandidate = $monitors |
        Where-Object { $_.Description -match "C3422WE|Dell" } |
        Select-Object -First 1
    $dellDefaultIndex = if ($null -ne $dellDefaultCandidate) {
        [int]$dellDefaultCandidate.Index
    }
    else {
        -1
    }

    $dellIndex = Read-MonitorIndex `
        -Prompt "Select the Dell C3422WE physical monitor index" `
        -Monitors $monitors `
        -Default $dellDefaultIndex

    $lgDefaultCandidate = $monitors |
        Where-Object { $_.Index -ne $dellIndex } |
        Select-Object -First 1
    $lgDefaultIndex = if ($null -ne $lgDefaultCandidate) {
        [int]$lgDefaultCandidate.Index
    }
    else {
        -1
    }

    $lgIndex = Read-MonitorIndex `
        -Prompt "Select the LG 27GN880 physical monitor index" `
        -Monitors $monitors `
        -Default $lgDefaultIndex

    Write-Host ""
    Write-Host "Input values should point to the OTHER computer."
    $dellInput = Read-VcpInput `
        -Prompt "Dell target input VCP value" `
        -Default $defaultDellInput

    $lgMethod = Read-ValidatedChoice `
        -Prompt "LG switch method (ddc, signal, ddc-then-signal)" `
        -Default $defaultLgMethod `
        -Allowed @("ddc", "signal", "ddc-then-signal")

    $lgInput = $defaultLgInput
    if ($lgMethod -eq "ddc" -or $lgMethod -eq "ddc-then-signal") {
        $lgInput = Read-VcpInput `
            -Prompt "LG target input VCP value" `
            -Default $defaultLgInput
    }

    $lgMonitor = $monitors | Where-Object { $_.Index -eq $lgIndex } | Select-Object -First 1
    $lgDisplayDevice = $lgMonitor.DisplayDevice
    $lgDelay = "10"
    if ($lgMethod -eq "signal" -or $lgMethod -eq "ddc-then-signal") {
        $lgDisplayDevice = Read-WithDefault `
            -Prompt "LG Windows display device for signal kill" `
            -Default $lgMonitor.DisplayDevice

        $lgDelay = Read-PositiveInt `
            -Prompt "LG signal kill delay in seconds" `
            -Default "10"
    }

    $config = [ordered]@{
        SchemaVersion = 1
        DellMonitorIndex = [int]$dellIndex
        DellInput = $dellInput
        LgMonitorIndex = [int]$lgIndex
        LgInput = $lgInput
        LgMethod = $lgMethod
        LgDisplayDevice = $lgDisplayDevice
        LgSignalKillDelaySeconds = [int]$lgDelay
    }

    $configDirectory = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
    $config | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8

    Write-Host ""
    Write-Host "Config written to: $ConfigPath"

    if (!$NoHotkey) {
        $switchScriptPath = Join-Path $PSScriptRoot "kvm-switch.ps1"
        $shortcutPath = New-KvmHotkeyShortcut -SwitchScriptPath $switchScriptPath
        Write-Host "Hotkey registered via shortcut: $shortcutPath"
        Write-Host "Shortcut hotkey: Ctrl+Alt+P"
    }

    Write-Host ""
    Write-Host "Installation complete. Run .\kvm-switch.ps1 once to test before relying on the hotkey."
}
finally {
    Close-KvmPhysicalMonitor -Monitor $monitors
}
