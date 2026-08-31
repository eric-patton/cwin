<#
.SYNOPSIS
  Records the README demo GIF: cwin driving a browser while the terminal keeps focus.

.DESCRIPTION
  The thing cwin claims is a negative. The browser changes and your focus never moves, so a
  single-window capture cannot show it. This records both panes at once, where three tells are
  visible in every frame:

    1. Chrome's title bar stays greyed, because it never becomes the foreground window.
    2. The mouse cursor never moves, because nothing here uses SendInput.
    3. This terminal keeps the caret, and its output scrolls as the browser reacts.

  The terminal you run this from becomes the left pane. Nothing is faked: every command printed
  below is the command that actually runs.

.PARAMETER OutFile
  Where the GIF lands. Defaults to docs/images/demo.gif beside the repo.

.PARAMETER Width
  Output width in pixels. The capture is 1900 wide, so anything below that is a downscale and
  costs text sharpness. 1400 is the default: crisp on a high-DPI display, where GitHub renders
  a README image at roughly 900 CSS pixels and doubles it. Pass 1900 for a 1:1 capture.

.PARAMETER Fps
  Frames per second in the GIF. Lower it to buy file size back after raising -Width.

.PARAMETER TrimStart
  Seconds to drop from the front. A fresh recording needs none, because the terminal is
  cleared before capture starts. Kept for re-encoding older captures that caught the setup.

.PARAMETER KeepVideo
  Keep the intermediate .mp4 next to the GIF. Worth passing on the first take, because
  -FromVideo can then re-encode it at another width without occupying the screen again.

.PARAMETER FromVideo
  Skip recording and convert an existing capture. Use it to retune -Width or -Fps.

.EXAMPLE
  .\scripts\record-demo.ps1 -KeepVideo

.EXAMPLE
  .\scripts\record-demo.ps1 -FromVideo docs\images\demo.mp4 -Width 1900

.NOTES
  Needs ffmpeg and Google Chrome on PATH, and cwin resolvable as 'cwin'.
  Do not touch the mouse or keyboard while it records.
#>
[CmdletBinding()]
param(
    [string]$OutFile,
    [ValidateRange(320, 3840)][int]$Width = 1400,
    [ValidateRange(4, 30)][int]$Fps = 10,
    [ValidateRange(0, 60)][double]$TrimStart = 0,
    [switch]$KeepVideo,
    [string]$FromVideo
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path $repo 'docs/images/demo.gif' }

# ---------------------------------------------------------------------------------------------
# Win32. Windows are closed by handle, never by process: Windows Terminal hosts every one of its
# windows in a single process, so taskkill against that PID would take down the terminal you are
# reading this in. WM_CLOSE addresses exactly one window.
# ---------------------------------------------------------------------------------------------
if (-not ('CwinDemo.Win' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CwinDemo {
  public static class Win {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
  }
}
'@
}

function Close-Window {
    param([IntPtr]$Handle)
    $result = [IntPtr]::Zero
    # WM_CLOSE = 0x0010, SMTO_ABORTIFHUNG = 0x0002
    [void][CwinDemo.Win]::SendMessageTimeout($Handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 3000, [ref]$result)
}

function Require-Command {
    param([string]$Name, [string]$Why)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' is not on PATH. $Why"
    }
}

function Type-Line {
    param([string]$Text, [ConsoleColor]$Color = 'White')
    Write-Host '> ' -NoNewline -ForegroundColor DarkGray
    foreach ($ch in $Text.ToCharArray()) {
        Write-Host $ch -NoNewline -ForegroundColor $Color
        Start-Sleep -Milliseconds 12
    }
    Write-Host ''
}

function Convert-ToGif {
    param([string]$Source, [string]$Destination, [int]$W, [int]$F, [double]$Skip = 0)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    # stats_mode=diff builds the palette from what actually changes between frames, which is what
    # keeps the terminal text readable instead of spending the 256 colours on static background.
    $filter = "fps=$F,scale=${W}:-1:flags=lanczos,split[a][b];" +
              '[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3'
    # -ss ahead of -i seeks before decoding, which is what keeps this fast.
    $ffArgs = @('-y', '-loglevel', 'error')
    if ($Skip -gt 0) { $ffArgs += @('-ss', $Skip) }
    $ffArgs += @('-i', $Source, '-vf', $filter, $Destination)
    & ffmpeg @ffArgs
    if ($LASTEXITCODE -ne 0) { throw 'ffmpeg failed to convert the capture to a GIF.' }
    $item = Get-Item $Destination
    $size = [math]::Round($item.Length / 1MB, 2)
    $dims = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $Destination
    Write-Host ''
    Write-Host ("  Wrote {0}  {1}  {2} MB" -f $Destination, $dims, $size) -ForegroundColor Green
    if ($size -gt 5) {
        Write-Host '  Over 5 MB, which loads slowly on mobile. Re-run with a lower -Fps or -Width.' -ForegroundColor Yellow
    }
}

Require-Command 'ffmpeg' 'Install it (winget install Gyan.FFmpeg) and reopen the terminal.'
Require-Command 'cwin'   'Add cwin to PATH, or run this from a shell that resolves it.'

# Re-encoding an existing capture needs none of the staging below.
if ($FromVideo) {
    if (-not (Test-Path $FromVideo)) { throw "No such capture: $FromVideo" }
    if (-not $OutFile) { $OutFile = Join-Path $repo 'docs/images/demo.gif' }
    Convert-ToGif -Source (Resolve-Path $FromVideo) -Destination $OutFile -W $Width -F $Fps -Skip $TrimStart
    return
}

$chromeExe = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chromeExe) { throw 'Google Chrome not found. Edit $chromeExe, or point this at another Chromium browser.' }

# ---------------------------------------------------------------------------------------------
# Layout. Both panes must sit inside the capture region, side by side.
# ---------------------------------------------------------------------------------------------
$region = @{ X = 30; Y = 40; W = 1900; H = 1020 }
$left   = @{ X = 40; Y = 50; W = 920;  H = 1000 }
$right  = @{ X = 980; Y = 50; W = 940; H = 1000 }

$term = [CwinDemo.Win]::GetForegroundWindow()
if ($term -eq [IntPtr]::Zero) { throw 'Could not identify this terminal window.' }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("cwin-demo-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$profileDir = Join-Path $work 'profile'
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
$video = Join-Path $work 'take.mp4'

$chromeWindow = [IntPtr]::Zero
$ffmpeg = $null

try {
    Write-Host ''
    Write-Host '  Positioning panes. Do not touch the mouse or keyboard until this finishes.' -ForegroundColor Yellow
    & cwin pos --hwnd ("0x{0:X}" -f $term.ToInt64()) --state normal | Out-Null
    & cwin pos --hwnd ("0x{0:X}" -f $term.ToInt64()) --x $left.X --y $left.Y --w $left.W --h $left.H | Out-Null

    # A throwaway profile keeps personal tabs, bookmarks and history out of the recording.
    # --force-renderer-accessibility makes Chrome publish its page tree to UIA immediately;
    # without it the first `cwin uia` only sees browser chrome.
    $proc = Start-Process -FilePath $chromeExe -PassThru -ArgumentList @(
        "--user-data-dir=$profileDir"
        '--no-first-run'
        '--no-default-browser-check'
        '--force-renderer-accessibility'
        '--window-size=640,680'
        '--window-position=660,30'
        'https://demo.playwright.dev/todomvc/'
    )

    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
        $row = & cwin list | Select-String 'TodoMVC' | Select-Object -First 1
        if ($row) {
            $chromeWindow = [IntPtr][Convert]::ToInt64(($row.ToString().Trim() -split '\s+')[0], 16)
            break
        }
    }
    if ($chromeWindow -eq [IntPtr]::Zero) { throw 'The demo page never opened. Check the network and try again.' }
    $chrome = "0x{0:X}" -f $chromeWindow.ToInt64()

    & cwin pos --hwnd $chrome --x $right.X --y $right.Y --w $right.W --h $right.H | Out-Null
    Start-Sleep -Seconds 2

    # Clear the staging chatter and paint the title card BEFORE recording starts. gdigrab takes a
    # moment to come up, so anything on screen at that point lands in the first frames; leaving
    # the prompt and the "positioning panes" warning there would put the operator's own paths and
    # a setup message at the front of the GIF.
    Clear-Host
    Write-Host ''
    Write-Host '  cwin' -NoNewline -ForegroundColor Cyan
    Write-Host ' drives the browser on the right.' -ForegroundColor Gray
    Write-Host '  Chrome never takes focus. The mouse never moves.' -ForegroundColor DarkGray
    Write-Host ''

    # Recording runs with a fixed duration so it stops on its own; nothing has to kill it.
    $take = 42
    $ffmpeg = Start-Process -FilePath 'ffmpeg' -PassThru -WindowStyle Hidden -ArgumentList @(
        '-y', '-f', 'gdigrab', '-framerate', '12'
        '-offset_x', $region.X, '-offset_y', $region.Y
        '-video_size', ("{0}x{1}" -f $region.W, $region.H)
        '-i', 'desktop', '-t', $take
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', $video
    )
    # Long enough for gdigrab to be capturing before the first command is typed.
    Start-Sleep -Seconds 3

    # 1. Read the page. Depth matters: the default depth only reaches browser chrome, and the
    #    web content lives well below it.
    Type-Line 'cwin uia --hwnd $chrome --all --depth 30'
    & cwin uia --hwnd $chrome --all --depth 30 2>$null |
        Select-String -Pattern 'Document|CheckBox|Hyperlink' |
        Select-Object -First 5 |
        ForEach-Object {
            $line = $_.ToString().Trim() -replace ' \d+x\d+@\d+,\d+$', ''
            if ($line.Length -gt 58) { $line = $line.Substring(0, 57) + [char]0x2026 }
            Write-Host ('  ' + $line) -ForegroundColor DarkCyan
            Start-Sleep -Milliseconds 140
        }
    Write-Host '  the page, not the browser chrome' -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 1400

    # 2. Type into it. PostMessage, so no focus change and no cursor movement.
    foreach ($task in @('bake the greedy mesher', 'crop the fire frames', 'cut the release')) {
        Write-Host ''
        Type-Line ('cwin keys --hwnd $chrome --text "{0}"' -f $task)
        & cwin keys --hwnd $chrome --text $task 2>$null | Out-Null
        Start-Sleep -Milliseconds 350
        & cwin key --hwnd $chrome --key Enter 2>$null | Out-Null
        Start-Sleep -Milliseconds 550
    }

    # 3. Click by accessible name. The checkbox exposes a Toggle pattern, so UIA invokes it
    #    directly: no coordinates, and nothing breaks when the layout moves.
    Write-Host ''
    Type-Line 'cwin click --hwnd $chrome --uia-name "Toggle Todo"' 'Yellow'
    & cwin click --hwnd $chrome --uia-name 'Toggle Todo' 2>$null | Out-Null
    Write-Host '  clicked by accessible name, not by coordinate' -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 1600

    Write-Host ''
    Write-Host '  Three todos typed, one ticked.' -ForegroundColor Green
    Write-Host '  No focus stolen, no cursor moved, no coordinates guessed.' -ForegroundColor DarkGray

    Write-Host ''
    Write-Host '  Finishing the capture...' -ForegroundColor DarkGray
    $ffmpeg.WaitForExit()
    $ffmpeg = $null

    # Copy the capture out before the finally block deletes the work directory, so -FromVideo
    # can retune the width later without occupying the screen for another take.
    if ($KeepVideo) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $OutFile) -Force | Out-Null
        Copy-Item $video (Join-Path (Split-Path -Parent $OutFile) 'demo.mp4') -Force
    }

    Write-Host '  Converting to GIF...' -ForegroundColor DarkGray
    Convert-ToGif -Source $video -Destination $OutFile -W $Width -F $Fps -Skip $TrimStart
}
finally {
    if ($ffmpeg -and -not $ffmpeg.HasExited) { $ffmpeg.Kill() }
    if ($chromeWindow -ne [IntPtr]::Zero) { Close-Window $chromeWindow }
    Start-Sleep -Seconds 2
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    & cwin pos --hwnd ("0x{0:X}" -f $term.ToInt64()) --state maximized | Out-Null
}
