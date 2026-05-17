Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CwinExit = @{
    Ok          = 0
    Ambiguous   = 2
    NotFound    = 3
    PinvokeFail = 4
    Unsupported = 5
    UsageError  = 64
}

function Write-CwinError {
    param(
        [Parameter(Mandatory)][string]$Message,
        [int]$ExitCode = $script:CwinExit.UsageError,
        [switch]$AsJson
    )
    if ($AsJson) {
        $obj = [ordered]@{ ok = $false; error = $Message; exitCode = $ExitCode }
        [Console]::Error.WriteLine(($obj | ConvertTo-Json -Compress -Depth 4))
    } else {
        [Console]::Error.WriteLine("cwin: $Message")
    }
    exit $ExitCode
}

function Write-CwinWarning {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine("cwin: warning: $Message")
}

function Write-CwinJson {
    param([Parameter(Mandatory, ValueFromPipeline)]$Object, [int]$Depth = 6)
    process { $Object | ConvertTo-Json -Depth $Depth }
}
