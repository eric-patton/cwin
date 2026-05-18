Set-StrictMode -Version Latest

$script:CwinHelp = @{}

$script:CwinHelp['__main__'] = @'
cwin - Windows window-control CLI

USAGE
  cwin <subcommand> [options]

SUBCOMMANDS
  list         enumerate visible top-level windows
  info         show details for one window
  monitors     enumerate connected monitors
  shot         screenshot a window to a PNG
  click        click inside a window (background by default)
  keys         type text into a window
  key          send a key chord (e.g. Ctrl+S) to a window
  uia          dump the UIA tree for a window (discovery for --uia-* selectors)
  pos          move/resize/minimize/maximize/restore a window; also --monitor/--anchor
  wait         wait for a window to appear/disappear/idle
  foreground   bring a window to the foreground (steals focus)
  background   send a window to the bottom of the Z-order (no focus shift)
  restore      restore (un-minimize) a window without activating it

SELECTORS (used by every subcommand except `list`)
  --hwnd <int>        exact HWND (decimal or 0x hex)
  --title <substr>    substring, case-insensitive
                      leading '^' = regex; leading '=' = exact match
  --pid <int>         match the first window owned by this process
  --class <substr>    window class name (same prefix rules as --title)

GLOBAL FLAGS
  --json              JSON output where supported (list, info, errors)
  --help, -h          show help for a subcommand: `cwin <sub> --help`

DEFAULT METHODS (background — no focus shift)
  shot   --method auto    PrintWindow + PW_RENDERFULLCONTENT, BitBlt fallback
  click  --method auto    post for Win32/WPF/Chromium, uia for XAML/WinUI/UWP
  keys   --method auto    post by default; uia when --uia-name/--uia-id is given
  key    --method auto    post (no UIA equivalent for arbitrary key chords)

UIA (UI Automation) drives apps through their accessibility tree, so it works
on the XAML/WinUI/UWP cases that reject PostMessage WITHOUT stealing focus.
Use `cwin uia --title X` to discover element names and AutomationIds.

When neither post nor uia works (DirectX games, custom controls that ignore
accessibility, modifier chords that fail because PostMessage cannot update
async keyboard state), re-run with `--method input` — uses SendInput, which
is reliable but steals focus and moves the cursor.

EXIT CODES
  0 OK; 2 selector ambiguous; 3 selector not found; 4 P/Invoke failure;
  5 unsupported for this window; 64 usage error.

Source: C:\repos\claude-tools\cwin\
'@

$script:CwinHelp['list'] = @'
cwin list [--filter <substr>] [--json]

List visible top-level windows. Cloaked UWP ghosts and tool windows are filtered.

OPTIONS
  --filter <substr>   case-insensitive substring filter applied to title
  --json              emit a JSON array

EXAMPLE
  cwin list --filter notepad --json
'@

$script:CwinHelp['info'] = @'
cwin info <selector> [--json]

Print details about a single window (HWND, PID, title, class, geometry, state).
'@

$script:CwinHelp['shot'] = @'
cwin shot <selector> [--out <path>] [--method print|bitblt|auto] [--client]

Screenshot a window to a PNG and print the path.

OPTIONS
  --out <path>        target file. Default: $env:TEMP\cwin\<hwnd>-<ts>.png
  --method <name>     auto (default), print (PrintWindow with PW_RENDERFULLCONTENT),
                      bitblt (BitBlt from screen DC — fails if window is obscured)
  --client            capture client area only (omit titlebar/border)

NOTES
  - `print` is the only method that works for occluded / off-screen windows.
  - Some apps (DRM video surfaces, certain DirectX paths) return black under
    `print`. `auto` falls back to `bitblt` automatically when the bitmap is empty.
  - Minimized windows return exit 5 — use `cwin restore` first.

EXAMPLE
  cwin shot --title "Notepad" --out C:\temp\np.png
'@

$script:CwinHelp['click'] = @'
cwin click <selector> (--x N --y N | --uia-name <s> | --uia-id <s>)
                     [--button left|right|middle] [--double]
                     [--method auto|post|input|uia]
                     [--keep-cursor] [--keep-foreground]

Click inside a window. Two element-resolution modes:
  coords (--x, --y)        target the descendant under those client coords
  UIA selector             target by accessibility name or AutomationId
                           (use `cwin uia --title X` to discover both)

METHOD
  auto   default. uia for XAML/WinUI/UWP (or when --uia-* is given);
                  post for everything else.
  post   PostMessage WM_LBUTTON* — background, but ignored by XAML.
  uia    UI Automation Invoke/Toggle/SelectionItem/ExpandCollapse.
         No focus shift, no cursor movement, works on XAML.
  input  SendInput — must briefly steal focus to inject. By default cwin
         snapshots the cursor and the previous foreground window, then
         restores both after the click. Pass --keep-cursor / --keep-foreground
         to leave the pointer or the focus on the click target instead.

EXAMPLES
  cwin click --title Calculator --uia-id num7Button           # background
  cwin click --title MyApp --x 220 --y 90                     # post path
  cwin click --title Notepad --uia-name "Save" --method uia   # explicit
  cwin click --title MyApp --x 50 --y 50 --method input       # restores fg+cursor
'@

$script:CwinHelp['keys'] = @'
cwin keys <selector> --text "..." [--uia-name <s> | --uia-id <s>]
                     [--method auto|post|input|uia] [--keep-foreground]

Type a string into the window.

METHOD
  auto   default. uia when --uia-name/--uia-id is given; post otherwise.
                  (auto does NOT auto-pick uia for XAML keys — see below.)
  post   PostMessage WM_CHAR per UTF-16 code unit (background, no focus shift).
         Ignored by XAML/WinUI/UWP text inputs.
  uia    ValuePattern.SetValue on the target element. REPLACES the field's
         contents in one call (not append). No focus shift.
  input  SendInput KEYEVENTF_UNICODE — must briefly steal focus to inject.
         By default cwin restores the previous foreground window after; pass
         --keep-foreground to leave focus on the click target instead.

For control keys / chords use `cwin key` instead.

EXAMPLES
  cwin keys --title MyApp --text "hello"
  cwin keys --title Login --uia-id PasswordBox --text "hunter2"   # uia, replace
'@

$script:CwinHelp['key'] = @'
cwin key <selector> --key <NAME> [--mods Ctrl,Shift,Alt,Win]
                    [--method post|input] [--keep-foreground]

Send a single key (optionally with modifiers).

KEY NAMES
  Letters A-Z, digits 0-9, F1..F24, Space, Enter, Tab, Escape, Backspace,
  Delete, Insert, Home, End, PgUp, PgDn, Left/Right/Up/Down, Numpad0..9,
  Multiply/Add/Subtract/Decimal/Divide, NumLock, ScrollLock, CapsLock,
  PrintScreen, Win, Apps, and punctuation glyphs (; = , - . / ` [ \ ] ').

MODIFIERS  Ctrl, Shift, Alt, Win  (comma-separated)

METHOD
  auto  (default) currently aliases to post — UIA has no generic key-chord pattern.
  post  WM_KEYDOWN/UP, or WM_SYSKEYDOWN/UP if Alt is in --mods.
  input SendInput. Use this when chords fail (some apps poll
        GetAsyncKeyState; PostMessage cannot update that state).
        Must briefly steal focus to inject; by default cwin restores the
        previous foreground window after — pass --keep-foreground to opt out.

EXAMPLES
  cwin key --title "Notepad" --key S --mods Ctrl       # Ctrl+S
  cwin key --title "Notepad" --key F4 --mods Alt --method input    # Alt+F4
'@

$script:CwinHelp['uia'] = @'
cwin uia <selector> [--depth N] [--all] [--json]

Dump the UIA (UI Automation) tree for a window. Used to discover the
--uia-name / --uia-id values that drive `cwin click --method uia` etc.

OPTIONS
  --depth N      maximum tree depth (default 4). Most apps want 6-8 for the
                 deep content.
  --all          include non-interactive nodes (panels, containers, layout).
                 By default only nodes that support an actionable pattern
                 (Invoke/Value/Toggle/SelectionItem/ExpandCollapse/RangeValue/
                 Text) are printed.
  --json         emit a JSON array instead of indented text.

OUTPUT FIELDS
  [ControlType]  name='X' id='Y' pat=PatternList WxH@x,y

EXAMPLES
  cwin uia --title Calculator --depth 8
  cwin uia --title MyApp --json | ConvertFrom-Json | Format-Table
'@

$script:CwinHelp['pos'] = @'
cwin pos <selector> [--x N --y N] [--w N --h N]
                    [--monitor N] [--anchor <position>]
                    [--state normal|minimized|maximized]

Move, resize, dock, or change the show-state of a window. SetWindowPos is
invoked with SWP_NOACTIVATE so window focus does not change.

POSITIONING
  --x N --y N            absolute screen coords (top-left corner)
  --w N --h N            new size
  --monitor N            1-indexed monitor (primary=1). Run 'cwin monitors'.
                         With no --anchor, preserves relative position from
                         the old monitor (clamped into the new work area).
  --anchor <position>    dock to a position on the target monitor's work area:
                           top-left, top, top-right
                           left,     center, right
                           bottom-left, bottom, bottom-right
                           offscreen[-left|-right]  (shoves past the edge)

STATE
  --state minimized      minimize without activating (SW_SHOWMINNOACTIVE)
  --state maximized      maximize
  --state normal         restore from minimized/maximized

NOTES
  - --x/--y and --anchor are mutually exclusive (anchor sets position itself).
  - --w/--h work alongside --anchor; if omitted, current size is preserved.
  - With no flags, this is a no-op (use 'cwin info' to read geometry).

EXAMPLES
  cwin pos --title MyApp --anchor bottom-right            # dock out of the way
  cwin pos --title MyApp --anchor offscreen               # shove past right edge
  cwin pos --title MyApp --monitor 2 --anchor center      # center on monitor 2
  cwin pos --title MyApp --x 100 --y 100 --w 1280 --h 720 # absolute
'@

$script:CwinHelp['wait'] = @'
cwin wait <selector> [--exists|--gone|--idle] [--timeout <ms>]

Poll until the window appears, disappears, or its input queue is idle.

OPTIONS
  --exists    return when the selector finds a window (default)
  --gone      return when no window matches the selector
  --idle      return when WaitForInputIdle reports the target ready
  --timeout N  milliseconds (default 5000). Alias: --timeoutMs.

Exit codes: 0 if condition met; 5 on timeout.
'@

$script:CwinHelp['foreground'] = @'
cwin foreground <selector>

Bring a window to the foreground. Uses the AttachThreadInput trick to bypass
Windows foreground-lock heuristics. WARNING: this steals focus from whatever
window the user is interacting with.
'@

$script:CwinHelp['background'] = @'
cwin background <selector>

Send a window to the bottom of the Z-order. Uses SetWindowPos(HWND_BOTTOM,
SWP_NOACTIVATE) so focus is not stolen by this call. If the target window WAS
the foreground, Windows promotes the next visible window to take its place.

Symmetric with `cwin foreground`. Useful for tucking a newly-launched app
behind whatever you were already working on.

EXAMPLE
  Start-Process myapp.exe
  cwin background --title "MyApp"        # push it behind without losing my focus
'@

$script:CwinHelp['monitors'] = @'
cwin monitors [--json]

Enumerate connected displays. Primary monitor is always index 1; remaining
monitors are ordered left-to-right then top-to-bottom by their virtual-screen
coordinates so the index is stable across runs.

COLUMNS  Idx · Primary · Name · Size · At (top-left) · Work area
The Work area excludes the taskbar and any docked shelves.

EXAMPLES
  cwin monitors
  cwin monitors --json | ConvertFrom-Json | Where primary
'@

$script:CwinHelp['restore'] = @'
cwin restore <selector>

Un-minimize a window without activating it (ShowWindow SW_SHOWNOACTIVATE).
'@

function Show-CwinHelp {
    param([string]$Topic = '__main__')
    if (-not $script:CwinHelp.ContainsKey($Topic)) { $Topic = '__main__' }
    Write-Output $script:CwinHelp[$Topic]
}
