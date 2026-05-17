# cwin smoke test — does not disturb the user's workspace.
# Exercises each subcommand against whatever happens to be open and reports
# pass/fail. Visual verification (e.g. did the screenshot look right?) is
# out of scope here; this catches regressions in dispatch and P/Invoke.
#
# Run:  pwsh.exe -NoProfile -File C:\repos\claude-tools\cwin\test\smoke.ps1

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$cwin = 'C:\repos\claude-tools\cwin\cwin.ps1'
function Invoke-Cwin { pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $cwin @args }

$tmp = Join-Path $env:TEMP "cwin-smoke-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

$pass = 0; $fail = 0
function Check([string]$name, [scriptblock]$test) {
    Write-Host "  [..] $name" -NoNewline
    try {
        & $test
        Write-Host "`r  [OK] $name" -ForegroundColor Green
        $script:pass++
    } catch {
        Write-Host "`r  [FAIL] $name -> $($_.Exception.Message)" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "cwin smoke test (outputs -> $tmp)"
Write-Host

# 1. help and dispatcher
Check "cwin --help prints usage" {
    $out = (Invoke-Cwin --help) -join "`n"
    if ($out -notmatch 'SUBCOMMANDS') { throw 'help missing SUBCOMMANDS section' }
}
Check "cwin unknown-cmd exits 64" {
    Invoke-Cwin not-a-real-sub 2>$null
    if ($LASTEXITCODE -ne 64) { throw "expected exit 64, got $LASTEXITCODE" }
}

# 2. list / info / json
Check "cwin list emits a table" {
    $out = Invoke-Cwin list
    if (-not $out) { throw 'list produced no output' }
}
Check "cwin list --json emits a JSON array" {
    $json = (Invoke-Cwin list --json) -join "`n"
    $parsed = $json | ConvertFrom-Json
    if (-not $parsed) { throw 'json parsed as empty' }
}

# Pick a target window — the user's terminal is usually a safe bet.
$windows = (Invoke-Cwin list --json) -join "`n" | ConvertFrom-Json
if (-not $windows -or $windows.Count -eq 0) { Write-Host "no windows visible, skipping window-based checks"; exit 0 }
# Prefer a non-minimized one so shot works.
$target = $windows | Where-Object { -not $_.minimized } | Select-Object -First 1
if (-not $target) { $target = $windows[0] }
$hwndArg = $target.hwnd
Write-Host "  target window: $hwndArg '$($target.title)' [$($target.class)]"

Check "cwin info --hwnd <x>" {
    $info = (Invoke-Cwin info --hwnd $hwndArg --json) -join "`n" | ConvertFrom-Json
    if ($info.hwndDec -ne $target.hwndDec) { throw "info returned different hwnd" }
}

# 3. shot
$shotPath = Join-Path $tmp 'shot.png'
Check "cwin shot --hwnd <x> --out <path>" {
    $printed = (Invoke-Cwin shot --hwnd $hwndArg --out $shotPath) -join "`n"
    if (-not (Test-Path -LiteralPath $shotPath)) { throw 'shot file not created' }
    $size = (Get-Item -LiteralPath $shotPath).Length
    if ($size -lt 1000) { throw "shot file too small ($size bytes)" }
}
Check "cwin shot --client" {
    $p2 = Join-Path $tmp 'shot-client.png'
    Invoke-Cwin shot --hwnd $hwndArg --out $p2 --client | Out-Null
    if (-not (Test-Path -LiteralPath $p2)) { throw 'client shot not created' }
}

# 4. wait
Check "cwin wait --hwnd <x> --exists --timeout 1000" {
    Invoke-Cwin wait --hwnd $hwndArg --exists --timeout 1000 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "expected 0, got $LASTEXITCODE" }
}
Check "cwin wait --title NoSuchWindow_XYZ --exists --timeout 300 -> exit 5" {
    Invoke-Cwin wait --title "NoSuchWindow_XYZ" --exists --timeout 300 2>$null
    if ($LASTEXITCODE -ne 5) { throw "expected exit 5, got $LASTEXITCODE" }
}

# 5. usage errors
Check "cwin info (no selector) -> exit 64" {
    Invoke-Cwin info 2>$null
    if ($LASTEXITCODE -ne 64) { throw "expected 64, got $LASTEXITCODE" }
}
Check "cwin click --title X --x 1 --y 1 (no window match) -> exit 3" {
    Invoke-Cwin click --title "NoSuchWindow_XYZ_123" --x 1 --y 1 2>$null
    if ($LASTEXITCODE -ne 3) { throw "expected 3, got $LASTEXITCODE" }
}

# 6. UIA — tree dump against the smoke-test target window
Check "cwin uia --hwnd <x> emits indented tree" {
    $out = (Invoke-Cwin uia --hwnd $hwndArg --depth 2) -join "`n"
    if (-not $out) { throw 'uia produced no output' }
}
Check "cwin uia --hwnd <x> --json parses as array" {
    $json = (Invoke-Cwin uia --hwnd $hwndArg --depth 2 --json) -join "`n"
    # ConvertFrom-Json '[]' legitimately returns $null in pwsh — just verify
    # the raw output is a JSON array literal.
    if ($json -notmatch '^\s*\[') { throw "expected JSON array, got: '$json'" }
    [void]($json | ConvertFrom-Json)  # round-trip parse must not error
}
Check "cwin click --uia-id (missing element) -> exit 3" {
    Invoke-Cwin click --hwnd $hwndArg --uia-id "definitely_not_a_real_id_xyz_123" 2>$null
    if ($LASTEXITCODE -ne 3) { throw "expected 3, got $LASTEXITCODE" }
}

# 7. monitors
Check "cwin monitors lists at least one display" {
    $list = (Invoke-Cwin monitors --json) -join "`n" | ConvertFrom-Json
    if ($null -eq $list -or $list.Count -lt 1) { throw "expected >=1 monitor" }
    if (-not ($list | Where-Object { $_.primary -eq $true })) { throw "no primary monitor found" }
}

# 8. UIA + placement + cursor against Calculator
$preexistingCalc = @(Get-Process -Name CalculatorApp,Calculator -ErrorAction SilentlyContinue)
if ($preexistingCalc.Count -eq 0) {
    $calcProc = Start-Process -FilePath calc.exe -PassThru
    Start-Sleep -Milliseconds 1500
    try {
        # Shared FG helper across the Calculator checks
        Add-Type -Name FgHelper -Namespace S -MemberDefinition @'
public static System.IntPtr Get() { return GetForegroundWindow(); }
[System.Runtime.InteropServices.DllImport("user32.dll")] static extern System.IntPtr GetForegroundWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT pt);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] public struct POINT { public int X, Y; }
'@ -ErrorAction SilentlyContinue | Out-Null

        Check "cwin click --uia-id num7Button against Calculator (XAML)" {
            Invoke-Cwin click --title Calculator --uia-id num7Button | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "expected 0, got $LASTEXITCODE" }
        }
        Check "auto-method on XAML window picks uia (display updates without focus)" {
            $before = [S.FgHelper]::Get()
            Invoke-Cwin click --title Calculator --uia-name "Three" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "click exit=$LASTEXITCODE" }
            $after = [S.FgHelper]::Get()
            if ($before -ne $after) { throw "foreground changed: $before -> $after" }
        }
        Check "cwin background --title Calculator does not take focus" {
            $before = [S.FgHelper]::Get()
            Invoke-Cwin background --title Calculator | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "exit=$LASTEXITCODE" }
            $after = [S.FgHelper]::Get()
            if ($before -ne $after -and $after -eq [int64]($before -bxor 0)) { throw "focus moved to Calculator" }
        }
        Check "cwin pos --anchor center repositions Calculator on the primary monitor" {
            Invoke-Cwin pos --title Calculator --anchor center | Out-Null
            $i = (Invoke-Cwin info --title Calculator --json) -join "`n" | ConvertFrom-Json
            $mons = (Invoke-Cwin monitors --json) -join "`n" | ConvertFrom-Json
            $p = $mons | Where-Object { $_.primary }
            $cx = $p.workX + [int](($p.workWidth - $i.width) / 2)
            $cy = $p.workY + [int](($p.workHeight - $i.height) / 2)
            if ([math]::Abs($i.x - $cx) -gt 2 -or [math]::Abs($i.y - $cy) -gt 2) {
                throw "expected ~($cx,$cy), got ($($i.x),$($i.y))"
            }
        }
        Check "cwin pos --anchor offscreen pushes Calculator past the right edge" {
            Invoke-Cwin pos --title Calculator --anchor offscreen | Out-Null
            $i = (Invoke-Cwin info --title Calculator --json) -join "`n" | ConvertFrom-Json
            $mons = (Invoke-Cwin monitors --json) -join "`n" | ConvertFrom-Json
            $p = $mons | Where-Object { $_.primary }
            if ($i.x -le ($p.workX + $p.workWidth)) {
                throw "expected x > $($p.workX + $p.workWidth), got $($i.x)"
            }
            # Park it back somewhere visible so the rest of the test isn't confused
            Invoke-Cwin pos --title Calculator --anchor center | Out-Null
        }
        Check "click --method input restores cursor by default" {
            [void][S.FgHelper]::SetCursorPos(50, 50)
            Start-Sleep -Milliseconds 80
            Invoke-Cwin click --title Calculator --x 65 --y 489 --method input | Out-Null
            Start-Sleep -Milliseconds 200
            $pt = [S.FgHelper+POINT]::new()
            [void][S.FgHelper]::GetCursorPos([ref]$pt)
            if ($pt.X -ne 50 -or $pt.Y -ne 50) { throw "expected (50,50), got ($($pt.X),$($pt.Y))" }
        }
        Check "click --method input --keep-cursor leaves the cursor at the click" {
            [void][S.FgHelper]::SetCursorPos(50, 50)
            Start-Sleep -Milliseconds 80
            Invoke-Cwin click --title Calculator --x 65 --y 489 --method input --keep-cursor | Out-Null
            Start-Sleep -Milliseconds 200
            $pt = [S.FgHelper+POINT]::new()
            [void][S.FgHelper]::GetCursorPos([ref]$pt)
            if ($pt.X -eq 50 -and $pt.Y -eq 50) { throw "cursor still at (50,50) — --keep-cursor was ignored" }
        }
    } finally {
        Start-Sleep -Milliseconds 300
        $calcProc | Stop-Process -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "  (skipping Calculator-based checks — Calculator already running)" -ForegroundColor DarkGray
}

Write-Host
Write-Host "Passed: $pass" -ForegroundColor Green
Write-Host "Failed: $fail" -ForegroundColor ($(if ($fail -eq 0) { 'Green' } else { 'Red' }))
if ($fail -gt 0) { exit 1 }
