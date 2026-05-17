#!/usr/bin/env pwsh
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$cwinRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $cwinRoot 'lib\output.ps1')
. (Join-Path $cwinRoot 'lib\help.ps1')
. (Join-Path $cwinRoot 'lib\windows.ps1')

[object[]]$allArgs = @($args)
if ($allArgs.Length -eq 0) {
    Show-CwinHelp
    exit 0
}

$sub = [string]$allArgs[0]

[object[]]$rest = @()
if ($allArgs.Length -gt 1) {
    $rest = @($allArgs[1..($allArgs.Length - 1)])
}

if ($sub -in @('--help','-h','-?','help','/?')) {
    $topic = if ($rest.Length -gt 0) { [string]$rest[0] } else { '__main__' }
    Show-CwinHelp $topic
    exit 0
}

foreach ($r in $rest) {
    if ($r -in @('--help','-h','-?')) {
        Show-CwinHelp $sub
        exit 0
    }
}

$subFile = Join-Path $cwinRoot ("subcmd\{0}.ps1" -f $sub)
if (-not (Test-Path -LiteralPath $subFile)) {
    Write-CwinError "unknown subcommand '$sub'. Run 'cwin --help' for the list." -ExitCode $script:CwinExit.UsageError
}

. $subFile
try {
    Invoke-CwinSubcommand @rest
} catch {
    $msg = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
    Write-CwinError $msg -ExitCode $script:CwinExit.PinvokeFail
}
