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
    $ok = Set-CwinForeground -Hwnd $w.Hwnd
    if (-not $ok) {
        Write-CwinError "SetForegroundWindow returned false (Windows foreground-lock may have suppressed the change)" -ExitCode $script:CwinExit.Unsupported
    }
}
