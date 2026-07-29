Set-StrictMode -Version Latest

$script:NativeLoaded = $false

function Initialize-KvmNative {
    if ($script:NativeLoaded -or ("KvmAtHome.Native" -as [type])) {
        $script:NativeLoaded = $true
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace KvmAtHome
{
    public sealed class PhysicalMonitor
    {
        public int Index;
        public IntPtr Handle;
        public string Description;
        public string DisplayDevice;
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;

        public override string ToString()
        {
            return String.Format("#{0}: {1} on {2} ({3},{4})-({5},{6})",
                Index, Description, DisplayDevice, Left, Top, Right, Bottom);
        }
    }

    public sealed class VcpValue
    {
        public UInt32 Current;
        public UInt32 Maximum;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public UInt32 dwFlags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    public static class Native
    {
        private delegate bool MonitorEnumProc(
            IntPtr hMonitor,
            IntPtr hdcMonitor,
            ref RECT lprcMonitor,
            IntPtr dwData);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EnumDisplayMonitors(
            IntPtr hdc,
            IntPtr lprcClip,
            MonitorEnumProc lpfnEnum,
            IntPtr dwData);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool GetMonitorInfo(
            IntPtr hMonitor,
            ref MONITORINFOEX lpmi);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(
            IntPtr hMonitor,
            out UInt32 pdwNumberOfPhysicalMonitors);

        [DllImport("dxva2.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool GetPhysicalMonitorsFromHMONITOR(
            IntPtr hMonitor,
            UInt32 dwPhysicalMonitorArraySize,
            [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool DestroyPhysicalMonitors(
            UInt32 dwPhysicalMonitorArraySize,
            PHYSICAL_MONITOR[] pPhysicalMonitorArray);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool SetVCPFeature(
            IntPtr hMonitor,
            byte bVCPCode,
            UInt32 dwNewValue);

        [DllImport("dxva2.dll", SetLastError = true)]
        private static extern bool GetVCPFeatureAndVCPFeatureReply(
            IntPtr hMonitor,
            byte bVCPCode,
            out UInt32 pvct,
            out UInt32 pdwCurrentValue,
            out UInt32 pdwMaximumValue);

        public static PhysicalMonitor[] GetPhysicalMonitors()
        {
            List<PhysicalMonitor> monitors = new List<PhysicalMonitor>();
            MonitorEnumProc callback = delegate(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT rect, IntPtr data)
            {
                MONITORINFOEX info = new MONITORINFOEX();
                info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
                if (!GetMonitorInfo(hMonitor, ref info))
                {
                    return true;
                }

                UInt32 count;
                if (!GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out count) || count == 0)
                {
                    return true;
                }

                PHYSICAL_MONITOR[] physical = new PHYSICAL_MONITOR[count];
                if (!GetPhysicalMonitorsFromHMONITOR(hMonitor, count, physical))
                {
                    return true;
                }

                for (int i = 0; i < physical.Length; i++)
                {
                    monitors.Add(new PhysicalMonitor
                    {
                        Index = monitors.Count,
                        Handle = physical[i].hPhysicalMonitor,
                        Description = physical[i].szPhysicalMonitorDescription,
                        DisplayDevice = info.szDevice,
                        Left = info.rcMonitor.Left,
                        Top = info.rcMonitor.Top,
                        Right = info.rcMonitor.Right,
                        Bottom = info.rcMonitor.Bottom
                    });
                }

                return true;
            };

            if (!EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "EnumDisplayMonitors failed.");
            }

            return monitors.ToArray();
        }

        public static void DestroyPhysicalMonitorHandles(PhysicalMonitor[] monitors)
        {
            if (monitors == null || monitors.Length == 0)
            {
                return;
            }

            PHYSICAL_MONITOR[] physical = new PHYSICAL_MONITOR[monitors.Length];
            for (int i = 0; i < monitors.Length; i++)
            {
                physical[i].hPhysicalMonitor = monitors[i].Handle;
                physical[i].szPhysicalMonitorDescription = monitors[i].Description;
            }

            DestroyPhysicalMonitors((UInt32)physical.Length, physical);
        }

        public static void SetMonitorInput(PhysicalMonitor monitor, UInt32 input)
        {
            if (monitor == null)
            {
                throw new ArgumentNullException("monitor");
            }

            if (!SetVCPFeature(monitor.Handle, 0x60, input))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SetVCPFeature 0x60 failed.");
            }
        }

        public static VcpValue ReadMonitorInput(PhysicalMonitor monitor)
        {
            if (monitor == null)
            {
                throw new ArgumentNullException("monitor");
            }

            UInt32 codeType;
            UInt32 current;
            UInt32 maximum;
            if (!GetVCPFeatureAndVCPFeatureReply(monitor.Handle, 0x60, out codeType, out current, out maximum))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetVCPFeature 0x60 failed.");
            }

            return new VcpValue { Current = current, Maximum = maximum };
        }
    }
}
"@

    $script:NativeLoaded = $true
}

function ConvertTo-KvmUInt32 {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Value
    )

    if ($Value -is [byte] -or $Value -is [int] -or $Value -is [uint32] -or $Value -is [long]) {
        return [uint32]$Value
    }

    $text = ([string]$Value).Trim()
    if ($text.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToUInt32($text.Substring(2), 16)
    }

    return [Convert]::ToUInt32($text, 10)
}

function Get-KvmPhysicalMonitor {
    Initialize-KvmNative
    [KvmAtHome.Native]::GetPhysicalMonitors()
}

function Close-KvmPhysicalMonitor {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Monitor
    )

    Initialize-KvmNative
    $typed = [KvmAtHome.PhysicalMonitor[]]@($Monitor)
    [KvmAtHome.Native]::DestroyPhysicalMonitorHandles($typed)
}

function Set-KvmMonitorInput {
    param(
        [Parameter(Mandatory = $true)]
        [KvmAtHome.PhysicalMonitor] $Monitor,

        [Parameter(Mandatory = $true)]
        [Alias("Input")]
        [object] $InputValue
    )

    Initialize-KvmNative
    $resolvedInput = ConvertTo-KvmUInt32 -Value $InputValue
    [KvmAtHome.Native]::SetMonitorInput($Monitor, $resolvedInput)
}

function Get-KvmMonitorInput {
    param(
        [Parameter(Mandatory = $true)]
        [KvmAtHome.PhysicalMonitor] $Monitor
    )

    Initialize-KvmNative
    [KvmAtHome.Native]::ReadMonitorInput($Monitor)
}

Export-ModuleMember -Function `
    ConvertTo-KvmUInt32, `
    Get-KvmPhysicalMonitor, `
    Close-KvmPhysicalMonitor, `
    Set-KvmMonitorInput, `
    Get-KvmMonitorInput
