function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class,
        [Nullable[int]]$X,
        [Nullable[int]]$Y,
        [Alias('W','Width')][Nullable[int]]$Wpx,
        [Alias('H','Height')][Nullable[int]]$Hpx,
        [ValidateSet('normal','minimized','maximized','restored')][string]$State,
        [Nullable[int]]$Monitor,
        [ValidateSet('top-left','top','top-right','left','center','right','bottom-left','bottom','bottom-right','offscreen','offscreen-left','offscreen-right')][string]$Anchor
    )
    $hw = $null
    if ($Hwnd) {
        if     ($Hwnd -match '^0[xX][0-9a-fA-F]+$') { $hw = [int64][Convert]::ToInt64($Hwnd.Substring(2), 16) }
        elseif ($Hwnd -match '^[0-9]+$')             { $hw = [int64]$Hwnd }
        else { Write-CwinError "invalid --hwnd '$Hwnd'" -ExitCode $script:CwinExit.UsageError }
    }
    $pidArg = $null
    if ($TargetPid) {
        if ($TargetPid -notmatch '^[0-9]+$') { Write-CwinError "invalid --pid '$TargetPid'" -ExitCode $script:CwinExit.UsageError }
        $pidArg = [int]$TargetPid
    }
    $w = Resolve-CwinSelector -Hwnd $hw -Title $Title -ProcessId $pidArg -Class $Class
    $handle = [intptr][int64]$w.Hwnd

    if ($State) {
        $cmd = switch ($State) {
            'minimized' { [Cwin.Native]::SW_SHOWMINNOACTIVE }
            'maximized' { [Cwin.Native]::SW_SHOWMAXIMIZED }
            default     { [Cwin.Native]::SW_RESTORE }     # 'normal' / 'restored'
        }
        [void][Cwin.Native]::ShowWindow($handle, $cmd)
        # Re-read geometry after state change so anchor math uses post-state size.
        $w = Resolve-CwinSelector -Hwnd ([int64]$w.Hwnd)
    }

    $hasMove   = ($null -ne $X) -or ($null -ne $Y)
    $hasSize   = ($null -ne $Wpx) -or ($null -ne $Hpx)
    $hasAnchor = [bool]$Anchor
    $hasMon    = ($null -ne $Monitor)

    if ($hasMove -and $hasAnchor) {
        Write-CwinError "specify --x/--y OR --anchor, not both" -ExitCode $script:CwinExit.UsageError
    }

    if (-not ($hasMove -or $hasSize -or $hasAnchor -or $hasMon)) {
        return  # nothing to do; --state alone already handled
    }

    # Decide the target monitor.
    if ($hasMon) {
        $mons = [Cwin.Monitors]::Enumerate()
        if ([int]$Monitor -lt 1 -or [int]$Monitor -gt $mons.Count) {
            Write-CwinError "monitor index $Monitor out of range (1..$($mons.Count)). Run 'cwin monitors' to list." -ExitCode $script:CwinExit.UsageError
        }
        $tgtMon = $mons[[int]$Monitor - 1]
    } else {
        $tgtMon = [Cwin.Monitors]::Containing($handle)
        if (-not $tgtMon) {
            $mons = [Cwin.Monitors]::Enumerate()
            $tgtMon = if ($mons.Count -gt 0) { $mons[0] } else { $null }
        }
    }

    # New size: explicit overrides current.
    $newW = if ($null -ne $Wpx) { [int]$Wpx } else { $w.Width }
    $newH = if ($null -ne $Hpx) { [int]$Hpx } else { $w.Height }

    # New position: anchor > explicit x/y > monitor-translated current > current.
    if ($hasAnchor) {
        if (-not $tgtMon) {
            Write-CwinError "--anchor requires a known monitor; none enumerated" -ExitCode $script:CwinExit.PinvokeFail
        }
        $wx = $tgtMon.WorkX; $wy = $tgtMon.WorkY
        $ww = $tgtMon.WorkWidth; $wh = $tgtMon.WorkHeight
        switch ($Anchor) {
            'top-left'      { $newX = $wx;                   $newY = $wy }
            'top'           { $newX = $wx + [int](($ww - $newW) / 2); $newY = $wy }
            'top-right'     { $newX = $wx + $ww - $newW;     $newY = $wy }
            'left'          { $newX = $wx;                   $newY = $wy + [int](($wh - $newH) / 2) }
            'center'        { $newX = $wx + [int](($ww - $newW) / 2); $newY = $wy + [int](($wh - $newH) / 2) }
            'right'         { $newX = $wx + $ww - $newW;     $newY = $wy + [int](($wh - $newH) / 2) }
            'bottom-left'   { $newX = $wx;                   $newY = $wy + $wh - $newH }
            'bottom'        { $newX = $wx + [int](($ww - $newW) / 2); $newY = $wy + $wh - $newH }
            'bottom-right'  { $newX = $wx + $ww - $newW;     $newY = $wy + $wh - $newH }
            'offscreen'        { $newX = $wx + $ww + 50;      $newY = $wy }
            'offscreen-right'  { $newX = $wx + $ww + 50;      $newY = $wy }
            'offscreen-left'   { $newX = $wx - $newW - 50;    $newY = $wy }
        }
    } elseif ($hasMove) {
        $newX = if ($null -ne $X) { [int]$X } else { $w.X }
        $newY = if ($null -ne $Y) { [int]$Y } else { $w.Y }
    } elseif ($hasMon) {
        # Translate current window position by the offset between the original
        # monitor and the target — preserves the visual placement on the new
        # screen. Clamp into work area so the titlebar stays reachable.
        $srcMon = [Cwin.Monitors]::Containing($handle)
        $offX = if ($srcMon) { $w.X - $srcMon.X } else { 0 }
        $offY = if ($srcMon) { $w.Y - $srcMon.Y } else { 0 }
        $newX = $tgtMon.X + $offX
        $newY = $tgtMon.Y + $offY
        if ($newX + $newW -gt $tgtMon.WorkX + $tgtMon.WorkWidth)  { $newX = $tgtMon.WorkX + $tgtMon.WorkWidth  - $newW }
        if ($newY + $newH -gt $tgtMon.WorkY + $tgtMon.WorkHeight) { $newY = $tgtMon.WorkY + $tgtMon.WorkHeight - $newH }
        if ($newX -lt $tgtMon.WorkX) { $newX = $tgtMon.WorkX }
        if ($newY -lt $tgtMon.WorkY) { $newY = $tgtMon.WorkY }
    } else {
        $newX = $w.X; $newY = $w.Y
    }

    $flags = [uint32]([Cwin.Native]::SWP_NOZORDER -bor [Cwin.Native]::SWP_NOACTIVATE)
    [void][Cwin.Native]::SetWindowPos($handle, [intptr]::Zero, [int]$newX, [int]$newY, [int]$newW, [int]$newH, $flags)
}
