function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class,
        [Alias('MaxDepth')][int]$Depth = 4,
        [switch]$All,
        [switch]$Json
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

    Initialize-CwinNative
    $root = [Cwin.Automation]::FromHwnd($handle)
    if (-not $root) {
        Write-CwinError "UIA: cannot bind to window 0x$('{0:X}' -f $w.Hwnd)" -ExitCode $script:CwinExit.PinvokeFail
    }

    # Default to "interactive elements only" — the noise-to-signal of the raw
    # tree is brutal. --all switches to the full tree.
    $onlyInteractive = -not $All
    $nodes = [Cwin.Automation]::DumpTree($root, [int]$Depth, [bool]$onlyInteractive)

    if ($Json) {
        if (-not $nodes -or $nodes.Count -eq 0) {
            '[]'
            return
        }
        $shaped = @($nodes | ForEach-Object {
            [pscustomobject][ordered]@{
                depth        = $_.Depth
                name         = $_.Name
                automationId = $_.AutomationId
                controlType  = $_.ControlType
                className    = $_.ClassName
                x            = $_.Left
                y            = $_.Top
                width        = $_.Width
                height       = $_.Height
                enabled      = $_.IsEnabled
                focusable    = $_.IsKeyboardFocusable
                patterns     = if ($_.Patterns) { $_.Patterns.Split(',') } else { @() }
            }
        })
        ($shaped | ConvertTo-Json -Depth 4 -AsArray)
    } else {
        if ($nodes.Count -eq 0) {
            Write-Host "no UIA elements found at depth <= $Depth ($(if ($onlyInteractive) { 'interactive only — pass --all to widen' } else { 'tree is empty' }))"
            return
        }
        foreach ($n in $nodes) {
            $indent = '  ' * $n.Depth
            $type = if ($n.ControlType) { $n.ControlType -replace '^ControlType\.','' } else { '?' }
            $head = "{0}[{1}]" -f $indent, $type
            $bits = @()
            if ($n.Name)         { $bits += "name='{0}'" -f $n.Name }
            if ($n.AutomationId) { $bits += "id='{0}'"   -f $n.AutomationId }
            if ($n.Patterns)     { $bits += "pat={0}"    -f $n.Patterns }
            if ($n.Width -gt 0 -and $n.Height -gt 0) {
                $bits += "{0}x{1}@{2},{3}" -f $n.Width, $n.Height, $n.Left, $n.Top
            }
            Write-Host ($head + ' ' + ($bits -join ' '))
        }
    }
}
