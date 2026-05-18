function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class,
        [Parameter(Mandatory)][string]$Text,
        [string]${uia-name},
        [string]${uia-id},
        [ValidateSet('auto','post','input','uia')][string]$Method = 'auto',
        [switch]${keep-foreground}
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

    # Resolve auto → concrete method. Unlike click, keys does NOT auto-pick uia
    # for XAML classes: ValuePattern.SetValue REPLACES the field contents, which
    # would destroy data in a text editor. Only opt into uia when the user
    # explicitly asks (--method uia or --uia-name/--uia-id).
    $effective = $Method
    if ($effective -eq 'auto') {
        if ($hasUia) { $effective = 'uia' } else { $effective = 'post' }
    }

    switch ($effective) {
        'uia' {
            Initialize-CwinNative
            $root = [Cwin.Automation]::FromHwnd($handle)
            if (-not $root) {
                Write-CwinError "UIA: cannot bind to window 0x$('{0:X}' -f $w.Hwnd)" -ExitCode $script:CwinExit.PinvokeFail
            }
            $target = $null
            if (${uia-id})   { $target = [Cwin.Automation]::FindByAutomationId($root, ${uia-id}, $true) }
            if (-not $target -and ${uia-name}) { $target = [Cwin.Automation]::FindByName($root, ${uia-name}, $true) }
            if (-not $target) { $target = [Cwin.Automation]::GetFocusedDescendant($root) }
            if (-not $target) {
                Write-CwinError "UIA: no target element. Specify --uia-name or --uia-id, or focus the field first." -ExitCode $script:CwinExit.NotFound
            }
            $ok = [Cwin.Automation]::TrySetValue($target, $Text)
            if (-not $ok) {
                Write-CwinError "UIA element does not support ValuePattern (or is read-only). Use --method post or --method input for typing." -ExitCode $script:CwinExit.Unsupported
            }
            Write-CwinWarning "uia mode REPLACES the field's contents (ValuePattern.SetValue). Pass --method post or --method input to append instead."
            return
        }
        'post' {
            $higher = Test-CwinUacMismatch -TargetPid $w.Pid
            if ($higher) {
                Write-CwinWarning "target is $higher-integrity but cwin is not elevated; PostMessage will silently fail."
            }
            [Cwin.Input]::PostText($handle, $Text)
            return
        }
        'input' {
            $prevForeground = [IntPtr]::Zero
            $current = [Cwin.Native]::GetForegroundWindow()
            if ($current -ne $handle) {
                $prevForeground = $current
                [void](Set-CwinForeground -Hwnd $w.Hwnd)
                Start-Sleep -Milliseconds 200
            }
            [Cwin.Input]::SendInputText($Text)
            if ($prevForeground -ne [IntPtr]::Zero -and -not ${keep-foreground}) {
                [void](Set-CwinForeground -Hwnd ([int64]$prevForeground))
            }
            return
        }
    }
}
