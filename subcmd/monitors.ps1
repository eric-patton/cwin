function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param([switch]$Json)
    Initialize-CwinNative
    $mons = [Cwin.Monitors]::Enumerate()
    if ($Json) {
        $shaped = $mons | ForEach-Object {
            [pscustomobject][ordered]@{
                index      = $_.Index
                name       = $_.DeviceName
                x          = $_.X
                y          = $_.Y
                width      = $_.Width
                height     = $_.Height
                workX      = $_.WorkX
                workY      = $_.WorkY
                workWidth  = $_.WorkWidth
                workHeight = $_.WorkHeight
                primary    = $_.IsPrimary
            }
        }
        if (-not $shaped -or $shaped.Count -eq 0) {
            '[]'
        } else {
            ($shaped | ConvertTo-Json -Depth 3 -AsArray)
        }
    } else {
        $rows = foreach ($m in $mons) {
            [pscustomobject][ordered]@{
                Idx     = $m.Index
                Primary = if ($m.IsPrimary) { '*' } else { '' }
                Name    = $m.DeviceName
                Size    = "$($m.Width)x$($m.Height)"
                At      = "$($m.X),$($m.Y)"
                Work    = "$($m.WorkWidth)x$($m.WorkHeight)@$($m.WorkX),$($m.WorkY)"
            }
        }
        $rows | Format-Table -AutoSize | Out-String -Width 200
    }
}
