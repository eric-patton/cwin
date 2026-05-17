function Invoke-CwinSubcommand {
    [CmdletBinding()]
    param(
        [string]$Hwnd,
        [string]$Title,
        [Alias('Pid')][string]$TargetPid,
        [string]$Class,
        [string]$Out,
        [ValidateSet('auto','print','bitblt')][string]$Method = 'auto',
        [switch]$Client
    )
    $hw = $null
    if ($Hwnd) {
        if ($Hwnd -match '^0[xX][0-9a-fA-F]+$') {
            $hw = [int64][Convert]::ToInt64($Hwnd.Substring(2), 16)
        } elseif ($Hwnd -match '^[0-9]+$') {
            $hw = [int64]$Hwnd
        } else {
            Write-CwinError "invalid --hwnd '$Hwnd'" -ExitCode $script:CwinExit.UsageError
        }
    }
    $pidArg = $null
    if ($TargetPid) {
        if ($TargetPid -notmatch '^[0-9]+$') {
            Write-CwinError "invalid --pid '$TargetPid'" -ExitCode $script:CwinExit.UsageError
        }
        $pidArg = [int]$TargetPid
    }
    $w = Resolve-CwinSelector -Hwnd $hw -Title $Title -ProcessId $pidArg -Class $Class

    if (-not $Out) {
        $dir = Join-Path $env:TEMP 'cwin'
        $ts  = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
        $Out = Join-Path $dir ("0x{0:X}-{1}.png" -f $w.Hwnd, $ts)
    } else {
        $Out = [System.IO.Path]::GetFullPath($Out)
    }

    $handle = [intptr][int64]$w.Hwnd
    try {
        $used = [Cwin.Capture]::PrintWindowToPng($handle, $Out, [bool]$Client, $Method)
    } catch [System.InvalidOperationException] {
        $msg = $_.Exception.Message
        if ($msg -match 'minimized') {
            Write-CwinError $msg -ExitCode $script:CwinExit.Unsupported
        }
        Write-CwinError $msg -ExitCode $script:CwinExit.PinvokeFail
    }
    Write-Output $Out
    if ($Method -eq 'auto' -and $used -eq 'bitblt') {
        [Console]::Error.WriteLine("cwin: method=auto fell back to bitblt (PrintWindow returned empty bitmap)")
    }
}
