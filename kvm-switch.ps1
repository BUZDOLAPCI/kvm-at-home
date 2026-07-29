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

$mutex = [System.Threading.Mutex]::new($false, "Local\KvmAtHome-U5226KW")
$lockTaken = $false

try {
    $lockTaken = $mutex.WaitOne(0)
    if (!$lockTaken) {
        exit 0
    }

    $config = Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
    $monitors = @(Get-KvmPhysicalMonitor)

    try {
        $descriptionMatches = @(
            $monitors | Where-Object { $_.Description -eq [string]$config.MonitorDescription }
        )
        $monitor = if ($descriptionMatches.Count -eq 1) {
            $descriptionMatches[0]
        }
        else {
            $monitors |
                Where-Object { $_.Index -eq [int]$config.MonitorIndex } |
                Select-Object -First 1
        }

        if ($null -eq $monitor) {
            throw "Configured U5226KW monitor was not found. Run .\install-windows.ps1 again."
        }

        $inputA = ConvertTo-KvmUInt32 -Value $config.InputA
        $inputB = ConvertTo-KvmUInt32 -Value $config.InputB
        if ($inputA -eq $inputB) {
            throw "InputA and InputB must be different."
        }

        $current = Get-KvmMonitorInput -Monitor $monitor
        if ($current.Current -eq $inputA) {
            $target = $inputB
        }
        elseif ($current.Current -eq $inputB) {
            $target = $inputA
        }
        else {
            throw ("Current source 0x{0:x2} is outside the configured input pair." -f $current.Current)
        }

        Write-Host ("Switching {0} from 0x{1:x2} to 0x{2:x2}" -f `
            $monitor.Description, $current.Current, $target)
        Set-KvmMonitorInput -Monitor $monitor -InputValue $target
    }
    finally {
        if ($null -ne $monitors) {
            Close-KvmPhysicalMonitor -Monitor $monitors
        }
    }
}
finally {
    if ($lockTaken) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
