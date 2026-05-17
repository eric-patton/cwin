function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class,
        [int]$X,
        [int]$Y,
        [string]${uia-name},
        [string]${uia-id},
        [ValidateSet('left','right','middle')][string]$Button = 'left',
        [switch]$Double,
        [ValidateSet('auto','post','input','uia')][string]$Method = 'auto',
        [switch]${keep-cursor}
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

    $hasUia = [bool](${uia-name} -or ${uia-id})
    $hasCoords = $PSBoundParameters.ContainsKey('X') -or $PSBoundParameters.ContainsKey('Y')
    if (-not $hasUia -and -not $hasCoords) {
        Write-CwinError "specify --x and --y, or --uia-name / --uia-id" -ExitCode $script:CwinExit.UsageError
    }
    if ($hasCoords -and (-not $PSBoundParameters.ContainsKey('X') -or -not $PSBoundParameters.ContainsKey('Y'))) {
        Write-CwinError "--x and --y must be given together" -ExitCode $script:CwinExit.UsageError
    }

    # Resolve auto → concrete method.
    $effective = $Method
    if ($effective -eq 'auto') {
        if ($hasUia -or (Test-CwinIsXamlClass $w.ClassName)) { $effective = 'uia' } else { $effective = 'post' }
    }

    switch ($effective) {
        'uia' {
            Initialize-CwinNative
            $root = [Cwin.Automation]::FromHwnd($handle)
            if (-not $root) {
                Write-CwinError "UIA: cannot bind to window 0x$('{0:X}' -f $w.Hwnd)" -ExitCode $script:CwinExit.PinvokeFail
            }
            $target = $null
            $fromCoords = $false
            if (${uia-id})   { $target = [Cwin.Automation]::FindByAutomationId($root, ${uia-id}, $true) }
            if (-not $target -and ${uia-name}) { $target = [Cwin.Automation]::FindByName($root, ${uia-name}, $true) }
            if (-not $target -and $hasCoords) {
                $pt = New-Object 'Cwin.Native+POINT'
                $pt.X = [int]$X; $pt.Y = [int]$Y
                [void][Cwin.Native]::ClientToScreen($handle, [ref]$pt)
                # Search WITHIN the target window's UIA subtree — global
                # ElementFromPoint would return whatever is visible-topmost at
                # those screen coords, which may belong to a different window.
                $target = [Cwin.Automation]::FromPointInSubtree($root, $pt.X, $pt.Y)
                $fromCoords = $true
            }
            if (-not $target) {
                $hint = if ($hasUia) { "no UIA element matched --uia-name='${uia-name}' / --uia-id='${uia-id}'" } else { "UIA found no element at the given coords" }
                Write-CwinError "$hint. Try 'cwin uia --title ...' to inspect the tree." -ExitCode $script:CwinExit.NotFound
            }
            # ElementFromPoint returns the leaf — walk up to find the actionable
            # ancestor (e.g. the Button surrounding a TextBlock). Named/Id lookups
            # already returned the right element directly.
            $fired = if ($fromCoords) {
                [Cwin.Automation]::TryInvokeAtOrAbove($target, 6)
            } else {
                [Cwin.Automation]::TryInvoke($target)
            }
            if (-not $fired) {
                Write-CwinError "UIA element supports no invokable pattern (Invoke/Toggle/SelectionItem/ExpandCollapse). Use --method post or --method input, or 'cwin uia --title ...' to inspect." -ExitCode $script:CwinExit.Unsupported
            }
            return
        }
        'post' {
            $higher = Test-CwinUacMismatch -TargetPid $w.Pid
            if ($higher) {
                Write-CwinWarning "target is $higher-integrity but cwin is not elevated; PostMessage will silently fail. Re-run as administrator or use --method input."
            }
            [Cwin.Input]::PostClick($handle, [int]$X, [int]$Y, $Button, [bool]$Double)
            return
        }
        'input' {
            # SendInput requires the target to be foreground. Skip the bring-forward
            # round trip entirely when we're already there.
            $current = [Cwin.Native]::GetForegroundWindow()
            if ($current -ne $handle) {
                [void](Set-CwinForeground -Hwnd $w.Hwnd)
                Start-Sleep -Milliseconds 200
            }
            # Snapshot the user's cursor before SendInput jerks it to (X,Y),
            # then snap it back when the click completes — minimizes the visual
            # disruption when the user is actively pointing somewhere else.
            $origCursor = New-Object 'Cwin.Native+POINT'
            $cursorOk = [Cwin.Native]::GetCursorPos([ref]$origCursor)

            $pt = New-Object 'Cwin.Native+POINT'
            $pt.X = [int]$X; $pt.Y = [int]$Y
            [void][Cwin.Native]::ClientToScreen($handle, [ref]$pt)
            [Cwin.Input]::SendInputClick($pt.X, $pt.Y, $Button, [bool]$Double)

            if ($cursorOk -and -not ${keep-cursor}) {
                [void][Cwin.Native]::SetCursorPos([int]$origCursor.X, [int]$origCursor.Y)
            }
            return
        }
    }
}

