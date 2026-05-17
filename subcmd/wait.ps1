function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class,
        [switch]$Exists,
        [switch]$Gone,
        [switch]$Idle,
        [Alias('TimeoutMs')][int]$Timeout = 5000
    )
    if (-not ($Exists -or $Gone -or $Idle)) { $Exists = $true }
    $modes = @(($Exists, $Gone, $Idle) | Where-Object { $_ })
    if ($modes.Count -gt 1) {
        Write-CwinError "specify only one of --exists/--gone/--idle" -ExitCode $script:CwinExit.UsageError
    }

    Initialize-CwinNative

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

    # In-place match without invoking Resolve-CwinSelector (which exits on no-match).
    $matchScript = {
        $all = Get-CwinWindows
        if ($null -ne $hw) {
            return @($all | Where-Object { $_.Hwnd -eq $hw })
        }
        if ($null -ne $pidArg) {
            return @($all | Where-Object { $_.Pid -eq $pidArg })
        }
        if ($Title) {
            $rawNeedle = $Title; $mode = 'substr'; $needle = $rawNeedle
            if     ($rawNeedle.StartsWith('^')) { $mode = 'regex'; $needle = $rawNeedle.Substring(1) }
            elseif ($rawNeedle.StartsWith('=')) { $mode = 'exact'; $needle = $rawNeedle.Substring(1) }
            switch ($mode) {
                'regex' { return @($all | Where-Object { $_.Title -match $needle }) }
                'exact' { return @($all | Where-Object { $_.Title -eq $needle }) }
                default { return @($all | Where-Object { $_.Title -and ($_.Title.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) }) }
            }
        }
        if ($Class) {
            $rawNeedle = $Class; $mode = 'substr'; $needle = $rawNeedle
            if     ($rawNeedle.StartsWith('^')) { $mode = 'regex'; $needle = $rawNeedle.Substring(1) }
            elseif ($rawNeedle.StartsWith('=')) { $mode = 'exact'; $needle = $rawNeedle.Substring(1) }
            switch ($mode) {
                'regex' { return @($all | Where-Object { $_.ClassName -match $needle }) }
                'exact' { return @($all | Where-Object { $_.ClassName -eq $needle }) }
                default { return @($all | Where-Object { $_.ClassName -and ($_.ClassName.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) }) }
            }
        }
        return @()
    }

    $deadline = [DateTime]::UtcNow.AddMilliseconds($Timeout)

    if ($Idle) {
        $found = @(& $matchScript)
        if ($found.Count -eq 0) { Write-CwinError "no window matched selector" -ExitCode $script:CwinExit.NotFound }
        $procHandle = [System.Diagnostics.Process]::GetProcessById($found[0].Pid).Handle
        $waitMs = [Math]::Max(0, [int]([Math]::Min($Timeout, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)))
        $r = [Cwin.Native]::WaitForInputIdle($procHandle, [uint32]$waitMs)
        if ($r -eq 0) { return }
        Write-CwinError "wait --idle timed out" -ExitCode $script:CwinExit.Unsupported
    }

    while ([DateTime]::UtcNow -lt $deadline) {
        $found = @(& $matchScript)
        if ($Exists -and $found.Count -gt 0) { return }
        if ($Gone   -and $found.Count -eq 0) { return }
        Start-Sleep -Milliseconds 100
    }
    $cond = if ($Exists) { '--exists' } else { '--gone' }
    Write-CwinError "wait $cond timed out after ${Timeout}ms" -ExitCode $script:CwinExit.Unsupported
}
