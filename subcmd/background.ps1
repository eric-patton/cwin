function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class
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

    # HWND_BOTTOM + SWP_NOACTIVATE drops the window to the bottom of the Z-order
    # without taking focus. If the window WAS the foreground, this also yields
    # focus to whatever was beneath it (Windows promotes the next visible window).
    $flags = [Cwin.Native]::SWP_NOMOVE -bor [Cwin.Native]::SWP_NOSIZE -bor [Cwin.Native]::SWP_NOACTIVATE
    $ok = [Cwin.Native]::SetWindowPos($handle, [Cwin.Native]::HWND_BOTTOM, 0, 0, 0, 0, $flags)
    if (-not $ok) {
        Write-CwinError "SetWindowPos(HWND_BOTTOM) failed" -ExitCode $script:CwinExit.PinvokeFail
    }
}
