Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CwinNativeLoaded = $false

function Initialize-CwinNative {
    if ($script:CwinNativeLoaded -or ('Cwin.Native' -as [type])) {
        $script:CwinNativeLoaded = $true
        return
    }
    # System.Drawing.Common is required for Bitmap/Graphics on .NET Core/5+.
    try { Add-Type -AssemblyName 'System.Drawing.Common' -ErrorAction Stop } catch { }
    # On .NET 9+ Graphics types live in private satellite assemblies.
    try { Add-Type -AssemblyName 'System.Private.Windows.GdiPlus' -ErrorAction Stop } catch { }
    try { Add-Type -AssemblyName 'System.Private.Windows.Core' -ErrorAction Stop } catch { }
    # UIAutomation* expose AutomationElement etc.; WindowsBase carries System.Windows.Point.
    try { Add-Type -AssemblyName 'UIAutomationClient' -ErrorAction Stop } catch { }
    try { Add-Type -AssemblyName 'UIAutomationTypes' -ErrorAction Stop } catch { }
    try { Add-Type -AssemblyName 'WindowsBase' -ErrorAction Stop } catch { }
    $cs = Join-Path $PSScriptRoot 'Cwin.Native.cs'
    if (-not (Test-Path -LiteralPath $cs)) {
        Write-CwinError "Cwin.Native.cs not found at $cs" -ExitCode $script:CwinExit.PinvokeFail
    }
    # Build the -ReferencedAssemblies list. For assemblies that may live in a
    # different runtime directory than the default one Roslyn searches (notably
    # the WindowsDesktop satellite assemblies: UIAutomation*, WindowsBase), pass
    # the resolved .Location so the compile finds them deterministically.
    $refs = [System.Collections.Generic.List[string]]::new()
    foreach ($n in @('System.Drawing.Common','System.Drawing.Primitives','System.Runtime','System.Runtime.InteropServices','System.Collections','System.Memory','System.ObjectModel')) {
        [void]$refs.Add($n)
    }
    $pathByName = @{}
    foreach ($asm in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
        $n = $asm.GetName().Name
        if ($asm.Location) { $pathByName[$n] = $asm.Location }
        if ($n -like 'System.Private.Windows.*' -and -not $refs.Contains($n)) {
            [void]$refs.Add($n)
        }
    }
    foreach ($n in @('UIAutomationClient','UIAutomationTypes','WindowsBase')) {
        if ($pathByName.ContainsKey($n)) {
            [void]$refs.Add($pathByName[$n])
        } else {
            [void]$refs.Add($n)
        }
    }
    try {
        Add-Type -Path $cs -ReferencedAssemblies $refs.ToArray()
    } catch {
        Write-CwinError "Failed to compile Cwin.Native.cs: $($_.Exception.Message)" -ExitCode $script:CwinExit.PinvokeFail
    }
    # Force static ctor (which sets DPI awareness) by touching the type.
    [void][Cwin.Native]::GetSystemMetrics(0)
    $script:CwinNativeLoaded = $true
}

function ConvertTo-CwinWindowObject {
    param([Parameter(Mandatory)]$Descriptor)
    [pscustomobject][ordered]@{
        Hwnd        = [int64]$Descriptor.Hwnd.ToInt64()
        Pid         = [int]$Descriptor.Pid
        Title       = [string]$Descriptor.Title
        ClassName   = [string]$Descriptor.ClassName
        X           = [int]$Descriptor.X
        Y           = [int]$Descriptor.Y
        Width       = [int]$Descriptor.Width
        Height      = [int]$Descriptor.Height
        IsMinimized = [bool]$Descriptor.IsMinimized
        IsCloaked   = [bool]$Descriptor.IsCloaked
        IsVisible   = [bool]$Descriptor.IsVisible
    }
}

function Get-CwinWindows {
    [CmdletBinding()]
    param([switch]$IncludeHidden)
    Initialize-CwinNative
    $arr = [Cwin.Window]::EnumerateTopLevel([bool]$IncludeHidden)
    foreach ($d in $arr) { ConvertTo-CwinWindowObject -Descriptor $d }
}

function Resolve-CwinSelector {
    <#
      Resolve a single window from one of: -HwndHex/-HwndDec, -Title, -Pid, -Class.
      Returns the matching pscustomobject (with .Hwnd as int64). Exits with appropriate
      code on no-match or ambiguous match.
    #>
    [CmdletBinding()]
    param(
        $Hwnd,
        [string]$Title,
        $ProcessId,
        [string]$Class
    )
    Initialize-CwinNative

    $providers = @()
    if ($null -ne $Hwnd)      { $providers += 'hwnd' }
    if ($Title)               { $providers += 'title' }
    if ($null -ne $ProcessId) { $providers += 'pid' }
    if ($Class)               { $providers += 'class' }

    if ($providers.Count -eq 0) {
        Write-CwinError "specify one of --hwnd, --title, --pid, --class" -ExitCode $script:CwinExit.UsageError
    }
    if ($providers.Count -gt 1) {
        Write-CwinError "specify only one selector at a time (got: $($providers -join ', '))" -ExitCode $script:CwinExit.UsageError
    }

    if ($null -ne $Hwnd) {
        $h = [intptr][int64]$Hwnd
        if (-not [Cwin.Native]::IsWindow($h)) {
            Write-CwinError "no window with hwnd 0x$('{0:X}' -f [int64]$Hwnd)" -ExitCode $script:CwinExit.NotFound
        }
        $info = [Cwin.Window]::GetInfo($h)
        return ConvertTo-CwinWindowObject -Descriptor $info
    }

    $all = Get-CwinWindows
    $matches = @()

    if ($Title) {
        $rawNeedle = $Title
        $mode = 'substr'
        $needle = $rawNeedle
        if ($rawNeedle.StartsWith('^')) { $mode = 'regex'; $needle = $rawNeedle.Substring(1) }
        elseif ($rawNeedle.StartsWith('=')) { $mode = 'exact'; $needle = $rawNeedle.Substring(1) }
        switch ($mode) {
            'regex'  { $matches = @($all | Where-Object { $_.Title -match $needle }) }
            'exact'  { $matches = @($all | Where-Object { $_.Title -eq $needle }) }
            default  { $matches = @($all | Where-Object { $_.Title -and ($_.Title.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) }) }
        }
    } elseif ($null -ne $ProcessId) {
        $pidNum = [int]$ProcessId
        $matches = @($all | Where-Object { $_.Pid -eq $pidNum })
    } elseif ($Class) {
        $needle = $Class
        $mode = 'substr'
        if ($needle.StartsWith('^')) { $mode = 'regex'; $needle = $needle.Substring(1) }
        elseif ($needle.StartsWith('=')) { $mode = 'exact'; $needle = $needle.Substring(1) }
        switch ($mode) {
            'regex'  { $matches = @($all | Where-Object { $_.ClassName -match $needle }) }
            'exact'  { $matches = @($all | Where-Object { $_.ClassName -eq $needle }) }
            default  { $matches = @($all | Where-Object { $_.ClassName -and ($_.ClassName.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) }) }
        }
    }

    if ($matches.Count -eq 0) {
        Write-CwinError "no window matched selector" -ExitCode $script:CwinExit.NotFound
    }
    if ($matches.Count -gt 1) {
        $brief = ($matches | Select-Object -First 5 | ForEach-Object { "0x$('{0:X}' -f $_.Hwnd) [$($_.ClassName)] '$($_.Title)'" }) -join "; "
        if ($matches.Count -gt 5) { $brief += "; ... ($($matches.Count) total)" }
        Write-CwinError "selector matched $($matches.Count) windows: $brief. Narrow with --hwnd, --class, --pid, or '^regex'/'=exact'." -ExitCode $script:CwinExit.Ambiguous
    }
    return $matches[0]
}

function ConvertTo-CwinHandle { param([int64]$Hwnd); return [intptr][int64]$Hwnd }

function Set-CwinForeground {
    <#
      Bring a window to the foreground using the AttachThreadInput trick to
      bypass Windows foreground-lock heuristics. Returns $true on success.
    #>
    param([Parameter(Mandatory)][int64]$Hwnd)
    Initialize-CwinNative
    $h = [intptr][int64]$Hwnd
    $currentTid = [Cwin.Native]::GetCurrentThreadId()
    $dummy = 0
    $targetTid = [Cwin.Native]::GetWindowThreadProcessId($h, [ref]$dummy)
    if ($targetTid -eq $currentTid) {
        return [Cwin.Native]::SetForegroundWindow($h)
    }
    [void][Cwin.Native]::AttachThreadInput($currentTid, $targetTid, $true)
    try {
        # Restore from minimized state without activating, then bring to front.
        if ([Cwin.Native]::IsIconic($h)) {
            [void][Cwin.Native]::ShowWindow($h, [Cwin.Native]::SW_RESTORE)
        }
        return [Cwin.Native]::SetForegroundWindow($h)
    } finally {
        [void][Cwin.Native]::AttachThreadInput($currentTid, $targetTid, $false)
    }
}

function Test-CwinIsXamlClass {
    <#
      Returns $true for window classes that ignore PostMessage clicks and posted
      WM_CHAR (DESIGN.md §5.6). These are the cases where --method auto should
      pick UIA instead of post. Microsoft.UI.* covers WinAppSDK / WinUI 3 hosts.
    #>
    param([string]$ClassName)
    if (-not $ClassName) { return $false }
    return ($ClassName -eq 'ApplicationFrameWindow') -or `
           ($ClassName -eq 'Windows.UI.Core.CoreWindow') -or `
           ($ClassName.StartsWith('Microsoft.UI.Content.', [StringComparison]::Ordinal)) -or `
           ($ClassName.StartsWith('Microsoft.UI.Composition.', [StringComparison]::Ordinal))
}

function Test-CwinUacMismatch {
    <#
      Returns the target's integrity level if it is higher than the caller's; otherwise $null.
      Used to warn that PostMessage will silently fail due to UIPI.
    #>
    param([Parameter(Mandatory)][int]$TargetPid)
    Initialize-CwinNative
    $rank = @{ 'low' = 0; 'medium' = 1; 'high' = 2; 'system' = 3; 'unknown' = -1 }
    $self = [Cwin.Token]::GetIntegrityLevel([int][System.Diagnostics.Process]::GetCurrentProcess().Id)
    $them = [Cwin.Token]::GetIntegrityLevel($TargetPid)
    if (-not $rank.ContainsKey($self) -or -not $rank.ContainsKey($them)) { return $null }
    if ($rank[$them] -gt $rank[$self]) { return $them }
    return $null
}
