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

    public sealed class DisplayConfigSnapshot
    {
        public DISPLAYCONFIG_PATH_INFO[] Paths;
        public DISPLAYCONFIG_MODE_INFO[] Modes;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID
    {
        public UInt32 LowPart;
        public Int32 HighPart;
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

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_RATIONAL
    {
        public UInt32 Numerator;
        public UInt32 Denominator;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_2DREGION
    {
        public UInt32 cx;
        public UInt32 cy;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO
    {
        public UInt64 pixelRate;
        public DISPLAYCONFIG_RATIONAL hSyncFreq;
        public DISPLAYCONFIG_RATIONAL vSyncFreq;
        public DISPLAYCONFIG_2DREGION activeSize;
        public DISPLAYCONFIG_2DREGION totalSize;
        public UInt32 videoStandard;
        public UInt32 scanLineOrdering;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_TARGET_MODE
    {
        public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINTL
    {
        public Int32 x;
        public Int32 y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECTL
    {
        public Int32 left;
        public Int32 top;
        public Int32 right;
        public Int32 bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_SOURCE_MODE
    {
        public UInt32 width;
        public UInt32 height;
        public UInt32 pixelFormat;
        public POINTL position;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_DESKTOP_IMAGE_INFO
    {
        public DISPLAYCONFIG_2DREGION PathSourceSize;
        public RECTL DesktopImageRegion;
        public RECTL DesktopImageClip;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct DISPLAYCONFIG_MODE_INFO_UNION
    {
        [FieldOffset(0)]
        public DISPLAYCONFIG_TARGET_MODE targetMode;

        [FieldOffset(0)]
        public DISPLAYCONFIG_SOURCE_MODE sourceMode;

        [FieldOffset(0)]
        public DISPLAYCONFIG_DESKTOP_IMAGE_INFO desktopImageInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_MODE_INFO
    {
        public UInt32 infoType;
        public UInt32 id;
        public LUID adapterId;
        public DISPLAYCONFIG_MODE_INFO_UNION modeInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_SOURCE_INFO
    {
        public LUID adapterId;
        public UInt32 id;
        public UInt32 modeInfoIdx;
        public UInt32 statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_TARGET_INFO
    {
        public LUID adapterId;
        public UInt32 id;
        public UInt32 modeInfoIdx;
        public UInt32 outputTechnology;
        public UInt32 rotation;
        public UInt32 scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate;
        public UInt32 scanLineOrdering;

        [MarshalAs(UnmanagedType.Bool)]
        public bool targetAvailable;

        public UInt32 statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_INFO
    {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public UInt32 flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_DEVICE_INFO_HEADER
    {
        public UInt32 type;
        public UInt32 size;
        public LUID adapterId;
        public UInt32 id;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAYCONFIG_SOURCE_DEVICE_NAME
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string viewGdiDeviceName;
    }

    public static class Native
    {
        private const int ERROR_SUCCESS = 0;
        private const int ERROR_INSUFFICIENT_BUFFER = 122;
        private const UInt32 QDC_ONLY_ACTIVE_PATHS = 0x00000002;
        private const UInt32 SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x00000020;
        private const UInt32 SDC_APPLY = 0x00000080;
        private const UInt32 SDC_ALLOW_CHANGES = 0x00000400;
        private const UInt32 DISPLAYCONFIG_PATH_ACTIVE = 0x00000001;
        private const UInt32 DISPLAYCONFIG_PATH_MODE_IDX_INVALID = 0xffffffff;
        private const UInt32 DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1;
        private const UInt32 DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE = 1;

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

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(
            UInt32 flags,
            out UInt32 numPathArrayElements,
            out UInt32 numModeInfoArrayElements);

        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(
            UInt32 flags,
            ref UInt32 numPathArrayElements,
            [Out] DISPLAYCONFIG_PATH_INFO[] pathArray,
            ref UInt32 numModeInfoArrayElements,
            [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
            IntPtr currentTopologyId);

        [DllImport("user32.dll")]
        private static extern int SetDisplayConfig(
            UInt32 numPathArrayElements,
            [In] DISPLAYCONFIG_PATH_INFO[] pathArray,
            UInt32 numModeInfoArrayElements,
            [In] DISPLAYCONFIG_MODE_INFO[] modeInfoArray,
            UInt32 flags);

        [DllImport("user32.dll")]
        private static extern int DisplayConfigGetDeviceInfo(
            ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

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

        public static DisplayConfigSnapshot CaptureActiveDisplayConfig()
        {
            while (true)
            {
                UInt32 pathCount;
                UInt32 modeCount;
                int result = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
                if (result != ERROR_SUCCESS)
                {
                    throw new Win32Exception(result, "GetDisplayConfigBufferSizes failed.");
                }

                DISPLAYCONFIG_PATH_INFO[] paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
                DISPLAYCONFIG_MODE_INFO[] modes = new DISPLAYCONFIG_MODE_INFO[modeCount];
                result = QueryDisplayConfig(
                    QDC_ONLY_ACTIVE_PATHS,
                    ref pathCount,
                    paths,
                    ref modeCount,
                    modes,
                    IntPtr.Zero);

                if (result == ERROR_INSUFFICIENT_BUFFER)
                {
                    continue;
                }

                if (result != ERROR_SUCCESS)
                {
                    throw new Win32Exception(result, "QueryDisplayConfig failed.");
                }

                Array.Resize(ref paths, (int)pathCount);
                Array.Resize(ref modes, (int)modeCount);
                return new DisplayConfigSnapshot { Paths = paths, Modes = modes };
            }
        }

        public static string GetPathSourceDeviceName(DISPLAYCONFIG_PATH_INFO path)
        {
            DISPLAYCONFIG_SOURCE_DEVICE_NAME name = new DISPLAYCONFIG_SOURCE_DEVICE_NAME();
            name.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            name.header.size = (UInt32)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DEVICE_NAME));
            name.header.adapterId = path.sourceInfo.adapterId;
            name.header.id = path.sourceInfo.id;

            int result = DisplayConfigGetDeviceInfo(ref name);
            if (result != ERROR_SUCCESS)
            {
                throw new Win32Exception(result, "DisplayConfigGetDeviceInfo source name failed.");
            }

            return name.viewGdiDeviceName;
        }

        public static DisplayConfigSnapshot DisableDisplayPath(string displayDevice)
        {
            DisplayConfigSnapshot snapshot = CaptureActiveDisplayConfig();
            bool matched = false;
            List<int> activePathIndexes = new List<int>();

            for (int i = 0; i < snapshot.Paths.Length; i++)
            {
                string sourceName = GetPathSourceDeviceName(snapshot.Paths[i]);
                if (String.Equals(sourceName, displayDevice, StringComparison.OrdinalIgnoreCase))
                {
                    matched = true;
                    continue;
                }

                activePathIndexes.Add(i);
            }

            if (!matched)
            {
                throw new InvalidOperationException("No active display path matched " + displayDevice + ".");
            }

            if (activePathIndexes.Count == 0)
            {
                throw new InvalidOperationException("Cannot disable the only active display path.");
            }

            DisplayConfigSnapshot disableConfig = BuildSubsetDisplayConfig(snapshot, activePathIndexes);
            ApplyDisplayConfig(disableConfig);
            return snapshot;
        }

        public static void RestoreDisplayConfig(DisplayConfigSnapshot snapshot)
        {
            if (snapshot == null)
            {
                throw new ArgumentNullException("snapshot");
            }

            for (int i = 0; i < snapshot.Paths.Length; i++)
            {
                snapshot.Paths[i].flags |= DISPLAYCONFIG_PATH_ACTIVE;
            }

            ApplyDisplayConfig(snapshot);
        }

        private static void ApplyDisplayConfig(DisplayConfigSnapshot snapshot)
        {
            int result = SetDisplayConfig(
                (UInt32)snapshot.Paths.Length,
                snapshot.Paths,
                (UInt32)snapshot.Modes.Length,
                snapshot.Modes,
                SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_APPLY | SDC_ALLOW_CHANGES);

            if (result != ERROR_SUCCESS)
            {
                throw new Win32Exception(result, "SetDisplayConfig failed with code " + result + ".");
            }
        }

        private static DisplayConfigSnapshot BuildSubsetDisplayConfig(DisplayConfigSnapshot snapshot, List<int> pathIndexes)
        {
            List<DISPLAYCONFIG_PATH_INFO> paths = new List<DISPLAYCONFIG_PATH_INFO>();
            List<DISPLAYCONFIG_MODE_INFO> modes = new List<DISPLAYCONFIG_MODE_INFO>();
            Dictionary<UInt32, UInt32> modeIndexMap = new Dictionary<UInt32, UInt32>();

            foreach (int pathIndex in pathIndexes)
            {
                DISPLAYCONFIG_PATH_INFO path = snapshot.Paths[pathIndex];
                path.flags |= DISPLAYCONFIG_PATH_ACTIVE;

                if (path.sourceInfo.modeInfoIdx != DISPLAYCONFIG_PATH_MODE_IDX_INVALID)
                {
                    path.sourceInfo.modeInfoIdx = AddSubsetMode(snapshot, path.sourceInfo.modeInfoIdx, modes, modeIndexMap);
                }

                if (path.targetInfo.modeInfoIdx != DISPLAYCONFIG_PATH_MODE_IDX_INVALID)
                {
                    path.targetInfo.modeInfoIdx = AddSubsetMode(snapshot, path.targetInfo.modeInfoIdx, modes, modeIndexMap);
                }

                paths.Add(path);
            }

            return new DisplayConfigSnapshot
            {
                Paths = paths.ToArray(),
                Modes = NormalizeSourceModePositions(modes.ToArray())
            };
        }

        private static UInt32 AddSubsetMode(
            DisplayConfigSnapshot snapshot,
            UInt32 oldIndex,
            List<DISPLAYCONFIG_MODE_INFO> modes,
            Dictionary<UInt32, UInt32> modeIndexMap)
        {
            UInt32 newIndex;
            if (modeIndexMap.TryGetValue(oldIndex, out newIndex))
            {
                return newIndex;
            }

            if (oldIndex >= snapshot.Modes.Length)
            {
                throw new InvalidOperationException("Display path references missing mode index " + oldIndex + ".");
            }

            newIndex = (UInt32)modes.Count;
            modes.Add(snapshot.Modes[oldIndex]);
            modeIndexMap[oldIndex] = newIndex;
            return newIndex;
        }

        private static DISPLAYCONFIG_MODE_INFO[] NormalizeSourceModePositions(DISPLAYCONFIG_MODE_INFO[] modes)
        {
            bool foundSource = false;
            Int32 minX = 0;
            Int32 minY = 0;

            for (int i = 0; i < modes.Length; i++)
            {
                if (modes[i].infoType != DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE)
                {
                    continue;
                }

                Int32 x = modes[i].modeInfo.sourceMode.position.x;
                Int32 y = modes[i].modeInfo.sourceMode.position.y;
                if (!foundSource || x < minX)
                {
                    minX = x;
                }

                if (!foundSource || y < minY)
                {
                    minY = y;
                }

                foundSource = true;
            }

            if (!foundSource || (minX == 0 && minY == 0))
            {
                return modes;
            }

            for (int i = 0; i < modes.Length; i++)
            {
                if (modes[i].infoType != DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE)
                {
                    continue;
                }

                DISPLAYCONFIG_MODE_INFO mode = modes[i];
                mode.modeInfo.sourceMode.position.x -= minX;
                mode.modeInfo.sourceMode.position.y -= minY;
                modes[i] = mode;
            }

            return modes;
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

function Invoke-KvmDisplaySignalKill {
    param(
        [Parameter(Mandatory = $true)]
        [string] $DisplayDevice,

        [int] $DelaySeconds = 10
    )

    Initialize-KvmNative
    $savedConfig = $null
    try {
        $savedConfig = [KvmAtHome.Native]::DisableDisplayPath($DisplayDevice)
        Start-Sleep -Seconds $DelaySeconds
    }
    finally {
        if ($null -ne $savedConfig) {
            [KvmAtHome.Native]::RestoreDisplayConfig($savedConfig)
        }
    }
}

Export-ModuleMember -Function `
    ConvertTo-KvmUInt32, `
    Get-KvmPhysicalMonitor, `
    Close-KvmPhysicalMonitor, `
    Set-KvmMonitorInput, `
    Get-KvmMonitorInput, `
    Invoke-KvmDisplaySignalKill
