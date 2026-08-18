[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Executable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Pomodoist executable was not found: $Executable"
}
$executablePath = (Resolve-Path -LiteralPath $Executable).Path
$started = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$receiver = $null

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Pomodoist.Windows.Tests
{
    public sealed class DeepLinkReceiver : IDisposable
    {
        private const uint WmClose = 0x0010;
        private const uint WmDestroy = 0x0002;
        private const uint WmCopyData = 0x004A;
        private const ulong AppLinkMessageId = 0x0402;
        private const string WindowClass = "FLUTTER_RUNNER_WIN32_WINDOW";
        private const string WindowTitle = "Pomodoist";

        private readonly ManualResetEventSlim ready = new ManualResetEventSlim();
        private readonly ManualResetEventSlim received = new ManualResetEventSlim();
        private readonly Thread thread;
        private readonly WindowProc windowProc;
        private IntPtr window;
        private IntPtr module;
        private Exception startupError;
        private string link;

        public DeepLinkReceiver()
        {
            windowProc = HandleMessage;
            thread = new Thread(Run) { IsBackground = true };
        }

        public void Start()
        {
            thread.Start();
            if (!ready.Wait(TimeSpan.FromSeconds(10)))
                throw new TimeoutException("The deep-link receiver did not start.");
            if (startupError != null)
                throw new InvalidOperationException(
                    "The deep-link receiver could not create its window.",
                    startupError);
        }

        public string WaitForLink(int milliseconds)
        {
            return received.Wait(milliseconds) ? link : null;
        }

        public bool IsDiscoverable()
        {
            return window != IntPtr.Zero &&
                FindWindow(WindowClass, WindowTitle) == window;
        }

        public string DiscoveryDetails()
        {
            return string.Format(
                "created={0}; class={1}; title={2}; exact={3}",
                window,
                FindWindow(WindowClass, null),
                FindWindow(null, WindowTitle),
                FindWindow(WindowClass, WindowTitle));
        }

        public void Dispose()
        {
            if (window != IntPtr.Zero)
                PostMessage(window, WmClose, UIntPtr.Zero, IntPtr.Zero);
            if (thread.IsAlive)
                thread.Join(TimeSpan.FromSeconds(10));
            ready.Dispose();
            received.Dispose();
        }

        private void Run()
        {
            try
            {
                module = GetModuleHandle(null);
                var windowClass = new WindowClassEx
                {
                    Size = (uint)Marshal.SizeOf(typeof(WindowClassEx)),
                    WindowProc = Marshal.GetFunctionPointerForDelegate(windowProc),
                    Instance = module,
                    ClassName = WindowClass,
                };
                if (RegisterClassEx(ref windowClass) == 0)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                window = CreateWindowEx(
                    0, WindowClass, WindowTitle, 0,
                    0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, module, IntPtr.Zero);
                if (window == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                if (!SetWindowText(window, WindowTitle))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            catch (Exception error)
            {
                startupError = error;
            }
            finally
            {
                ready.Set();
            }

            if (window == IntPtr.Zero)
                return;

            Message message;
            while (GetMessage(out message, IntPtr.Zero, 0, 0) > 0)
            {
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
            UnregisterClass(WindowClass, module);
        }

        private IntPtr HandleMessage(
            IntPtr handle,
            uint message,
            UIntPtr wParam,
            IntPtr lParam)
        {
            if (message == WmCopyData)
            {
                var data = (CopyData)Marshal.PtrToStructure(
                    lParam,
                    typeof(CopyData));
                if (data.Id.ToUInt64() == AppLinkMessageId)
                {
                    link = ReadUtf8(data.Data);
                    received.Set();
                    return new IntPtr(1);
                }
            }
            else if (message == WmClose)
            {
                DestroyWindow(handle);
                return IntPtr.Zero;
            }
            else if (message == WmDestroy)
            {
                window = IntPtr.Zero;
                PostQuitMessage(0);
                return IntPtr.Zero;
            }
            return DefWindowProc(handle, message, wParam, lParam);
        }

        private static string ReadUtf8(IntPtr pointer)
        {
            var length = 0;
            while (Marshal.ReadByte(pointer, length) != 0)
                length++;
            var bytes = new byte[length];
            Marshal.Copy(pointer, bytes, 0, length);
            return Encoding.UTF8.GetString(bytes);
        }

        private delegate IntPtr WindowProc(
            IntPtr handle,
            uint message,
            UIntPtr wParam,
            IntPtr lParam);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WindowClassEx
        {
            public uint Size;
            public uint Style;
            public IntPtr WindowProc;
            public int ClassExtra;
            public int WindowExtra;
            public IntPtr Instance;
            public IntPtr Icon;
            public IntPtr Cursor;
            public IntPtr Background;
            [MarshalAs(UnmanagedType.LPWStr)] public string MenuName;
            [MarshalAs(UnmanagedType.LPWStr)] public string ClassName;
            public IntPtr SmallIcon;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CopyData
        {
            public UIntPtr Id;
            public uint Size;
            public IntPtr Data;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Point
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Message
        {
            public IntPtr Window;
            public uint Id;
            public UIntPtr WParam;
            public IntPtr LParam;
            public uint Time;
            public Point Position;
            public uint Private;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr GetModuleHandle(string moduleName);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern ushort RegisterClassEx(ref WindowClassEx windowClass);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool UnregisterClass(string className, IntPtr instance);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateWindowEx(
            uint extendedStyle,
            string className,
            string windowName,
            uint style,
            int x,
            int y,
            int width,
            int height,
            IntPtr parent,
            IntPtr menu,
            IntPtr instance,
            IntPtr parameter);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr FindWindow(string className, string windowName);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SetWindowText(IntPtr window, string text);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr DefWindowProc(
            IntPtr window,
            uint message,
            UIntPtr wParam,
            IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool DestroyWindow(IntPtr window);

        [DllImport("user32.dll")]
        private static extern bool PostMessage(
            IntPtr window,
            uint message,
            UIntPtr wParam,
            IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern int GetMessage(
            out Message message,
            IntPtr window,
            uint minimum,
            uint maximum);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage(ref Message message);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage(ref Message message);

        [DllImport("user32.dll")]
        private static extern void PostQuitMessage(int exitCode);
    }
}
'@

function Wait-ForMainWindow {
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process)

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        if ($Process.HasExited) {
            throw "Pomodoist exited before creating its main window ($($Process.ExitCode))."
        }
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return
        }
        Start-Sleep -Milliseconds 250
    } until ([DateTime]::UtcNow -ge $deadline)
    throw 'Pomodoist did not create its main window within 30 seconds.'
}

try {
    $probeUri = 'pomodoist://login-callback?code=delivery-probe'
    $receiver = [Pomodoist.Windows.Tests.DeepLinkReceiver]::new()
    $receiver.Start()
    if (-not $receiver.IsDiscoverable()) {
        throw "The deep-link delivery probe window is not discoverable: $($receiver.DiscoveryDetails())"
    }
    $probe = Start-Process `
        -FilePath $executablePath `
        -ArgumentList @($probeUri) `
        -PassThru
    $started.Add($probe)
    if (-not $probe.WaitForExit(10000)) {
        throw 'The deep-link delivery probe did not exit.'
    }
    if ($probe.ExitCode -ne 0) {
        throw "The deep-link delivery probe exited with code $($probe.ExitCode)."
    }
    $deliveredUri = $receiver.WaitForLink(10000)
    if ($deliveredUri -cne $probeUri) {
        throw "The runner delivered an unexpected deep link: '$deliveredUri'."
    }
    $receiver.Dispose()
    $receiver = $null

    $primary = Start-Process -FilePath $executablePath -PassThru
    $started.Add($primary)
    Wait-ForMainWindow -Process $primary

    $callback = Start-Process `
        -FilePath $executablePath `
        -ArgumentList @('pomodoist://focus') `
        -PassThru
    $started.Add($callback)
    if (-not $callback.WaitForExit(10000)) {
        throw 'The deep-link process did not forward to the primary instance.'
    }
    if ($callback.ExitCode -ne 0) {
        throw "The deep-link process exited with code $($callback.ExitCode)."
    }
    if ($primary.HasExited) {
        throw 'The primary Pomodoist instance exited while receiving a deep link.'
    }

    Write-Output 'Windows deep-link single-instance test passed.'
} finally {
    if ($null -ne $receiver) {
        $receiver.Dispose()
    }
    foreach ($process in $started) {
        if (-not $process.HasExited) {
            $process.Kill()
            [void]$process.WaitForExit(10000)
        }
        $process.Dispose()
    }
}
