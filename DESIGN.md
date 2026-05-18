# cwin — design notes and lessons learned

This document explains the *why* behind `cwin` — the decisions, the tradeoffs, and the things that surprised us during the build. The [`README.md`](README.md) covers usage; the repo [`CLAUDE.md`](../CLAUDE.md) is a quick reference for the assistant. This file is the long form.

## 1. Why cwin exists

When the user and Claude iterate on UI / game / desktop work, every loop today requires the user to manually screenshot, click, type, and tell Claude what happened. The goal of `cwin` is to let Claude drive arbitrary windows directly so iteration is faster and the user can keep working in parallel.

Concretely we wanted:

- **screenshot any window** — including occluded ones, including hardware-accelerated ones (Chromium/Electron, UWP, modern Microsoft apps)
- **click anywhere in a window** at known coordinates
- **send text and key chords** to a window
- **all of the above without stealing focus**, so the user can be in another window while Claude drives a third

The "without stealing focus" requirement is the load-bearing constraint. It rules out the easy path (`SendKeys`, `SetForegroundWindow` + `SendInput`, etc.) and forces us into Windows message-posting territory, which is more powerful but has sharper edges.

## 2. High-level design decisions

### 2.1 Single CLI with subcommands (`cwin <verb> ...`) rather than per-verb scripts

Rejected: shipping `cwin-shot.ps1`, `cwin-click.ps1`, `cwin-keys.ps1` as separate entry points.

Why a single entry point won:

- **Discoverability**: `cwin --help` lists everything. With separate scripts the assistant has to remember names.
- **Shared state**: every verb needs the same window-selector logic (`--hwnd`/`--title`/`--pid`/`--class`), the same P/Invoke surface, the same error formatting. Centralizing those in one entry script avoids drift.
- **Standard pattern**: `git`, `gh`, `docker`, `winget` are all single-entry-point-with-subcommands. Both the user and the assistant recognize that shape instantly.

Inside the entry script we dispatch by reading `$args[0]` and dot-sourcing `subcmd\<name>.ps1`. Each subcommand file defines its own `Invoke-CwinSubcommand` function with a normal PowerShell `param()` block. The dispatcher splats the remaining args into that function with `@rest`, and PowerShell's parameter binding takes over from there.

### 2.2 Language: PowerShell entry script + one embedded C# file via `Add-Type`

Considered: pure PowerShell with inline P/Invoke (`Add-Type -MemberDefinition`), Python with `pywin32` or raw `ctypes`, a precompiled C# console executable.

Pure PowerShell P/Invoke is painful as soon as you need structs (`INPUT`, `MOUSEINPUT`, `KEYBDINPUT`, `WINDOWPLACEMENT`, `RECT`), unions, marshalled bitmaps, or `EnumWindows` callbacks. PowerShell's value-type story is fragile and forces ugly `New-Object` + property-assignment patterns.

Python via `pywin32` would have worked but adds a dependency the user does not have today (just `python3.12.exe`, no packages). Pure `ctypes` Python is 80+ lines of `Structure` boilerplate per Win32 struct — no shorter than C#.

A precompiled C# `.exe` is the cleanest code but needs a build step (`dotnet publish`) and a binary to maintain. Out of step with the user's existing PowerShell automation conventions.

PowerShell + embedded C# via `Add-Type` is the right boundary:

- **PowerShell** owns argparse, subcommand dispatch, JSON output, error formatting, stderr/exit codes — things it does well.
- **C#** owns `[DllImport]`s, struct definitions, `INPUT` union layout, bitmap encoding (`Bitmap.Save(path, ImageFormat.Png)`), `SendInput` packing — things PowerShell is bad at.

Cost: one `Add-Type` compile per `cwin` invocation, ~150–300 ms cold (Roslyn). Fine for an interactive iteration tool; would matter for tight loops, in which case a precompiled DLL or a long-lived daemon are options for v2.

### 2.3 PATH shim: `cwin.cmd` for cmd/PowerShell, `cwin` (no extension) for bash

The shim at `C:\Users\ursin\.local\bin\cwin.cmd`:

```cmd
@echo off
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\repos\claude-tools\cwin\cwin.ps1" %*
```

- `.cmd` extension is in `PATHEXT`, so a bare `cwin` resolves from cmd and PowerShell.
- `pwsh.exe`, not `powershell.exe`: PS7 on .NET 9 has noticeably faster startup and modern features.
- `-NoProfile` is mandatory for predictability: anything in `$PROFILE` (PSReadLine themes, lazy-loaded modules) would change startup behavior unpredictably.
- `-ExecutionPolicy Bypass` avoids touching the machine policy (`RemoteSigned`).
- `-File` (not `-Command`) for clean arg quoting.

A second shim at `C:\Users\ursin\.local\bin\cwin` (no extension) for Git Bash:

```bash
#!/usr/bin/env bash
exec pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:/repos/claude-tools/cwin/cwin.ps1" "$@"
```

Git Bash does not honor `PATHEXT`, so without this the bash tool would have to invoke `cwin.cmd` explicitly. The bash variant talks to `pwsh` directly to save one process hop.

### 2.4 File layout

```
cwin\
├── cwin.ps1                  ~50 lines: arg parse, dispatch, error wrap
├── lib\
│   ├── Cwin.Native.cs        ~530 lines: P/Invoke + structs + capture + input
│   ├── windows.ps1           ~180 lines: loader, selector resolution, foreground helper, UAC check
│   ├── output.ps1            ~25 lines: exit codes, error/warning helpers
│   └── help.ps1              ~170 lines: per-subcommand help strings
├── subcmd\
│   ├── list.ps1   info.ps1   shot.ps1   click.ps1
│   ├── keys.ps1   key.ps1    pos.ps1    wait.ps1
│   └── foreground.ps1   restore.ps1
└── test\smoke.ps1            ~110 lines: 11 dispatcher/Win32 regression checks
```

One file per subcommand. Small enough that each is one `Read` for the assistant — useful when editing. Per-command files also let tests dot-source the unit they care about.

## 3. API surface

```
cwin list   [--filter <s>] [--json]
cwin info   <selector> [--json]
cwin shot   <selector> [--out <path>] [--method print|bitblt|auto] [--client]
cwin click  <selector> --x N --y N [--button left|right|middle] [--double] [--method post|input]
cwin keys   <selector> --text "..." [--method post|input]
cwin key    <selector> --key <NAME> [--mods Ctrl,Shift,Alt,Win] [--method post|input]
cwin pos    <selector> [--x N --y N] [--w N --h N] [--state normal|minimized|maximized]
cwin wait   <selector> [--exists|--gone|--idle] [--timeout <ms>]
cwin foreground <selector>
cwin restore    <selector>
```

### 3.1 Selectors

`<selector>` is exactly one of:

- `--hwnd <int>` — decimal or `0x` hex
- `--title <substr>` — case-insensitive substring; `^...` for regex; `=...` for exact
- `--pid <int>`
- `--class <substr>` — same prefix rules as `--title`

Specifying zero or two-plus selectors is a usage error (exit 64). Matching multiple windows is "ambiguous" (exit 2) with a hint listing the first few matches.

The `^regex` / `=exact` prefix idiom keeps the common case terse (just type a substring) while giving deterministic scripting access when needed. Stolen shamelessly from how good CLIs handle this.

### 3.2 `--method post` vs `--method input`

The toolkit's core architectural choice:

- **`post`** (default for `click`, `keys`, `key`) uses `PostMessage` of `WM_LBUTTON*` / `WM_CHAR` / `WM_KEYDOWN`/`WM_KEYUP`. No focus shift, no cursor movement, no foreground transition. Works for traditional Win32 (WPF, WinForms, Win32) and Chromium top-level HWNDs.
- **`input`** uses `SendInput` (real system input). Reliable for almost everything but **steals focus** and moves the cursor.

`shot` is similar: `auto` (default) tries `PrintWindow` + `PW_RENDERFULLCONTENT` and falls back to `BitBlt` from the screen DC when the bitmap looks empty. Explicit `print` and `bitblt` are also exposed.

### 3.3 Exit codes

| code | meaning |
|------|---------|
| 0 | OK |
| 2 | selector matched multiple windows |
| 3 | selector matched no window |
| 4 | P/Invoke failure |
| 5 | unsupported for this window (e.g. screenshotting a minimized window, wait timeout) |
| 64 | usage error (bad flag, missing required arg) |

Scriptable; the smoke test asserts these.

### 3.4 `--json`

`list`, `info`, and errors emit single-line JSON when `--json` is set. The assistant uses this to parse output reliably — substring-parsing a `Format-Table` view would be brittle.

## 4. Win32 implementation notes — the load-bearing details

This section lives here so the next person who touches this code does not have to rediscover the gotchas.

### 4.1 DPI awareness

```csharp
static Native() {
    try { SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2); } catch { }
}
```

This single static initializer is **critical**. Without it, on a 4K monitor at 200% scaling, `GetWindowRect` reports virtualized (unscaled) coordinates, `PrintWindow` writes a virtualized (half-size) bitmap, and screenshots come back half-resolution and blurry. With it, everything is in real pixels.

`DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2` (= `-4`) is the right choice over per-monitor v1 or system-aware. It correctly handles windows that move between monitors with different scale factors.

### 4.2 Window enumeration filters

`EnumWindows` returns *every* top-level window, including a lot of garbage:

- invisible windows (`IsWindowVisible == false`)
- tool windows (`GWL_EXSTYLE & WS_EX_TOOLWINDOW`) — IME, helper overlays
- **cloaked UWP ghosts**: every UWP app you ever launched leaves a top-level `ApplicationFrameWindow` around in a "cloaked" state when suspended. Without filtering, `cwin list` shows the whole UWP history. The fix: `DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, ...)` and skip when non-zero.
- empty-title windows (mostly noise)

`Cwin.Window.EnumerateTopLevel` applies all four filters by default. An `--include-hidden` flag (not in v1) would relax them.

### 4.3 Screenshot: `PrintWindow` + `PW_RENDERFULLCONTENT`

```csharp
uint flags = PW_RENDERFULLCONTENT | (clientOnly ? PW_CLIENTONLY : 0u);
bool ok = Native.PrintWindow(hwnd, hdc, flags);
```

`PW_RENDERFULLCONTENT` (= 0x2) is the magic flag. Without it, capturing any Chromium, Electron, UWP, or modern Microsoft app returns a black rectangle (the GDI DC is empty because DWM composes the real content from a DirectComposition surface). With it, DWM renders the actual visible content into the DC.

It works for:
- Win11 Notepad (XAML/WinAppSDK) ✓ tested
- Calculator (UWP/XAML) ✓ tested  
- Chromium-based apps (Chrome, Edge, Discord, VS Code, Slack, Claude desktop) ✓ tested on Claude desktop
- Traditional Win32 apps ✓ always worked even without the flag

It fails for:
- DRM-protected video surfaces (renders black where the protected region is)
- Some exclusive-fullscreen DirectX games
- Anti-cheat-protected windows (intentionally blocked)

For the failure cases, `--method bitblt` falls back to `BitBlt` from the screen DC at the window's position — correct only when the window is unobscured and on screen. The `auto` method detects "all sampled pixels are identical" (sample 200 random points after `LockBits`) and falls back automatically.

### 4.4 Click target resolution

The caller gives client-area coordinates against the top-level HWND. Posting `WM_LBUTTONDOWN` to the *wrong* HWND silently does nothing — a common trap. The flow:

```
client (X, Y) against top-level
  → ClientToScreen(top, ...)  →  absolute screen coords
  → WindowFromPoint(...)       →  innermost descendant at that point
  → ScreenToClient(target, ...) →  target-relative coords
  → PostMessage(target, WM_LBUTTONDOWN, ...)
```

`WindowFromPoint` (not `ChildWindowFromPoint`) recurses through descendants and respects transparency. It returns:
- traditional Win32 (Notepad legacy, dialogs): the actual `Edit`/`Button`/etc. child control — required for posted clicks to register
- Chromium / Electron: the top-level HWND itself (the whole window is one HWND from outside)
- UWP/XAML: the `ApplicationFrameWindow` or its inner `Windows.UI.Core.CoreWindow` (which then rejects the posted click anyway — see §5.6)

### 4.5 Click message sequence

```
PostMessage(target, WM_MOUSEMOVE,  0,           lParam)    optional, helps hover-reactive UI
PostMessage(target, WM_LBUTTONDOWN, MK_LBUTTON, lParam)
PostMessage(target, WM_LBUTTONUP,   0,          lParam)
[if --double]
PostMessage(target, WM_LBUTTONDBLCLK, MK_LBUTTON, lParam)
PostMessage(target, WM_LBUTTONUP,     0,          lParam)
```

Where `lParam = ((y & 0xFFFF) << 16) | (x & 0xFFFF)` (client coords) and `wParam` for `_DOWN` is `MK_LBUTTON` (= 0x1). The leading `WM_MOUSEMOVE` is cheap and helps controls that only commit "active" state after seeing a recent move.

`(int)` shifts can lose bit 31 on negative inputs. The implementation uses `long` arithmetic in `MakeLParam` to be safe.

### 4.6 Key chord packing

```csharp
long lp = 1L;                              // bits 0-15: repeat count
lp |= ((long)(scan & 0xFF)) << 16;         // bits 16-23: scancode
if (extended) lp |= (1L << 24);            // bit 24: extended key
if (syskey)   lp |= (1L << 29);            // bit 29: context (Alt held)
if (up)       lp |= (1L << 30) | (1L << 31); // bits 30,31: prev state + transition
```

- `scan = MapVirtualKey(vk, MAPVK_VK_TO_VSC)`
- `extended` is true for arrow keys, Ins/Del/Home/End, PgUp/PgDn, right-side modifiers, numpad divide, NumLock, RWin, LWin. `MapVirtualKey` does **not** tell us this — we maintain a small lookup set in `Input.ExtendedKeys`.
- `syskey` is true when Alt is in the mod set. When syskey, post `WM_SYSKEYDOWN`/`WM_SYSKEYUP` instead of `WM_KEYDOWN`/`WM_KEYUP`. Otherwise Alt+F4 etc. silently fail.

Modifier order: down modifiers in given order, then key down+up, then up modifiers in *reverse* order.

### 4.7 Text input: `WM_CHAR` per UTF-16 code unit

```csharp
foreach (char ch in text) {
    Native.PostMessageW(hwnd, Native.WM_CHAR, (IntPtr)ch, (IntPtr)1);
}
```

Most edit controls (legacy `Edit`, `RichEdit`, Scintilla, even Chromium's text inputs) listen to `WM_CHAR` directly without needing `WM_KEYDOWN`. Surrogate pairs (emoji etc.) iterate as two `char`s and post as two `WM_CHAR`s — Windows reassembles them.

### 4.8 SendInput keyboard with `KEYEVENTF_UNICODE`

```csharp
list.Add(MakeKeyboardInput(0, ch, KEYEVENTF_UNICODE));
list.Add(MakeKeyboardInput(0, ch, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
```

`wVk = 0`, `wScan = unicode code unit`, `dwFlags = KEYEVENTF_UNICODE` (and `KEYEVENTF_KEYUP` for release). Keyboard-layout-independent, so this is what we use for text under `--method input`.

For modifier chords under `--method input` we use the VK path:

```csharp
uint scan = MapVirtualKey(vk, MAPVK_VK_TO_VSC);
uint flags = (up ? KEYEVENTF_KEYUP : 0u) | (ExtendedKeys.Contains(vk) ? KEYEVENTF_EXTENDEDKEY : 0u);
list.Add(MakeKeyboardInput(vk, (ushort)scan, flags));
```

### 4.9 SendInput needs the target to be foreground

`SendInput` injects at the system input queue, which dispatches to whatever has foreground. So we must bring the target forward first. The `Set-CwinForeground` helper uses the `AttachThreadInput` trick to bypass Windows' foreground-lock heuristics:

```powershell
$currentTid = [Cwin.Native]::GetCurrentThreadId()
[Cwin.Native]::GetWindowThreadProcessId($h, [ref]$dummy)  # returns targetTid
[void][Cwin.Native]::AttachThreadInput($currentTid, $targetTid, $true)
try {
    if ([Cwin.Native]::IsIconic($h)) { [void][Cwin.Native]::ShowWindow($h, SW_RESTORE) }
    return [Cwin.Native]::SetForegroundWindow($h)
} finally {
    [void][Cwin.Native]::AttachThreadInput($currentTid, $targetTid, $false)
}
```

Attaching the input queues briefly merges them, which lets `SetForegroundWindow` succeed against an unrelated thread that would otherwise be blocked by foreground-lock rules. We detach immediately after.

After bringing the target forward we wait **200 ms** before `SendInput`. The exact number was found empirically (see §5.7); 80 ms was not enough for KEYEVENTF_UNICODE text.

After the input completes, we restore the foreground window the call displaced. The bring-forward step snapshots `GetForegroundWindow()` before activating the target; once `SendInput` returns we feed that HWND back through `Set-CwinForeground`. This keeps `--method input` from leaving focus parked on the click target — the rest of the tool's design is "background where possible," and one-shot input calls should not violate that. The opt-out is `--keep-foreground`, useful when you're about to chain more input into the same target window.

### 4.10 UAC mismatch detection

A non-elevated `cwin` cannot post messages to a higher-integrity (elevated) target — UIPI silently drops the message and `PostMessage` returns success anyway. To stop the user from staring at a no-op, before each `--method post` operation we compare token integrity levels:

```csharp
public static string GetIntegrityLevel(int pid) {
    OpenProcess → OpenProcessToken → GetTokenInformation(TokenIntegrityLevel)
    → read the SID's last sub-authority RID → compare to SECURITY_MANDATORY_{LOW,MEDIUM,HIGH,SYSTEM}_RID
}
```

If the target is higher than self, we emit a warning suggesting `--method input` or running cwin elevated.

### 4.11 UI Automation (UIA) — the second background path

`--method post` covers Win32/WPF/Chromium without focus theft, but XAML/WinUI/UWP windows reject it (§5.6). That left `--method input` as the only working option for stock Microsoft apps, which steals focus and disrupts the user's other work.

The fix is **UI Automation** — Microsoft's accessibility framework, the same channel that screen readers and voice-control tools use. It bypasses the input queue entirely:

- App elements are addressed by `Name` and `AutomationId`, not pixel coordinates.
- Actions go through "patterns" — `InvokePattern.Invoke()` clicks, `ValuePattern.SetValue()` types, `TogglePattern.Toggle()` flips checkboxes, etc.
- Nothing about this requires focus, foreground, or cursor position.

UIA was already in the v2 wishlist (§7 in the previous design). It moved up because:
1. It directly closes the XAML gap that was the user's main pain point.
2. Win11's first-party apps (Calculator, Notepad, Settings) expose excellent UIA trees, so the experience is reliable on the exact apps that were broken.
3. Chromium / Electron also implement UIA, so a single `--method uia` works for Chrome/Edge/VS Code/Discord/Slack/Claude desktop without falling back to PostMessage tricks.

#### Wiring

`System.Windows.Automation` is the .NET wrapper. It lives in `UIAutomationClient.dll` / `UIAutomationTypes.dll`, with `System.Windows.Point` coming from `WindowsBase.dll`. All three ship with the .NET Desktop runtime that PowerShell 7 already uses. They are loaded in `Initialize-CwinNative` (windows.ps1) and their full `.Location` paths are passed to `Add-Type -ReferencedAssemblies` so the embedded C# compile finds them — bare string names didn't resolve under .NET 9.

The wrapper class `Cwin.Automation` exposes a small surface:
- `FromHwnd(hwnd)` → root element for a top-level window
- `FromPoint(x, y)` → element under screen coords (for the coord path of `click --method uia`)
- `FindByName(root, name)` / `FindByAutomationId(root, id)` → descendant lookup
- `TryInvoke(elt)` → tries `InvokePattern` → `TogglePattern` → `SelectionItemPattern` → `ExpandCollapsePattern`, returns the name of whichever fired (or `null`)
- `TrySetValue(elt, text)` → `ValuePattern.SetValue` if the element is writable
- `GetFocusedDescendant(window)` → for `keys --method uia` when no element selector is given
- `DumpTree(root, maxDepth, onlyInteractive)` → flat array used by `cwin uia`

#### Auto-method dispatch

`--method auto` (the new default for click/keys/key) picks per-window:

| subcommand | window class | --uia-* selector | chosen method |
|------------|--------------|------------------|---------------|
| click | XAML/WinUI/UWP | any | uia |
| click | Win32/WPF/Chromium | none | post |
| click | Win32/WPF/Chromium | --uia-name/--uia-id | uia |
| keys | any | --uia-name/--uia-id | uia (REPLACE) |
| keys | any | none | post |
| key | any | any | post |

`keys` deliberately does NOT auto-select uia for XAML, even though click does. `ValuePattern.SetValue` REPLACES the field's contents — auto-clobbering a Notepad document because the user typed `cwin keys` would be surprising-and-destructive. The user opts in explicitly with `--uia-name`/`--uia-id` for replace-style fields (login forms, search boxes).

`key` has no UIA path at all — UIA doesn't model "send Ctrl+S to the app." It would be possible to map a chord to a UIA menu item via accelerator, but that's app-specific and brittle. We document `--method input` as the answer for chords.

The XAML-class detection lives in `Test-CwinIsXamlClass` (windows.ps1) and matches `ApplicationFrameWindow`, `Windows.UI.Core.CoreWindow`, and the `Microsoft.UI.Content.*` / `Microsoft.UI.Composition.*` prefixes for newer WinAppSDK hosts.

#### Already-foreground fast path

`--method input` is still needed sometimes (chords, custom controls). Today's code always calls `Set-CwinForeground` + `Start-Sleep -Milliseconds 200`. That 200 ms is overkill when the target window is *already* the foreground — common when a script clicks a button and then immediately sends a chord into the same app.

Each input-method branch in click/keys/key now compares `[Cwin.Native]::GetForegroundWindow()` against the target HWND first. Match → skip both the foreground hop and the sleep. Miss → bring-forward + wait as before.

#### What UIA does NOT solve

- DirectX games and apps that don't expose accessibility info — still need `--method input` (or are unreachable from outside).
- UAC mismatch — UIA also requires matching integrity for accessibility access.
- Modifier chords on any framework — still need `--method input` (or expose the same action as a UIA menu item).
- Bulk text typing into an editor without replacing the existing content — `ValuePattern.SetValue` is atomic. Workaround: read current value, append, write back; or use `--method input`.

### 4.12 Z-order, placement, and cursor — keeping the user undisturbed

UIA closes the input-method side of "don't disrupt the user." Three more pieces close the *placement* side:

#### `cwin background` — symmetric with `cwin foreground`

`SetWindowPos(hwnd, HWND_BOTTOM, 0,0,0,0, SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE)` drops the target to the bottom of the Z-order without taking focus. If the target WAS the foreground (e.g. a newly-launched app), Windows promotes the next visible window to take its place, so focus naturally returns to whatever the user was working on. Cheap, no race window. Pairs naturally with `Start-Process myapp.exe; cwin background --title MyApp`.

#### `cwin monitors` + `cwin pos --monitor / --anchor` — get it out of the way

Monitor enumeration goes through the standard `EnumDisplayMonitors` callback and pulls per-monitor `MONITORINFOEX` (full rect + work area + primary flag + device name). We sort the result so **primary is always index 1** and the rest are ordered by virtual-screen position. That makes the index stable across runs and across docking changes — `cwin pos --monitor 1` is always the primary, no matter what order the OS hands them back.

`cwin pos` grew two flags:

- `--monitor N` translates the window from its current monitor to monitor N, preserving the relative offset within the monitor and clamping into the new work area so the titlebar stays reachable on a smaller display.
- `--anchor <pos>` docks the window at a corner / edge / center of the chosen monitor's work area, or shoves it past the edge entirely. Positions:
  - `top-left`, `top`, `top-right`
  - `left`, `center`, `right`
  - `bottom-left`, `bottom`, `bottom-right`
  - `offscreen` (alias `offscreen-right`), `offscreen-left`

`--anchor` always operates against the work area (excludes the taskbar), so `bottom-right` lands cleanly above the taskbar rather than under it. Size is preserved unless `--w` / `--h` are also given.

`--x`/`--y` and `--anchor` are mutually exclusive — both prescribe a position. With neither, `--monitor N` translates the current position by the monitor offset.

#### Cursor save/restore for `click --method input`

`SendInput` mouse events warp the system cursor to the click coords. If the user was actively pointing somewhere else, that's a visible jerk. The fix is one extra round trip:

```csharp
GetCursorPos(out origin);
SendInput(...);
SetCursorPos(origin.X, origin.Y);
```

Default ON for `click --method input`. `--keep-cursor` opts out for callers who want the pointer to land at the click point (e.g. when chaining a hover-reactive UI). The `keys` and `key` verbs don't need this — `KEYEVENTF_UNICODE` and VK inputs don't move the cursor.

The brief flicker between SendInput and SetCursorPos is normally one frame and visually a non-event; eliminating it entirely would require driver-level input injection, which is out of scope.

## 5. Things that didn't work, things I learned

### 5.1 .NET 9 split System.Drawing into private satellite assemblies

PowerShell 7.6 runs on .NET 9. On .NET 9, `Graphics.FromImage`'s return type implements interfaces (`IGraphics`, `IPointer<>`) from `System.Private.Windows.GdiPlus` and `System.Private.Windows.Core`. The Roslyn compiler that `Add-Type` invokes needs both as explicit references, even though they ship right next to `System.Drawing.Common.dll`.

The first cascade of errors was:
```
error CS0012: The type 'IGraphics' is defined in an assembly that is not referenced.
  You must add a reference to assembly 'System.Private.Windows.GdiPlus'.
```
Then after adding that one:
```
error CS0012: The type 'IPointer<>' is defined in an assembly that is not referenced.
  You must add a reference to assembly 'System.Private.Windows.Core'.
```

Robust fix in `windows.ps1`: dynamically pick up any `System.Private.Windows.*` assembly in the AppDomain and add it to `-ReferencedAssemblies`. Survives future .NET reshuffles.

### 5.2 PowerShell strict mode + empty arrays from `if` expressions

```powershell
$rest = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)]) } else { @() }
# Later:
if ($rest.Count -gt 0) { ... }
```

Under `Set-StrictMode -Version 3.0` this throws:
```
The property 'Count' cannot be found on this object.
```

Reason: an `if` expression that "outputs" `@()` ends up assigning `$null` (PowerShell's empty-pipeline unrolling). `$null.Count` is a strict-mode error.

Fix: avoid `if` as an expression for arrays; assign explicitly with `[object[]]` and use `.Length`:

```powershell
[object[]]$rest = @()
if ($allArgs.Length -gt 1) {
    $rest = @($allArgs[1..($allArgs.Length - 1)])
}
```

### 5.3 `Nullable[T]` does not survive PowerShell parameter binding

The cleanest C#-style way to express "optional integer parameter" is `[Nullable[int]]$Pid`, and then `if ($Pid.HasValue) { ... $Pid.Value ... }`. This does **not** work reliably under strict mode: when the caller does not supply the parameter, `$Pid` is `$null`, not `Nullable<int>{ HasValue = false }`. Accessing `.HasValue` throws.

Fix used everywhere: take `[string]` and parse, or just type as untyped and test for `$null`:

```powershell
[string]$TargetPid,
...
$pidArg = $null
if ($TargetPid) {
    if ($TargetPid -notmatch '^[0-9]+$') { Write-CwinError "invalid --pid '$TargetPid'" ... }
    $pidArg = [int]$TargetPid
}
```

### 5.4 PowerShell parameter names CAN contain dashes — via `${name}`

`[int]$TimeoutMs` lets the user write `--timeout-ms 500`, right? No: `--timeout-ms` does not bind to `$TimeoutMs` because PowerShell uses `-` as a sigil. The trap is in the **variable syntax**, not the parser. With the `$name` form, hyphens in names are illegal.

But PowerShell has a second variable-name syntax — `${name}` — which DOES accept hyphens (and almost any character). That works for parameter declarations too:

```powershell
param(
    [string]${uia-id},
    [string]${uia-name}
)
# ...
if (${uia-id}) { ... }
```

The CLI flags `--uia-id` and `--uia-name` then bind natively, no dispatcher preprocessing needed. Used for the UIA selectors in click/keys (see §7's UIA entry).

A second, separate trap that we DID hit and gave up on: **`$args` carries hidden parser-time metadata** distinguishing parameter-name tokens from value tokens. When we rebuilt args via `[string]::Concat`, the rebuilt tokens were ignored by parameter binding even though their content was identical. Lesson: don't try to "preprocess and re-splat" — use the brace syntax instead.

For the older `--timeout-ms` style param (declared as `$TimeoutMs`), we still document `--timeout` with `[Alias('TimeoutMs')]` for compatibility. New hyphenated flags should use `${name}` declarations.

### 5.5 `exit` inside helper functions kills polling loops

`Resolve-CwinSelector` calls `Write-CwinError` on no-match, which calls `exit 3`. This exits the entire pwsh process — `try`/`catch` doesn't intercept it. `wait --exists` was supposed to poll until the window appeared, but the first poll's "not found" exited the script with code 3 instead of continuing the loop.

Fix: `wait.ps1` does its own enumeration (`Get-CwinWindows` + manual matching) instead of using `Resolve-CwinSelector`. Cleaner long-term fix would be to convert `Write-CwinError` to throw a typed exception and let the dispatcher decide whether to exit — punted for now.

### 5.6 WinUI 3 / XAML / UWP apps reject PostMessage clicks AND posted WM_CHAR

The big architectural disappointment, but predicted in the design phase. Tested live against Win11 Calculator (`ApplicationFrameWindow`):

- `cwin click --title Calculator --x 75 --y 515` (PostMessage) → display unchanged. No "7" appeared.
- `cwin click --title Calculator --x 75 --y 515 --method input` → display showed "7".

Same for keys against Win11 Notepad. PostMessage `WM_CHAR` to the inner `Windows.UI.Core.CoreWindow` does not surface as text input. `--method input` (with foreground bring-forward) works.

**Practical implication**: for the apps the user and assistant actually build together (WPF, WinForms, plain Win32, Godot, Tauri apps with a Win32 host), PostMessage should work fine. For driving stock Microsoft Win11 apps (Calculator, Settings, Notepad), `--method input` is mandatory.

### 5.7 SendInput timing: 80 ms isn't enough for KEYEVENTF_UNICODE text

Initially `Set-CwinForeground; Start-Sleep 80; SendInput*` worked for clicks but text input vanished. Bumping the sleep to 200 ms fixed it; bumping to 400 ms in isolated tests was fully reliable for an 11-character string. Final value: 200 ms.

The exact reason is not fully nailed down, but the suspicion is that the kernel-level dispatch of KEYEVENTF_UNICODE events into per-thread input queues + cross-thread WM_CHAR conversion takes longer to settle than mouse-event dispatch. 200 ms is empirically generous and still feels snappy for an interactive iteration tool.

### 5.8 ApplicationFrameWindow has a thin titlebar (sort of)

`GetClientRect` on Win11's Calculator (`ApplicationFrameWindow`) returns 480x799 against a 502x810 window — so 11 px of horizontal "border" (left and right combined) and 11 px of vertical "border" (bottom). The titlebar is effectively absent at the OS level; the UWP frame draws its own title and chrome inside the client area. `ClientToScreen(0, 0)` puts you at the window's top edge minus a few pixels of border.

Practical effect: there's no consistent "y offset = titlebar height" you can rely on for modern apps. Always derive coordinates from a screenshot.

### 5.9a PostClick's WindowFromPoint dropped clicks on backgrounded windows

The original `PostClick` resolved the descendant control under the click via `WindowFromPoint(scrX, scrY)`. The intent was right — for traditional Win32 dialogs you have to post `WM_LBUTTON*` to the actual `Edit` / `Button` child HWND, not to the top-level — but `WindowFromPoint` is **Z-order sensitive**. When the target window is buried (after `cwin background`, when another app is covering it, when it's off-screen), `WindowFromPoint` returns whatever HWND is *visible* at that screen point. That belongs to some other process, and the click message goes there instead. Symptom: `cwin click` was a no-op for any window that wasn't on top — even though `cwin keys` worked fine because text/key posting doesn't go through `WindowFromPoint`.

Found while smoke-testing against a Godot game that had been `cwin background`-ed. Keys toggled the in-game inventory; clicks did nothing. Bringing the window forward and re-clicking worked, which pointed straight at Z-order.

Fix: only trust the `WindowFromPoint` result if it's the target itself or a `IsChild`-descendant of it. Otherwise post to the original top-level using the original client coords. This preserves the dialog-child routing for the cases that need it and the obvious behavior for everything else.

```csharp
IntPtr resolved = Native.WindowFromPoint(scr);
IntPtr target; Native.POINT local;
if (resolved != IntPtr.Zero && (resolved == topHwnd || Native.IsChild(topHwnd, resolved))) {
    target = resolved;
    local = scr;
    Native.ScreenToClient(target, ref local);
} else {
    target = topHwnd;
    local = new Native.POINT { X = x, Y = y };
}
```

Regression check in `smoke.ps1`: click a XAML element by post on a backgrounded Calculator and verify the message reaches Calculator (not the visible-topmost window).

### 5.9 PowerShell tool wrapper mangles `$_` in -Command

When invoking `pwsh -Command "... $_ ..."` through the harness's PowerShell tool, `$_` got eaten in some calls and produced parser errors. Workaround: use heredoc-style here-strings (`@'...'@`) when the command needs `$_`, or invoke via the Bash tool with proper escaping. For `cwin.ps1` itself this is a non-issue — it only matters when writing ad-hoc inline scripts.

## 6. Verification

Two layers:

1. **`smoke.ps1`** (11 checks, all passing) covers dispatcher behavior, exit codes, JSON output, error paths, and the screenshot pipeline. Visual correctness is *not* verified — it would require a known reference image. Catches regressions in argparse and P/Invoke.

2. **Live tests during build** (recorded in this session):
   - `list` filters cloaked UWP ghosts ✓
   - `shot` of Win11 Notepad (XAML) renders text correctly ✓
   - `shot` of Claude desktop (Chromium) renders correctly ✓
   - `shot --client` excludes the OS-drawn titlebar ✓
   - `click --method post` on Calculator → no effect (XAML, expected)
   - `click --method input` on Calculator "7" → display shows 7 ✓
   - `keys --method input` typing into Notepad → "HELLO_CWIN" appears ✓
   - `key --mods Ctrl --key Z` (Ctrl+Z chord) → Notepad buffer restored ✓
   - `pos` move/resize/minimize, `restore` un-minimize without activating ✓
   - `wait --exists` (immediate return) and timeout (exit 5) ✓

   Not run in this session (require specific environment):
   - UAC mismatch warning (needs an elevated target window)
   - Multi-monitor + DPI on a non-100% monitor
   - Occluded-window `--method bitblt` fallback

## 7. Out of scope for v1 (revisit if needed)

| feature | sketch |
|---------|--------|
| OCR | `Windows.Media.Ocr.OcrEngine` via WinRT — "what does the screen say?" |
| Image diff | `System.Drawing` pixel compare with mask + threshold; "did anything change?" |
| Mouse drag | extra `WM_MOUSEMOVE` discipline + `MOUSEEVENTF_MOVE` sequence |
| Mouse wheel | `WM_MOUSEWHEEL` with screen-relative `lParam` (different from button messages) |
| Full-screen / multi-monitor capture | no HWND; uses screen DC + `EnumDisplayMonitors` |
| Persistent helper process | sub-100 ms call latency via precompiled DLL or named-pipe daemon |
| Promote to a packaged Claude Code skill | `~/.claude/skills/cwin/SKILL.md` with `allowed-tools` |
| Recording mode | capture real user input for replay |

## 8. Files

| path | purpose |
|------|---------|
| `cwin\cwin.ps1` | entry script: arg parse + subcommand dispatch |
| `cwin\lib\Cwin.Native.cs` | all P/Invoke, structs, capture, input |
| `cwin\lib\windows.ps1` | native loader, selector resolution, foreground helper, UAC check |
| `cwin\lib\output.ps1` | exit codes, error/warning helpers |
| `cwin\lib\help.ps1` | per-subcommand help text |
| `cwin\subcmd\*.ps1` | one file per verb (10 files) |
| `cwin\test\smoke.ps1` | dispatcher + Win32 regression checks |
| `cwin\README.md` | user-facing usage and examples |
| `cwin\DESIGN.md` | this document |
| `CLAUDE.md` (repo root) | quick reference for the assistant |
| `C:\Users\ursin\.local\bin\cwin.cmd` | PATH shim for cmd/PowerShell |
| `C:\Users\ursin\.local\bin\cwin` | PATH shim for bash |
| `C:\Users\ursin\.claude\CLAUDE.md` | (modified) added a pointer block so the assistant uses cwin in future sessions |
