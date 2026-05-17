function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class,
        [Parameter(Mandatory)][string]$Key,
        [string]$Mods,
        [ValidateSet('auto','post','input')][string]$Method = 'auto'
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

    try {
        $vk = [Cwin.Keys]::Resolve($Key)
    } catch {
        Write-CwinError "unknown --key '$Key': $($_.Exception.Message)" -ExitCode $script:CwinExit.UsageError
    }

    $modVks = [System.Collections.Generic.List[uint16]]::new()
    if ($Mods) {
        foreach ($name in ($Mods -split '[,\s]+' | Where-Object { $_ })) {
            $modName = $name.Trim().ToUpperInvariant()
            $modVk = switch ($modName) {
                'CTRL'    { 0x11 }
                'CONTROL' { 0x11 }
                'SHIFT'   { 0x10 }
                'ALT'     { 0x12 }
                'MENU'    { 0x12 }
                'WIN'     { 0x5B }
                default {
                    Write-CwinError "unknown modifier '$name' (expected Ctrl/Shift/Alt/Win)" -ExitCode $script:CwinExit.UsageError
                }
            }
            [void]$modVks.Add([uint16]$modVk)
        }
    }
    $modArr = $modVks.ToArray()

    # No UIA equivalent for arbitrary key chords — auto stays at today's post
    # behavior. Document in DESIGN.md / CLAUDE.md that chords usually need
    # --method input regardless of window class because apps poll GetAsyncKeyState
    # (DESIGN.md §5.6), which PostMessage cannot update.
    $effective = if ($Method -eq 'auto') { 'post' } else { $Method }

    if ($effective -eq 'post') {
        $higher = Test-CwinUacMismatch -TargetPid $w.Pid
        if ($higher) {
            Write-CwinWarning "target is $higher-integrity but cwin is not elevated; PostMessage will silently fail."
        }
        [Cwin.Input]::PostKey($handle, [uint16]$vk, $modArr)
    } else {
        # SendInput requires the target to be foreground. Skip the bring-forward
        # round trip entirely when we're already there.
        $current = [Cwin.Native]::GetForegroundWindow()
        if ($current -ne $handle) {
            [void](Set-CwinForeground -Hwnd $w.Hwnd)
            Start-Sleep -Milliseconds 200
        }
        [Cwin.Input]::SendInputKey([uint16]$vk, $modArr)
    }
}
