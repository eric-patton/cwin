function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class,
        [switch]$Json
    )
    $hw = $null
    if ($Hwnd) {
        if ($Hwnd -match '^0[xX][0-9a-fA-F]+$') {
            $hw = [int64][Convert]::ToInt64($Hwnd.Substring(2), 16)
        } elseif ($Hwnd -match '^[0-9]+$') {
            $hw = [int64]$Hwnd
        } else {
            Write-CwinError "invalid --hwnd '$Hwnd' (expected decimal or 0x hex)" -ExitCode $script:CwinExit.UsageError
        }
    }
    $pidArg = $null
    if ($TargetPid) {
        if ($TargetPid -notmatch '^[0-9]+$') {
            Write-CwinError "invalid --pid '$TargetPid' (expected integer)" -ExitCode $script:CwinExit.UsageError
        }
        $pidArg = [int]$TargetPid
    }
    $w = Resolve-CwinSelector -Hwnd $hw -Title $Title -ProcessId $pidArg -Class $Class

    if ($Json) {
        [pscustomobject][ordered]@{
            hwnd      = ('0x{0:X}' -f $w.Hwnd)
            hwndDec   = $w.Hwnd
            pid       = $w.Pid
            title     = $w.Title
            class     = $w.ClassName
            x         = $w.X
            y         = $w.Y
            width     = $w.Width
            height    = $w.Height
            minimized = $w.IsMinimized
            cloaked   = $w.IsCloaked
            visible   = $w.IsVisible
        } | ConvertTo-Json -Depth 4
    } else {
        [pscustomobject][ordered]@{
            Hwnd      = '0x{0:X}' -f $w.Hwnd
            HwndDec   = $w.Hwnd
            Pid       = $w.Pid
            Title     = $w.Title
            Class     = $w.ClassName
            Geometry  = "$($w.X),$($w.Y) $($w.Width)x$($w.Height)"
            Visible   = $w.IsVisible
            Minimized = $w.IsMinimized
            Cloaked   = $w.IsCloaked
        } | Format-List | Out-String
    }
}
