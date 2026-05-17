function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Filter,
        [switch]$Json,
        [switch]$IncludeHidden
    )
    Initialize-CwinNative
    $windows = Get-CwinWindows -IncludeHidden:$IncludeHidden
    if ($Filter) {
        $windows = @($windows | Where-Object {
            $_.Title -and ($_.Title.IndexOf($Filter, [StringComparison]::OrdinalIgnoreCase) -ge 0)
        })
    }
    if ($Json) {
        $shaped = $windows | ForEach-Object {
            [pscustomobject][ordered]@{
                hwnd       = ('0x{0:X}' -f $_.Hwnd)
                hwndDec    = $_.Hwnd
                pid        = $_.Pid
                title      = $_.Title
                class      = $_.ClassName
                x          = $_.X
                y          = $_.Y
                width      = $_.Width
                height     = $_.Height
                minimized  = $_.IsMinimized
                cloaked    = $_.IsCloaked
                visible    = $_.IsVisible
            }
        }
        ($shaped | ConvertTo-Json -Depth 4 -AsArray)
    } else {
        $rows = foreach ($w in $windows) {
            [pscustomobject][ordered]@{
                Hwnd  = '0x{0:X}' -f $w.Hwnd
                Pid   = $w.Pid
                Class = $w.ClassName
                Size  = "$($w.Width)x$($w.Height)"
                Pos   = "$($w.X),$($w.Y)"
                Min   = if ($w.IsMinimized) { 'Y' } else { '' }
                Title = $w.Title
            }
        }
        $rows | Format-Table -AutoSize | Out-String -Width 200
    }
}
