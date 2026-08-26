param(
    [string]$Path = '',
    [switch]$IncludeHeartbeat
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($Path)) {
    $Path = Join-Path $ProjectRoot '@Resources\Generated\state.kv'
}
$targets = New-Object System.Collections.Generic.List[string]
$targets.Add([System.IO.Path]::GetFullPath($Path))
if ($IncludeHeartbeat) {
    $targets.Add([System.IO.Path]::GetFullPath((Join-Path $ProjectRoot '@Resources\Generated\last-update.txt')))
}

if (-not ('TravelAssistant.RestartManager' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace TravelAssistant {
    public static class RestartManager {
        const int ERROR_MORE_DATA = 234;
        const int CCH_RM_SESSION_KEY = 32;
        const int CCH_RM_MAX_APP_NAME = 255;
        const int CCH_RM_MAX_SVC_NAME = 63;

        [StructLayout(LayoutKind.Sequential)]
        struct RM_UNIQUE_PROCESS {
            public int dwProcessId;
            public FILETIME ProcessStartTime;
        }

        enum RM_APP_TYPE {
            RmUnknownApp = 0,
            RmMainWindow = 1,
            RmOtherWindow = 2,
            RmService = 3,
            RmExplorer = 4,
            RmConsole = 5,
            RmCritical = 1000
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct RM_PROCESS_INFO {
            public RM_UNIQUE_PROCESS Process;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_APP_NAME + 1)]
            public string strAppName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCH_RM_MAX_SVC_NAME + 1)]
            public string strServiceShortName;
            public RM_APP_TYPE ApplicationType;
            public uint AppStatus;
            public uint TSSessionId;
            [MarshalAs(UnmanagedType.Bool)]
            public bool bRestartable;
        }

        [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
        static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);

        [DllImport("rstrtmgr.dll")]
        static extern int RmEndSession(uint pSessionHandle);

        [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
        static extern int RmRegisterResources(
            uint pSessionHandle,
            uint nFiles,
            string[] rgsFilenames,
            uint nApplications,
            [In] RM_UNIQUE_PROCESS[] rgApplications,
            uint nServices,
            string[] rgsServiceNames);

        [DllImport("rstrtmgr.dll")]
        static extern int RmGetList(
            uint dwSessionHandle,
            out uint pnProcInfoNeeded,
            ref uint pnProcInfo,
            [In, Out] RM_PROCESS_INFO[] rgAffectedApps,
            ref uint lpdwRebootReasons);

        public sealed class LockInfo {
            public int ProcessId { get; set; }
            public string ProcessName { get; set; }
            public string AppName { get; set; }
            public string ServiceName { get; set; }
            public string ApplicationType { get; set; }
            public bool Restartable { get; set; }
        }

        public static LockInfo[] GetLockingProcesses(string path) {
            if (String.IsNullOrWhiteSpace(path)) throw new ArgumentException("path");
            uint handle;
            string key = Guid.NewGuid().ToString("N").Substring(0, CCH_RM_SESSION_KEY);
            int result = RmStartSession(out handle, 0, key);
            if (result != 0) throw new InvalidOperationException("RmStartSession failed: " + result);

            try {
                string[] files = new string[] { System.IO.Path.GetFullPath(path) };
                result = RmRegisterResources(handle, 1, files, 0, null, 0, null);
                if (result != 0) throw new InvalidOperationException("RmRegisterResources failed: " + result);

                // The owner set can change between the size and data calls. Retry
                // ERROR_MORE_DATA instead of aborting the diagnostic on that race.
                for (int attempt = 0; attempt < 5; attempt++) {
                    uint needed = 0;
                    uint count = 0;
                    uint rebootReasons = 0;
                    result = RmGetList(handle, out needed, ref count, null, ref rebootReasons);
                    if (result == 0 && needed == 0) return new LockInfo[0];
                    if (result != ERROR_MORE_DATA) throw new InvalidOperationException("RmGetList(size) failed: " + result);

                    uint capacity = needed == 0 ? 1u : needed;
                    RM_PROCESS_INFO[] info = new RM_PROCESS_INFO[capacity];
                    count = capacity;
                    result = RmGetList(handle, out needed, ref count, info, ref rebootReasons);
                    if (result == ERROR_MORE_DATA) continue;
                    if (result != 0) throw new InvalidOperationException("RmGetList(data) failed: " + result);

                    List<LockInfo> output = new List<LockInfo>();
                    for (int i = 0; i < count; i++) {
                        int pid = info[i].Process.dwProcessId;
                        string processName = "";
                        try { processName = Process.GetProcessById(pid).ProcessName; } catch { }
                        output.Add(new LockInfo {
                            ProcessId = pid,
                            ProcessName = processName,
                            AppName = info[i].strAppName ?? "",
                            ServiceName = info[i].strServiceShortName ?? "",
                            ApplicationType = info[i].ApplicationType.ToString(),
                            Restartable = info[i].bRestartable
                        });
                    }
                    return output.ToArray();
                }

                throw new InvalidOperationException("RmGetList owner set kept changing after 5 attempts.");
            }
            finally {
                RmEndSession(handle);
            }
        }
    }
}
'@
}

function Get-LockProcessDetail {
    param([object]$Lock)

    $pidValue = [int]$Lock.ProcessId
    $processName = [string]$Lock.ProcessName
    $parentPid = 0
    $parentName = ''
    $commandLine = ''

    try {
        $process = Get-CimInstance Win32_Process -Filter ('ProcessId={0}' -f $pidValue) -ErrorAction Stop
        if ($null -ne $process) {
            $parentPid = [int]$process.ParentProcessId
            $commandLine = [string]$process.CommandLine
            if ([string]::IsNullOrWhiteSpace($processName)) { $processName = [string]$process.Name }
        }
    } catch { }

    if ($parentPid -gt 0) {
        try {
            $parent = Get-CimInstance Win32_Process -Filter ('ProcessId={0}' -f $parentPid) -ErrorAction Stop
            if ($null -ne $parent) { $parentName = [string]$parent.Name }
        } catch { }
    }

    return [pscustomobject]@{
        ProcessId = $pidValue
        ProcessName = $processName
        ParentProcessId = $parentPid
        ParentName = $parentName
        CommandLine = $commandLine
        AppName = [string]$Lock.AppName
        ServiceName = [string]$Lock.ServiceName
        ApplicationType = [string]$Lock.ApplicationType
        Restartable = [bool]$Lock.Restartable
    }
}

foreach ($target in $targets) {
    Write-Host ''
    Write-Host ('=== Lock owners: {0} ===' -f $target) -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host 'File does not currently exist.' -ForegroundColor Yellow
        continue
    }

    $locks = @([TravelAssistant.RestartManager]::GetLockingProcesses($target))
    if ($locks.Count -eq 0) {
        Write-Host 'No persistent Restart Manager lock owner reported at this instant.' -ForegroundColor Green
        Write-Host 'If publication still fails, rerun this command while RunUpdate is retrying.' -ForegroundColor Yellow
        continue
    }

    foreach ($lock in $locks) {
        Get-LockProcessDetail -Lock $lock | Format-List
    }
}

Write-Host ''
Write-Host 'This diagnostic is read-only. It does not terminate processes or modify state files.' -ForegroundColor DarkGray
