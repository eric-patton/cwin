# cwin

A small Windows CLI that lets you (or an LLM coding agent like Claude Code) drive **any** visible window on a Windows 11 machine — screenshot it, click in it, send keys to it, resize and move it — **without stealing focus** in the common case. Built so an interactive session can have the agent iterate on a UI in one window while you keep working in another.

```pwsh
cwin list
cwin shot   --title "MyApp" --out shot.png
cwin click  --title "MyApp" --x 200 --y 150
cwin click  --title "Calculator" --uia-id num7Button     # XAML — UIA path, no focus
cwin keys   --title "MyApp" --text "hello world"
cwin key    --title "MyApp" --key S --mods Ctrl
cwin uia    --title "MyApp"                              # discover element ids
cwin pos    --title "MyApp" --anchor bottom-right        # dock it out of the way
cwin background --title "MyApp"                          # drop to back of Z-order
cwin monitors                                            # list displays
```

`cwin --help` lists every subcommand; `cwin <sub> --help` dives in.

## Why

When a person and an LLM iterate on UI work — a WPF app, a Godot game, a web frontend in a browser, an Electron tool — every loop usually requires the human to take a screenshot, click somewhere, type something, and tell the model what happened. cwin lets the model do it directly. The hard constraint, and the reason this isn't a one-liner around `SendInput`, is **don't disrupt the user**: no focus theft, no cursor jerks, no popping windows in front of what they're typing into.

That constraint forces a layered strategy:

| layer       | API                  | works on                                              | steals focus?    |
|-------------|----------------------|-------------------------------------------------------|------------------|
| **post**    | `PostMessage`        | Win32, WPF, WinForms, Chromium/Electron               | no               |
| **uia**     | UI Automation        | XAML/WinUI/UWP, WPF, Chromium/Electron, and more      | no               |
| **input**   | `SendInput`          | everything that accepts real keyboard/mouse input     | briefly, then restored |

`--method auto` (the default for click/keys/key) picks `post` or `uia` per window class so you almost never need `input`. The few cases where you do — modifier chords like Ctrl+S, apps that don't expose UIA, Flutter desktop windows — get extra polish: cwin skips the 200 ms foreground-settle when the target is already in front, restores the cursor to where it was before the click, and **restores the previously-foreground window after the input completes** so focus lands back where the user left it.

## Install

Source lives in this repo; cwin is a single PowerShell entry script (`cwin.ps1`) that dispatches to per-subcommand scripts. No build step.

Requirements:
- **PowerShell 7** (`pwsh.exe`). Ships with Windows 11 22H2+; install standalone otherwise.
- Windows 10/11.

Add `cwin` to your PATH via shims. On a personal machine I put them in `%USERPROFILE%\.local\bin\` (which I keep on PATH):

**`cwin.cmd`** — for cmd.exe and PowerShell (cmd's PATHEXT picks it up so a bare `cwin` resolves):

```cmd
@echo off
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\cwin\cwin.ps1" %*
```

**`cwin`** (no extension) — for Git Bash / WSL bridge / anything that ignores PATHEXT:

```bash
#!/usr/bin/env bash
exec pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:/path/to/cwin/cwin.ps1" "$@"
```

Cold-start cost is ~150-300 ms per invocation (Roslyn compiles the embedded C# P/Invoke layer the first time per process). Fine for an interactive iteration tool.

## Subcommands

```
cwin list      [--filter <substr>] [--json]
cwin info      <selector> [--json]
cwin monitors  [--json]
cwin shot      <selector> [--out <path>] [--method print|bitblt|auto] [--client]
cwin click     <selector> (--x N --y N | --uia-name <s> | --uia-id <s>)
                          [--button left|right|middle] [--double]
                          [--method auto|post|input|uia] [--keep-cursor]
cwin keys      <selector> --text "..." [--uia-name <s> | --uia-id <s>]
                          [--method auto|post|input|uia]
cwin key       <selector> --key <NAME> [--mods Ctrl,Shift,Alt,Win]
                          [--method auto|post|input]
cwin uia       <selector> [--depth N] [--all] [--json]
cwin pos       <selector> [--x N --y N] [--w N --h N]
                          [--monitor N] [--anchor <position>]
                          [--state normal|minimized|maximized]
cwin wait      <selector> [--exists|--gone|--idle] [--timeout <ms>]
cwin foreground <selector>
cwin background <selector>
cwin restore    <selector>
```

Run `cwin <sub> --help` for the full surface of each.

## Selectors

Every subcommand except `list` and `monitors` takes exactly one selector:

| flag                  | matches                                         |
|-----------------------|-------------------------------------------------|
| `--hwnd <int>`        | exact HWND, decimal or `0x` hex                 |
| `--title <substr>`    | case-insensitive substring on the window title  |
| `--pid <int>`         | first visible top-level window owned by the PID |
| `--class <substr>`    | window class name                               |

Both `--title` and `--class` accept prefix sigils for stricter matching:
- `^pattern` — treat as a regex
- `=exact` — exact match (case-insensitive)

Ambiguous matches exit `2`; missing matches exit `3`.

## The method trifecta

`--method auto` is the default for `click` / `keys` / `key` and picks per window:

- **click**: XAML/WinUI/UWP (`ApplicationFrameWindow`, `Windows.UI.Core.CoreWindow`, `Microsoft.UI.*`) → uia. Everything else → post.
- **keys**: post by default. Switches to uia only when `--uia-name` / `--uia-id` is given explicitly — because UIA `ValuePattern.SetValue` **replaces** the field's contents, which would clobber an open editor if auto kicked in.
- **key**: post. UIA has no general key-chord pattern; for chords that need real `GetAsyncKeyState` updates (Ctrl+S etc.), pass `--method input` explicitly.

You can always override. The four methods:

### `--method post` — PostMessage

`PostMessage(WM_LBUTTONDOWN/UP)`, `WM_CHAR` per code unit, `WM_KEYDOWN/UP` (or `WM_SYSKEY*` if Alt is in the mods). For clicks, the actual descendant HWND under the coordinate is found via `WindowFromPoint` so child controls (Edit, Button, etc.) receive the message directly.

Works on Win32, WPF, WinForms, and Chromium/Electron top-level HWNDs. **Ignored** by XAML/WinUI/UWP and often by apps that poll `GetAsyncKeyState` from inside their key handlers.

### `--method uia` — UI Automation

The Microsoft-recommended way for accessibility tools to drive apps. cwin uses `System.Windows.Automation` (`UIAutomationClient.dll`) to:

- find elements by Name (`--uia-name`), AutomationId (`--uia-id`), or coordinates (`ElementFromPoint`, scoped to the target window's UIA subtree),
- invoke them via the standard patterns: `InvokePattern` (buttons, menu items), `TogglePattern` (checkboxes), `SelectionItemPattern` (list items, tabs), `ExpandCollapsePattern` (menus, trees), `ValuePattern` (text inputs).

For clicks from coordinates the search walks up to the nearest invokable ancestor — XAML composes complex controls from non-invokable leaves (a Button wraps a Pane wraps a TextBlock), so `ElementFromPoint` rarely lands directly on the invokable element.

`cwin uia --title MyApp` dumps the interactive tree to discover element names/ids.

### `--method input` — SendInput (universal fallback)

Real system-level input. Reliable for almost everything but **briefly takes focus** and moves the cursor. cwin pre-brings the target to foreground (using the `AttachThreadInput` trick to bypass Windows' foreground-lock heuristics) and waits 200 ms before injecting — empirically the minimum settle time for `KEYEVENTF_UNICODE` text. Three small kindnesses:

- The 200 ms wait is **skipped** if `GetForegroundWindow() == target` already.
- For `click --method input`, the cursor is **snapshotted before and restored after** by default. Pass `--keep-cursor` to leave it at the click point.
- The previous foreground window is **restored after the input completes**, so the call doesn't park focus on the click target. Works for `click`, `key`, and `keys`. Pass `--keep-foreground` to opt out when chaining more input into the same target.

### `--method auto` for `shot`

`shot` is independent: `auto` tries `PrintWindow(PW_RENDERFULLCONTENT)` (the only reliable way to capture Chromium/Electron/UWP via DWM composition) and falls back to `BitBlt` from the screen DC if the bitmap is empty (200 sampled pixels all identical).

## Placement — getting windows out of your way

These compose nicely:

```pwsh
Start-Process myapp.exe
cwin background --title "MyApp"                # ↓ push behind whatever I'm doing
cwin pos --title "MyApp" --anchor bottom-right # ↘ dock it
cwin pos --title "MyApp" --anchor offscreen    # ⤴ shove it past the right edge
cwin pos --title "MyApp" --monitor 2 --anchor center  # → throw it onto monitor 2, centered
```

`cwin monitors` enumerates displays. **Primary is always index 1**; the rest are stable-ordered by virtual-screen position.

`pos --anchor` positions:
- corners and edges: `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`
- offscreen: `offscreen` (alias for `offscreen-right`), `offscreen-left`

All positions are computed against the target monitor's **work area** (excludes the taskbar), so `bottom-right` lands cleanly above the taskbar rather than under it.

## Exit codes

| code | meaning                                                |
|------|--------------------------------------------------------|
| 0    | OK                                                     |
| 2    | selector matched multiple windows (ambiguous)          |
| 3    | selector matched no window                             |
| 4    | P/Invoke or compile failure                            |
| 5    | unsupported for this window (e.g. shot of a minimized) |
| 64   | usage error (bad flag, missing required arg, etc.)    |

All `--json` paths emit single-line JSON errors so scripts can parse.

## Known limits

- **Modifier chords** (Ctrl+S, Alt+F4) often need `--method input`. Many apps poll `GetAsyncKeyState` from inside `WM_KEYDOWN`, and `PostMessage` cannot update async keyboard state; UIA has no key-chord pattern.
- **DirectX exclusive-fullscreen games** reject both PostMessage and posted clicks; `input` works for input but `PrintWindow` may return black. `auto` falls back to `bitblt` automatically if the window is unobscured.
- **Anti-cheat-protected games** (EAC, BattlEye, VAC) detect and block input injection. Do not target them.
- **UAC-elevated targets**: a non-elevated `cwin` cannot post messages to a higher-integrity window (UIPI silently drops them). cwin detects and warns; re-run elevated or use `--method input`.
- **DRM video surfaces** (Netflix in Edge, etc.) capture as black.
- `keys --method uia` **replaces** field contents (`ValuePattern.SetValue` is atomic). To **append** text into a XAML editor, use `--method input`.

## Layout

```
cwin.ps1                       # dispatcher: arg parse, subcommand load, error wrap
lib/
  Cwin.Native.cs               # all P/Invoke + UIA wrapper + Capture + Monitors
  windows.ps1                  # Add-Type loader, selector resolution, FG helper, UAC check
  output.ps1                   # exit codes, error/warning helpers
  help.ps1                     # per-subcommand help text
subcmd/
  list.ps1   info.ps1   monitors.ps1
  shot.ps1
  click.ps1  keys.ps1   key.ps1   uia.ps1
  pos.ps1    wait.ps1
  foreground.ps1   background.ps1   restore.ps1
test/
  smoke.ps1                    # dispatcher + Win32 + UIA + placement regression checks
scripts/
  record-demo.ps1              # records the two-pane demo capture (see Demo)
DESIGN.md                      # the *why* behind every nontrivial decision
```

One file per subcommand. All Win32/UIA work is centralized in `lib/Cwin.Native.cs` and compiled once per invocation via `Add-Type`.

## Test

```pwsh
pwsh -NoProfile -File test\smoke.ps1
```

22 checks covering dispatcher behavior, exit codes, JSON output, shot pipeline, the UIA paths, placement (`--anchor`, `--monitor`, `monitors`, `background`), and cursor restore. Most checks run against whatever windows are open; a few launch Calculator briefly to exercise the XAML/UIA paths and clean up after themselves.

## Demo

What cwin does is hard to screenshot, because the claim is a negative: the target app changes and
your focus never moves. A single window cannot show that, so the demo records two panes at once.

```pwsh
pwsh -NoProfile -File scriptsecord-demo.ps1
```

The terminal you run it from becomes the left pane. It opens a throwaway-profile Chrome on a
public TodoMVC demo as the right pane, reads the page's accessibility tree, types three todos into
it, ticks one by accessible name, and records the whole thing with ffmpeg into
`docs/images/demo.gif`. Needs ffmpeg and Chrome on PATH. Leave the mouse and keyboard alone while
it runs, and note it occupies the screen for about 45 seconds.

Three tells are visible in every frame, and together they are the whole argument:

1. **Chrome's title bar stays greyed.** It is never the foreground window.
2. **The cursor never moves.** Nothing in the sequence uses SendInput.
3. **The terminal keeps the caret** and its output scrolls while the browser reacts.

Nothing is staged: each command printed in the left pane is the command that then runs. The script
also cleans up after itself, closing the browser by window handle rather than by process, for the
reason in [DESIGN.md](DESIGN.md) about shared-process hosts.

## Design notes

See [DESIGN.md](DESIGN.md) for the long form: why PostMessage for some apps but not others, why UIA, the `AttachThreadInput` trick, the 200 ms timing, the `PW_RENDERFULLCONTENT` flag, the things that didn't work, and the things that surprised us.

## Contributing

cwin is intentionally small. Keep it that way. Before adding a new subcommand, check if the verb fits inside an existing one — e.g. anchoring lives in `pos` rather than getting its own `dock` verb.

When touching Win32 P/Invoke, prefer adding to `lib/Cwin.Native.cs` over scattering `[DllImport]` declarations across PowerShell scripts. The single-compile model keeps cold-start fast and the surface auditable.
