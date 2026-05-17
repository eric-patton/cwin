using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;

namespace Cwin {

    public struct WindowDescriptor {
        public IntPtr Hwnd;
        public int Pid;
        public string Title;
        public string ClassName;
        public int X, Y, Width, Height;
        public bool IsMinimized;
        public bool IsCloaked;
        public bool IsVisible;
    }

    public static class Native {
        public const uint WM_MOUSEMOVE      = 0x0200;
        public const uint WM_LBUTTONDOWN    = 0x0201;
        public const uint WM_LBUTTONUP      = 0x0202;
        public const uint WM_LBUTTONDBLCLK  = 0x0203;
        public const uint WM_RBUTTONDOWN    = 0x0204;
        public const uint WM_RBUTTONUP      = 0x0205;
        public const uint WM_RBUTTONDBLCLK  = 0x0206;
        public const uint WM_MBUTTONDOWN    = 0x0207;
        public const uint WM_MBUTTONUP      = 0x0208;
        public const uint WM_MBUTTONDBLCLK  = 0x0209;
        public const uint WM_KEYDOWN        = 0x0100;
        public const uint WM_KEYUP          = 0x0101;
        public const uint WM_SYSKEYDOWN     = 0x0104;
        public const uint WM_SYSKEYUP       = 0x0105;
        public const uint WM_CHAR           = 0x0102;

        public const uint MK_LBUTTON = 0x0001;
        public const uint MK_RBUTTON = 0x0002;
        public const uint MK_SHIFT   = 0x0004;
        public const uint MK_CONTROL = 0x0008;
        public const uint MK_MBUTTON = 0x0010;

        public const uint PW_CLIENTONLY        = 0x00000001;
        public const uint PW_RENDERFULLCONTENT = 0x00000002;

        public const int GWL_EXSTYLE      = -20;
        public const int WS_EX_TOOLWINDOW = 0x00000080;

        public const int SW_HIDE             = 0;
        public const int SW_SHOWNORMAL       = 1;
        public const int SW_SHOWMINIMIZED    = 2;
        public const int SW_SHOWMAXIMIZED    = 3;
        public const int SW_SHOWNOACTIVATE   = 4;
        public const int SW_SHOW             = 5;
        public const int SW_MINIMIZE         = 6;
        public const int SW_SHOWMINNOACTIVE  = 7;
        public const int SW_SHOWNA           = 8;
        public const int SW_RESTORE          = 9;

        public const uint SWP_NOSIZE     = 0x0001;
        public const uint SWP_NOMOVE     = 0x0002;
        public const uint SWP_NOZORDER   = 0x0004;
        public const uint SWP_NOACTIVATE = 0x0010;

        public static readonly IntPtr HWND_TOP       = new IntPtr(0);
        public static readonly IntPtr HWND_BOTTOM    = new IntPtr(1);
        public static readonly IntPtr HWND_TOPMOST   = new IntPtr(-1);
        public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

        public const uint MONITOR_DEFAULTTONULL    = 0x00000000;
        public const uint MONITOR_DEFAULTTOPRIMARY = 0x00000001;
        public const uint MONITOR_DEFAULTTONEAREST = 0x00000002;
        public const uint MONITORINFOF_PRIMARY     = 0x00000001;

        public const int SRCCOPY = 0x00CC0020;

        public const int DWMWA_CLOAKED = 14;

        public const int SM_XVIRTUALSCREEN  = 76;
        public const int SM_YVIRTUALSCREEN  = 77;
        public const int SM_CXVIRTUALSCREEN = 78;
        public const int SM_CYVIRTUALSCREEN = 79;

        public const uint INPUT_MOUSE    = 0;
        public const uint INPUT_KEYBOARD = 1;

        public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        public const uint KEYEVENTF_KEYUP       = 0x0002;
        public const uint KEYEVENTF_UNICODE     = 0x0004;
        public const uint KEYEVENTF_SCANCODE    = 0x0008;

        public const uint MOUSEEVENTF_MOVE       = 0x0001;
        public const uint MOUSEEVENTF_LEFTDOWN   = 0x0002;
        public const uint MOUSEEVENTF_LEFTUP     = 0x0004;
        public const uint MOUSEEVENTF_RIGHTDOWN  = 0x0008;
        public const uint MOUSEEVENTF_RIGHTUP    = 0x0010;
        public const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
        public const uint MOUSEEVENTF_MIDDLEUP   = 0x0040;
        public const uint MOUSEEVENTF_ABSOLUTE   = 0x8000;
        public const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;

        public const uint MAPVK_VK_TO_VSC = 0;

        public const uint TOKEN_QUERY = 0x0008;
        public const int  TokenIntegrityLevel = 25;
        public const uint SECURITY_MANDATORY_LOW_RID    = 0x00001000;
        public const uint SECURITY_MANDATORY_MEDIUM_RID = 0x00002000;
        public const uint SECURITY_MANDATORY_HIGH_RID   = 0x00003000;
        public const uint SECURITY_MANDATORY_SYSTEM_RID = 0x00004000;
        public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

        public static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left, Top, Right, Bottom;
            public int Width  { get { return Right - Left; } }
            public int Height { get { return Bottom - Top; } }
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X, Y; }

        // 40 bytes (4 ints rcMonitor + 4 ints rcWork + uint flags + 32 wchars name).
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct MONITORINFOEX {
            public uint cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string szDevice;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT {
            public ushort wVk;
            public ushort wScan;
            public uint   dwFlags;
            public uint   time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct HARDWAREINPUT {
            public uint uMsg;
            public ushort wParamL;
            public ushort wParamH;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct INPUT_UNION {
            [FieldOffset(0)] public MOUSEINPUT mi;
            [FieldOffset(0)] public KEYBDINPUT ki;
            [FieldOffset(0)] public HARDWAREINPUT hi;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT {
            public uint type;
            public INPUT_UNION u;
        }

        public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
        public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool GetMonitorInfoW(IntPtr hMonitor, ref MONITORINFOEX lpmi);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hwnd);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hwnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hwnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetWindowTextW(IntPtr hwnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetClassNameW(IntPtr hwnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out int processId);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool GetWindowRect(IntPtr hwnd, out RECT lpRect);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool GetClientRect(IntPtr hwnd, out RECT lpRect);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ClientToScreen(IntPtr hwnd, ref POINT lpPoint);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ScreenToClient(IntPtr hwnd, ref POINT lpPoint);

        [DllImport("user32.dll")]
        public static extern IntPtr WindowFromPoint(POINT Point);

        [DllImport("user32.dll")]
        public static extern IntPtr GetParent(IntPtr hwnd);

        [DllImport("user32.dll")]
        public static extern bool IsChild(IntPtr hWndParent, IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);

        [DllImport("gdi32.dll", SetLastError = true)]
        public static extern bool BitBlt(IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest, IntPtr hdcSrc, int xSrc, int ySrc, int rop);

        [DllImport("user32.dll")]
        public static extern IntPtr GetDC(IntPtr hwnd);

        [DllImport("user32.dll")]
        public static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool PostMessageW(IntPtr hwnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowPos(IntPtr hwnd, IntPtr hwndAfter, int X, int Y, int cx, int cy, uint flags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool ShowWindow(IntPtr hwnd, int nCmdShow);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetForegroundWindow(IntPtr hwnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

        [DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
        public static extern int GetWindowLong(IntPtr hwnd, int nIndex);

        [DllImport("user32.dll")]
        public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

        [DllImport("user32.dll")]
        public static extern uint WaitForInputIdle(IntPtr hProcess, uint dwMilliseconds);

        [DllImport("dwmapi.dll", SetLastError = true)]
        public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

        [DllImport("user32.dll")]
        public static extern uint MapVirtualKey(uint uCode, uint uMapType);

        [DllImport("user32.dll")]
        public static extern int GetSystemMetrics(int nIndex);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool GetTokenInformation(IntPtr TokenHandle, int TokenInformationClass, IntPtr TokenInformation, uint TokenInformationLength, out uint ReturnLength);

        [DllImport("advapi32.dll")]
        public static extern IntPtr GetSidSubAuthority(IntPtr pSid, uint nSubAuthority);

        [DllImport("advapi32.dll")]
        public static extern IntPtr GetSidSubAuthorityCount(IntPtr pSid);

        static Native() {
            try { SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2); } catch { }
        }
    }

    public static class Window {
        public static WindowDescriptor[] EnumerateTopLevel(bool includeHidden) {
            var list = new List<WindowDescriptor>();
            Native.EnumWindowsProc cb = (hwnd, lparam) => {
                bool visible = Native.IsWindowVisible(hwnd);
                if (!includeHidden && !visible) return true;

                int cloaked = 0;
                Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_CLOAKED, out cloaked, sizeof(int));
                bool isCloaked = cloaked != 0;
                if (!includeHidden && isCloaked) return true;

                int ex = Native.GetWindowLong(hwnd, Native.GWL_EXSTYLE);
                if (!includeHidden && (ex & Native.WS_EX_TOOLWINDOW) != 0) return true;

                var sbT = new StringBuilder(512);
                Native.GetWindowTextW(hwnd, sbT, sbT.Capacity);
                if (!includeHidden && sbT.Length == 0) return true;

                var sbC = new StringBuilder(256);
                Native.GetClassNameW(hwnd, sbC, sbC.Capacity);

                int pid = 0;
                Native.GetWindowThreadProcessId(hwnd, out pid);

                Native.RECT r;
                Native.GetWindowRect(hwnd, out r);

                list.Add(new WindowDescriptor {
                    Hwnd = hwnd,
                    Pid = pid,
                    Title = sbT.ToString(),
                    ClassName = sbC.ToString(),
                    X = r.Left, Y = r.Top, Width = r.Width, Height = r.Height,
                    IsMinimized = Native.IsIconic(hwnd),
                    IsCloaked = isCloaked,
                    IsVisible = visible
                });
                return true;
            };
            Native.EnumWindows(cb, IntPtr.Zero);
            return list.ToArray();
        }

        public static WindowDescriptor GetInfo(IntPtr hwnd) {
            var sbT = new StringBuilder(512);
            Native.GetWindowTextW(hwnd, sbT, sbT.Capacity);
            var sbC = new StringBuilder(256);
            Native.GetClassNameW(hwnd, sbC, sbC.Capacity);
            int pid = 0;
            Native.GetWindowThreadProcessId(hwnd, out pid);
            Native.RECT r;
            Native.GetWindowRect(hwnd, out r);
            int cloaked = 0;
            Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_CLOAKED, out cloaked, sizeof(int));
            return new WindowDescriptor {
                Hwnd = hwnd,
                Pid = pid,
                Title = sbT.ToString(),
                ClassName = sbC.ToString(),
                X = r.Left, Y = r.Top, Width = r.Width, Height = r.Height,
                IsMinimized = Native.IsIconic(hwnd),
                IsCloaked = cloaked != 0,
                IsVisible = Native.IsWindowVisible(hwnd)
            };
        }
    }

    public class MonitorDescriptor {
        public int Index;            // 1-indexed; primary always = 1.
        public IntPtr Handle;
        public string DeviceName;
        public int X, Y, Width, Height;            // full monitor rect
        public int WorkX, WorkY, WorkWidth, WorkHeight;  // excludes taskbar/docked bars
        public bool IsPrimary;
    }

    public static class Monitors {
        public static MonitorDescriptor[] Enumerate() {
            var raw = new List<MonitorDescriptor>();
            Native.MonitorEnumProc cb = (IntPtr hMon, IntPtr hdc, ref Native.RECT r, IntPtr data) => {
                var mi = new Native.MONITORINFOEX();
                mi.cbSize = (uint)Marshal.SizeOf<Native.MONITORINFOEX>();
                if (!Native.GetMonitorInfoW(hMon, ref mi)) return true;
                raw.Add(new MonitorDescriptor {
                    Handle = hMon,
                    DeviceName = mi.szDevice ?? "",
                    X = mi.rcMonitor.Left, Y = mi.rcMonitor.Top,
                    Width = mi.rcMonitor.Width, Height = mi.rcMonitor.Height,
                    WorkX = mi.rcWork.Left, WorkY = mi.rcWork.Top,
                    WorkWidth = mi.rcWork.Width, WorkHeight = mi.rcWork.Height,
                    IsPrimary = (mi.dwFlags & Native.MONITORINFOF_PRIMARY) != 0,
                });
                return true;
            };
            Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, cb, IntPtr.Zero);

            // Stable ordering: primary first, then by X then Y. This way --monitor 1
            // is always the primary regardless of OS enumeration order.
            raw.Sort((a, b) => {
                if (a.IsPrimary != b.IsPrimary) return a.IsPrimary ? -1 : 1;
                int dx = a.X.CompareTo(b.X);
                if (dx != 0) return dx;
                return a.Y.CompareTo(b.Y);
            });
            for (int i = 0; i < raw.Count; i++) raw[i].Index = i + 1;
            return raw.ToArray();
        }

        public static MonitorDescriptor Containing(IntPtr hwnd) {
            IntPtr h = Native.MonitorFromWindow(hwnd, Native.MONITOR_DEFAULTTONEAREST);
            if (h == IntPtr.Zero) return null;
            var all = Enumerate();
            foreach (var m in all) if (m.Handle == h) return m;
            return all.Length > 0 ? all[0] : null;
        }
    }

    public static class Capture {
        public static string PrintWindowToPng(IntPtr hwnd, string path, bool clientOnly, string method) {
            if (!Native.IsWindow(hwnd))
                throw new InvalidOperationException("Invalid window handle.");
            if (Native.IsIconic(hwnd))
                throw new InvalidOperationException("Window is minimized; cannot capture. Use `cwin restore` first.");

            int w, h;
            if (clientOnly) {
                Native.RECT cr; Native.GetClientRect(hwnd, out cr);
                w = cr.Width; h = cr.Height;
            } else {
                Native.RECT wr; Native.GetWindowRect(hwnd, out wr);
                w = wr.Width; h = wr.Height;
            }
            if (w <= 0 || h <= 0) throw new InvalidOperationException("Window has zero size.");

            string actual;
            Bitmap result;
            if (method == "bitblt") {
                result = ScreenBitBlt(hwnd, clientOnly, w, h);
                actual = "bitblt";
            } else {
                result = TryPrintWindow(hwnd, w, h, clientOnly);
                bool empty = result == null || IsLikelyEmpty(result);
                if (!empty) {
                    actual = "print";
                } else {
                    if (result != null) result.Dispose();
                    if (method == "print")
                        throw new InvalidOperationException("PrintWindow returned an empty bitmap. Try --method bitblt (window must be unobscured) or --method auto.");
                    result = ScreenBitBlt(hwnd, clientOnly, w, h);
                    actual = "bitblt";
                }
            }

            try {
                EnsureDirectory(path);
                result.Save(path, ImageFormat.Png);
            } finally {
                result.Dispose();
            }
            return actual;
        }

        private static Bitmap TryPrintWindow(IntPtr hwnd, int w, int h, bool clientOnly) {
            var bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp)) {
                IntPtr hdc = g.GetHdc();
                try {
                    uint flags = Native.PW_RENDERFULLCONTENT | (clientOnly ? Native.PW_CLIENTONLY : 0u);
                    bool ok = Native.PrintWindow(hwnd, hdc, flags);
                    if (!ok) { g.ReleaseHdc(hdc); bmp.Dispose(); return null; }
                } finally {
                    g.ReleaseHdc(hdc);
                }
            }
            return bmp;
        }

        private static Bitmap ScreenBitBlt(IntPtr hwnd, bool clientOnly, int w, int h) {
            Native.POINT origin = new Native.POINT { X = 0, Y = 0 };
            if (clientOnly) {
                Native.ClientToScreen(hwnd, ref origin);
            } else {
                Native.RECT wr; Native.GetWindowRect(hwnd, out wr);
                origin.X = wr.Left; origin.Y = wr.Top;
            }
            var bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp)) {
                IntPtr destDC = g.GetHdc();
                IntPtr srcDC = Native.GetDC(IntPtr.Zero);
                try {
                    Native.BitBlt(destDC, 0, 0, w, h, srcDC, origin.X, origin.Y, Native.SRCCOPY);
                } finally {
                    Native.ReleaseDC(IntPtr.Zero, srcDC);
                    g.ReleaseHdc(destDC);
                }
            }
            return bmp;
        }

        private static bool IsLikelyEmpty(Bitmap bmp) {
            const int samples = 200;
            var rnd = new Random(31);
            var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height),
                                    ImageLockMode.ReadOnly,
                                    System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            try {
                IntPtr ptr = data.Scan0;
                int stride = data.Stride;
                int? first = null;
                int n = Math.Min(samples, bmp.Width * bmp.Height);
                for (int i = 0; i < n; i++) {
                    int x = rnd.Next(bmp.Width);
                    int y = rnd.Next(bmp.Height);
                    int val = Marshal.ReadInt32(ptr, y * stride + x * 4);
                    if (first == null) first = val;
                    else if (val != first.Value) return false;
                }
                return true;
            } finally {
                bmp.UnlockBits(data);
            }
        }

        private static void EnsureDirectory(string path) {
            var dir = Path.GetDirectoryName(Path.GetFullPath(path));
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                Directory.CreateDirectory(dir);
        }
    }

    public static class Input {
        private static readonly HashSet<ushort> ExtendedKeys = new HashSet<ushort> {
            0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
            0x2C, 0x2D, 0x2E,
            0x5B, 0x5C,
            0x6F,
            0x90,
            0xA3, 0xA5
        };

        public static void PostClick(IntPtr topHwnd, int x, int y, string button, bool doubleClick) {
            Native.POINT scr = new Native.POINT { X = x, Y = y };
            Native.ClientToScreen(topHwnd, ref scr);

            // WindowFromPoint is Z-order sensitive — if our window is buried
            // (e.g. after `cwin background`, or simply behind the user's other
            // apps), it returns some other process's HWND at that screen point
            // and our PostMessage goes to the wrong window. Only trust the
            // descendant if it's actually ours.
            IntPtr resolved = Native.WindowFromPoint(scr);
            IntPtr target;
            Native.POINT local;
            if (resolved != IntPtr.Zero && (resolved == topHwnd || Native.IsChild(topHwnd, resolved))) {
                target = resolved;
                local = scr;
                Native.ScreenToClient(target, ref local);
            } else {
                target = topHwnd;
                local = new Native.POINT { X = x, Y = y };
            }

            uint downMsg, upMsg, dblMsg, downBtn;
            switch (button) {
                case "right":
                    downMsg = Native.WM_RBUTTONDOWN; upMsg = Native.WM_RBUTTONUP;
                    dblMsg = Native.WM_RBUTTONDBLCLK; downBtn = Native.MK_RBUTTON; break;
                case "middle":
                    downMsg = Native.WM_MBUTTONDOWN; upMsg = Native.WM_MBUTTONUP;
                    dblMsg = Native.WM_MBUTTONDBLCLK; downBtn = Native.MK_MBUTTON; break;
                default:
                    downMsg = Native.WM_LBUTTONDOWN; upMsg = Native.WM_LBUTTONUP;
                    dblMsg = Native.WM_LBUTTONDBLCLK; downBtn = Native.MK_LBUTTON; break;
            }

            IntPtr lp = MakeLParam(local.X, local.Y);
            Native.PostMessageW(target, Native.WM_MOUSEMOVE, IntPtr.Zero, lp);
            Native.PostMessageW(target, downMsg, (IntPtr)downBtn, lp);
            Native.PostMessageW(target, upMsg, IntPtr.Zero, lp);
            if (doubleClick) {
                Native.PostMessageW(target, dblMsg, (IntPtr)downBtn, lp);
                Native.PostMessageW(target, upMsg, IntPtr.Zero, lp);
            }
        }

        public static void PostText(IntPtr hwnd, string text) {
            foreach (char ch in text) {
                Native.PostMessageW(hwnd, Native.WM_CHAR, (IntPtr)ch, (IntPtr)1);
            }
        }

        public static void PostKey(IntPtr hwnd, ushort vk, ushort[] modVks) {
            bool altInMods = false;
            if (modVks != null) {
                foreach (var m in modVks) {
                    if (m == 0x12 || m == 0xA4 || m == 0xA5) { altInMods = true; break; }
                }
            }
            if (modVks != null) {
                foreach (var m in modVks) PostOneKey(hwnd, m, false, altInMods);
            }
            PostOneKey(hwnd, vk, false, altInMods);
            PostOneKey(hwnd, vk, true, altInMods);
            if (modVks != null) {
                for (int i = modVks.Length - 1; i >= 0; i--) PostOneKey(hwnd, modVks[i], true, altInMods);
            }
        }

        private static void PostOneKey(IntPtr hwnd, ushort vk, bool up, bool syskey) {
            uint scan = Native.MapVirtualKey(vk, Native.MAPVK_VK_TO_VSC);
            bool extended = ExtendedKeys.Contains(vk);

            long lp = 1L;
            lp |= ((long)(scan & 0xFF)) << 16;
            if (extended) lp |= (1L << 24);
            if (syskey)   lp |= (1L << 29);
            if (up)       lp |= (1L << 30) | (1L << 31);

            uint msg = syskey
                ? (up ? Native.WM_SYSKEYUP : Native.WM_SYSKEYDOWN)
                : (up ? Native.WM_KEYUP    : Native.WM_KEYDOWN);
            Native.PostMessageW(hwnd, msg, (IntPtr)vk, (IntPtr)lp);
        }

        private static IntPtr MakeLParam(int x, int y) {
            return (IntPtr)((((long)(y & 0xFFFF)) << 16) | (uint)(x & 0xFFFF));
        }

        public static void SendInputClick(int xScreen, int yScreen, string button, bool doubleClick) {
            int vsX = Native.GetSystemMetrics(Native.SM_XVIRTUALSCREEN);
            int vsY = Native.GetSystemMetrics(Native.SM_YVIRTUALSCREEN);
            int vsW = Native.GetSystemMetrics(Native.SM_CXVIRTUALSCREEN);
            int vsH = Native.GetSystemMetrics(Native.SM_CYVIRTUALSCREEN);
            int nx = (int)Math.Round((xScreen - vsX) * 65535.0 / Math.Max(1, vsW - 1));
            int ny = (int)Math.Round((yScreen - vsY) * 65535.0 / Math.Max(1, vsH - 1));

            uint downFlag, upFlag;
            switch (button) {
                case "right":  downFlag = Native.MOUSEEVENTF_RIGHTDOWN;  upFlag = Native.MOUSEEVENTF_RIGHTUP; break;
                case "middle": downFlag = Native.MOUSEEVENTF_MIDDLEDOWN; upFlag = Native.MOUSEEVENTF_MIDDLEUP; break;
                default:       downFlag = Native.MOUSEEVENTF_LEFTDOWN;   upFlag = Native.MOUSEEVENTF_LEFTUP; break;
            }

            uint baseFlags = Native.MOUSEEVENTF_VIRTUALDESK | Native.MOUSEEVENTF_ABSOLUTE;
            var list = new List<Native.INPUT>();
            list.Add(MakeMouseInput(nx, ny, baseFlags | Native.MOUSEEVENTF_MOVE));
            list.Add(MakeMouseInput(nx, ny, baseFlags | downFlag));
            list.Add(MakeMouseInput(nx, ny, baseFlags | upFlag));
            if (doubleClick) {
                list.Add(MakeMouseInput(nx, ny, baseFlags | downFlag));
                list.Add(MakeMouseInput(nx, ny, baseFlags | upFlag));
            }
            var arr = list.ToArray();
            Native.SendInput((uint)arr.Length, arr, Marshal.SizeOf<Native.INPUT>());
        }

        public static void SendInputText(string text) {
            var list = new List<Native.INPUT>();
            foreach (char ch in text) {
                list.Add(MakeKeyboardInput(0, ch, Native.KEYEVENTF_UNICODE));
                list.Add(MakeKeyboardInput(0, ch, Native.KEYEVENTF_UNICODE | Native.KEYEVENTF_KEYUP));
            }
            var arr = list.ToArray();
            Native.SendInput((uint)arr.Length, arr, Marshal.SizeOf<Native.INPUT>());
        }

        public static void SendInputKey(ushort vk, ushort[] modVks) {
            var list = new List<Native.INPUT>();
            if (modVks != null) foreach (var m in modVks) AddVkInput(list, m, false);
            AddVkInput(list, vk, false);
            AddVkInput(list, vk, true);
            if (modVks != null) for (int i = modVks.Length - 1; i >= 0; i--) AddVkInput(list, modVks[i], true);
            var arr = list.ToArray();
            Native.SendInput((uint)arr.Length, arr, Marshal.SizeOf<Native.INPUT>());
        }

        private static void AddVkInput(List<Native.INPUT> list, ushort vk, bool up) {
            uint scan = Native.MapVirtualKey(vk, Native.MAPVK_VK_TO_VSC);
            uint flags = up ? Native.KEYEVENTF_KEYUP : 0u;
            if (ExtendedKeys.Contains(vk)) flags |= Native.KEYEVENTF_EXTENDEDKEY;
            list.Add(MakeKeyboardInput(vk, (ushort)scan, flags));
        }

        private static Native.INPUT MakeMouseInput(int dx, int dy, uint flags) {
            var input = new Native.INPUT { type = Native.INPUT_MOUSE };
            input.u.mi = new Native.MOUSEINPUT { dx = dx, dy = dy, mouseData = 0, dwFlags = flags, time = 0, dwExtraInfo = UIntPtr.Zero };
            return input;
        }

        private static Native.INPUT MakeKeyboardInput(ushort vk, ushort scan, uint flags) {
            var input = new Native.INPUT { type = Native.INPUT_KEYBOARD };
            input.u.ki = new Native.KEYBDINPUT { wVk = vk, wScan = scan, dwFlags = flags, time = 0, dwExtraInfo = UIntPtr.Zero };
            return input;
        }
    }

    public static class Token {
        public static string GetIntegrityLevel(int pid) {
            IntPtr proc = Native.OpenProcess(Native.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (proc == IntPtr.Zero) return "unknown";
            try {
                IntPtr token;
                if (!Native.OpenProcessToken(proc, Native.TOKEN_QUERY, out token)) return "unknown";
                try {
                    uint needed = 0;
                    Native.GetTokenInformation(token, Native.TokenIntegrityLevel, IntPtr.Zero, 0, out needed);
                    if (needed == 0) return "unknown";
                    IntPtr buf = Marshal.AllocHGlobal((int)needed);
                    try {
                        if (!Native.GetTokenInformation(token, Native.TokenIntegrityLevel, buf, needed, out needed)) return "unknown";
                        IntPtr sid = Marshal.ReadIntPtr(buf);
                        IntPtr countPtr = Native.GetSidSubAuthorityCount(sid);
                        byte count = Marshal.ReadByte(countPtr);
                        IntPtr last = Native.GetSidSubAuthority(sid, (uint)(count - 1));
                        uint rid = (uint)Marshal.ReadInt32(last);
                        if (rid >= Native.SECURITY_MANDATORY_SYSTEM_RID) return "system";
                        if (rid >= Native.SECURITY_MANDATORY_HIGH_RID)   return "high";
                        if (rid >= Native.SECURITY_MANDATORY_MEDIUM_RID) return "medium";
                        return "low";
                    } finally {
                        Marshal.FreeHGlobal(buf);
                    }
                } finally {
                    Native.CloseHandle(token);
                }
            } finally {
                Native.CloseHandle(proc);
            }
        }
    }

    public static class Keys {
        // Map a friendly key name (e.g. "S", "F5", "Enter", "Left") to a virtual-key code.
        public static ushort Resolve(string name) {
            if (string.IsNullOrEmpty(name)) throw new ArgumentException("empty key name");
            string n = name.Trim().ToUpperInvariant();

            // Single-char alpha/digit
            if (n.Length == 1) {
                char c = n[0];
                if (c >= '0' && c <= '9') return (ushort)c;
                if (c >= 'A' && c <= 'Z') return (ushort)c;
            }

            // Function keys
            if (n.Length >= 2 && n[0] == 'F') {
                int fn;
                if (int.TryParse(n.Substring(1), out fn) && fn >= 1 && fn <= 24) return (ushort)(0x6F + fn);
            }

            switch (n) {
                case "BACK": case "BACKSPACE": return 0x08;
                case "TAB":          return 0x09;
                case "ENTER": case "RETURN": return 0x0D;
                case "SHIFT":        return 0x10;
                case "CTRL": case "CONTROL": return 0x11;
                case "ALT": case "MENU": return 0x12;
                case "PAUSE":        return 0x13;
                case "CAPS": case "CAPSLOCK": return 0x14;
                case "ESC": case "ESCAPE":   return 0x1B;
                case "SPACE":        return 0x20;
                case "PGUP": case "PAGEUP":  return 0x21;
                case "PGDN": case "PAGEDOWN": return 0x22;
                case "END":          return 0x23;
                case "HOME":         return 0x24;
                case "LEFT":         return 0x25;
                case "UP":           return 0x26;
                case "RIGHT":        return 0x27;
                case "DOWN":         return 0x28;
                case "PRINTSCREEN": case "PRTSC": return 0x2C;
                case "INSERT": case "INS": return 0x2D;
                case "DELETE": case "DEL": return 0x2E;
                case "WIN": case "LWIN":     return 0x5B;
                case "RWIN":         return 0x5C;
                case "APPS":         return 0x5D;
                case "MULTIPLY":     return 0x6A;
                case "ADD":          return 0x6B;
                case "SEPARATOR":    return 0x6C;
                case "SUBTRACT":     return 0x6D;
                case "DECIMAL":      return 0x6E;
                case "DIVIDE":       return 0x6F;
                case "NUMLOCK":      return 0x90;
                case "SCROLLLOCK": case "SCROLL": return 0x91;
                case "LSHIFT":       return 0xA0;
                case "RSHIFT":       return 0xA1;
                case "LCTRL": case "LCONTROL": return 0xA2;
                case "RCTRL": case "RCONTROL": return 0xA3;
                case "LALT": case "LMENU":     return 0xA4;
                case "RALT": case "RMENU":     return 0xA5;
                case "SEMICOLON": case ";":  return 0xBA;
                case "PLUS": case "=":       return 0xBB;
                case "COMMA": case ",":      return 0xBC;
                case "MINUS": case "-":      return 0xBD;
                case "PERIOD": case ".":     return 0xBE;
                case "SLASH": case "/":      return 0xBF;
                case "TILDE": case "BACKTICK": case "`": return 0xC0;
                case "LBRACKET": case "[":   return 0xDB;
                case "BACKSLASH": case "\\": return 0xDC;
                case "RBRACKET": case "]":   return 0xDD;
                case "QUOTE": case "'":      return 0xDE;
            }

            // Numpad
            if (n.StartsWith("NUMPAD") && n.Length == 7) {
                char c = n[6];
                if (c >= '0' && c <= '9') return (ushort)(0x60 + (c - '0'));
            }

            throw new ArgumentException("Unknown key name: " + name);
        }
    }

    public static class Automation {
        // UIA can be slow to find elements in deep trees. Cap searches.
        private const int FindTimeoutMs = 5000;

        public static AutomationElement FromHwnd(IntPtr hwnd) {
            if (hwnd == IntPtr.Zero) return null;
            try { return AutomationElement.FromHandle(hwnd); }
            catch { return null; }
        }

        public static AutomationElement FromPoint(int xScreen, int yScreen) {
            try { return AutomationElement.FromPoint(new System.Windows.Point(xScreen, yScreen)); }
            catch { return null; }
        }

        // Like FromPoint, but restricted to descendants of `root`. Useful when the
        // target window is obscured by another window at those screen coords —
        // global ElementFromPoint would return the visible-topmost element from
        // some OTHER window. Returns the smallest descendant whose bounding box
        // contains the point and which supports an actionable pattern, or the
        // smallest descendant covering the point if none are actionable.
        public static AutomationElement FromPointInSubtree(AutomationElement root, int xScreen, int yScreen) {
            if (root == null) return null;
            AutomationElement bestAny = null;
            double bestAnyArea = double.MaxValue;
            AutomationElement bestActionable = null;
            double bestActionableArea = double.MaxValue;
            try {
                AutomationElementCollection all = root.FindAll(TreeScope.Descendants | TreeScope.Element, Condition.TrueCondition);
                foreach (AutomationElement e in all) {
                    System.Windows.Rect bb;
                    try { bb = e.Current.BoundingRectangle; } catch { continue; }
                    if (bb.IsEmpty || bb.Width <= 0 || bb.Height <= 0) continue;
                    if (xScreen < bb.Left || xScreen >= bb.Right) continue;
                    if (yScreen < bb.Top  || yScreen >= bb.Bottom) continue;
                    double area = bb.Width * bb.Height;
                    if (area < bestAnyArea) { bestAnyArea = area; bestAny = e; }
                    object _p;
                    bool actionable = e.TryGetCurrentPattern(InvokePattern.Pattern, out _p)
                        || e.TryGetCurrentPattern(TogglePattern.Pattern, out _p)
                        || e.TryGetCurrentPattern(SelectionItemPattern.Pattern, out _p)
                        || e.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out _p);
                    if (actionable && area < bestActionableArea) {
                        bestActionableArea = area;
                        bestActionable = e;
                    }
                }
            } catch { }
            return bestActionable != null ? bestActionable : bestAny;
        }

        public static AutomationElement FindByName(AutomationElement root, string name, bool descendants) {
            if (root == null || string.IsNullOrEmpty(name)) return null;
            var scope = descendants ? (TreeScope.Element | TreeScope.Descendants) : TreeScope.Children;
            var cond = new PropertyCondition(AutomationElement.NameProperty, name);
            try { return root.FindFirst(scope, cond); } catch { return null; }
        }

        public static AutomationElement FindByAutomationId(AutomationElement root, string id, bool descendants) {
            if (root == null || string.IsNullOrEmpty(id)) return null;
            var scope = descendants ? (TreeScope.Element | TreeScope.Descendants) : TreeScope.Children;
            var cond = new PropertyCondition(AutomationElement.AutomationIdProperty, id);
            try { return root.FindFirst(scope, cond); } catch { return null; }
        }

        // Walk up from a UIA element to the nearest ancestor with a real HWND.
        public static IntPtr GetNativeHwnd(AutomationElement elt) {
            var cur = elt;
            while (cur != null) {
                int h = cur.Current.NativeWindowHandle;
                if (h != 0) return new IntPtr(h);
                try { cur = TreeWalker.RawViewWalker.GetParent(cur); }
                catch { break; }
            }
            return IntPtr.Zero;
        }

        // Try the action patterns appropriate for "click-like" intent. Returns the
        // name of the pattern that fired, or null if nothing applicable was found.
        public static string TryInvoke(AutomationElement elt) {
            return TryInvokeOnElement(elt);
        }

        // ElementFromPoint commonly returns the leaf element (a child Pane or
        // TextBlock) which does NOT itself implement Invoke even though the
        // parent Button does. Walk up the UIA tree until we find an actionable
        // pattern. Returns the pattern that fired, or null if none found.
        public static string TryInvokeAtOrAbove(AutomationElement elt, int maxHops) {
            var cur = elt;
            int hops = 0;
            while (cur != null && hops <= maxHops) {
                var r = TryInvokeOnElement(cur);
                if (r != null) return r;
                try { cur = TreeWalker.ControlViewWalker.GetParent(cur); }
                catch { break; }
                hops++;
            }
            return null;
        }

        private static string TryInvokeOnElement(AutomationElement elt) {
            if (elt == null) return null;
            object pat;
            if (elt.TryGetCurrentPattern(InvokePattern.Pattern, out pat)) {
                ((InvokePattern)pat).Invoke();
                return "invoke";
            }
            if (elt.TryGetCurrentPattern(TogglePattern.Pattern, out pat)) {
                ((TogglePattern)pat).Toggle();
                return "toggle";
            }
            if (elt.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pat)) {
                ((SelectionItemPattern)pat).Select();
                return "select";
            }
            if (elt.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out pat)) {
                var ec = (ExpandCollapsePattern)pat;
                if (ec.Current.ExpandCollapseState == ExpandCollapseState.Expanded) ec.Collapse();
                else ec.Expand();
                return "expandcollapse";
            }
            return null;
        }

        public static bool TrySetValue(AutomationElement elt, string text) {
            if (elt == null) return false;
            object pat;
            if (!elt.TryGetCurrentPattern(ValuePattern.Pattern, out pat)) return false;
            var vp = (ValuePattern)pat;
            if (vp.Current.IsReadOnly) return false;
            vp.SetValue(text ?? string.Empty);
            return true;
        }

        // Element used by `keys --method uia` when no explicit element is supplied:
        // the currently focused element inside the target window.
        public static AutomationElement GetFocusedDescendant(AutomationElement window) {
            try {
                var focused = AutomationElement.FocusedElement;
                if (focused == null || window == null) return focused;
                // Verify focused is inside `window` by walking up.
                var cur = focused;
                while (cur != null) {
                    if (Automation.Equals(cur, window)) return focused;
                    try { cur = TreeWalker.RawViewWalker.GetParent(cur); }
                    catch { break; }
                }
                return null;
            } catch { return null; }
        }

        private static bool Equals(AutomationElement a, AutomationElement b) {
            if (a == null || b == null) return false;
            try { return a.Current.NativeWindowHandle != 0 && a.Current.NativeWindowHandle == b.Current.NativeWindowHandle; }
            catch { return false; }
        }

        public class TreeNode {
            public int Depth;
            public string Name;
            public string AutomationId;
            public string ControlType;
            public string ClassName;
            public int Left, Top, Width, Height;
            public bool IsEnabled;
            public bool IsKeyboardFocusable;
            public string Patterns;   // comma-separated, for human display
        }

        public static TreeNode[] DumpTree(AutomationElement root, int maxDepth, bool onlyInteractive) {
            var list = new List<TreeNode>();
            if (root != null) DumpRec(root, 0, maxDepth, onlyInteractive, list);
            return list.ToArray();
        }

        private static void DumpRec(AutomationElement elt, int depth, int maxDepth, bool onlyInteractive, List<TreeNode> list) {
            AutomationElement.AutomationElementInformation c;
            try { c = elt.Current; } catch { return; }

            var pats = new List<string>();
            object p;
            if (elt.TryGetCurrentPattern(InvokePattern.Pattern,         out p)) pats.Add("Invoke");
            if (elt.TryGetCurrentPattern(ValuePattern.Pattern,          out p)) pats.Add("Value");
            if (elt.TryGetCurrentPattern(TogglePattern.Pattern,         out p)) pats.Add("Toggle");
            if (elt.TryGetCurrentPattern(SelectionItemPattern.Pattern,  out p)) pats.Add("SelectionItem");
            if (elt.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out p)) pats.Add("ExpandCollapse");
            if (elt.TryGetCurrentPattern(RangeValuePattern.Pattern,     out p)) pats.Add("RangeValue");
            if (elt.TryGetCurrentPattern(TextPattern.Pattern,           out p)) pats.Add("Text");

            bool interactive = pats.Count > 0;
            if (!onlyInteractive || interactive) {
                var bb = c.BoundingRectangle;
                list.Add(new TreeNode {
                    Depth = depth,
                    Name = c.Name ?? "",
                    AutomationId = c.AutomationId ?? "",
                    ControlType = c.ControlType != null ? c.ControlType.ProgrammaticName : "",
                    ClassName = c.ClassName ?? "",
                    Left = (int)bb.Left, Top = (int)bb.Top,
                    Width = (int)bb.Width, Height = (int)bb.Height,
                    IsEnabled = c.IsEnabled,
                    IsKeyboardFocusable = c.IsKeyboardFocusable,
                    Patterns = string.Join(",", pats.ToArray())
                });
            }
            if (depth >= maxDepth) return;
            AutomationElementCollection kids;
            try { kids = elt.FindAll(TreeScope.Children, Condition.TrueCondition); }
            catch { return; }
            foreach (AutomationElement kid in kids) {
                DumpRec(kid, depth + 1, maxDepth, onlyInteractive, list);
            }
        }
    }
}
