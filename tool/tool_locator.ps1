# Dot-source only. Explicit settings fail closed; never fall back from a typo.
function Resolve-JaxTool {
    param([ValidateSet('dart','flutter','adb','aapt2')][string]$Name, [string]$ExplicitPath)
    $envName = 'JAX_' + $Name.ToUpperInvariant() + '_PATH'
    $configured = if ($ExplicitPath) { $ExplicitPath } else { [Environment]::GetEnvironmentVariable($envName) }
    if ($configured) {
        if (-not (Test-Path -LiteralPath $configured -PathType Leaf)) { throw "$Name configured path is invalid. Check -${Name}Path or $envName." }
        return (Resolve-Path -LiteralPath $configured).Path
    }
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $candidates = @()
    if ($Name -in @('dart','flutter')) {
        if ($env:FLUTTER_ROOT) { $candidates += Join-Path $env:FLUTTER_ROOT "bin\$Name.bat" }
        if ($Name -eq 'dart') {
            $flutter = Get-Command flutter -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($flutter) { $candidates += Join-Path (Split-Path $flutter.Source) 'dart.bat' }
            if ($env:JAX_FLUTTER_PATH) { $candidates += Join-Path (Split-Path $env:JAX_FLUTTER_PATH) 'dart.bat' }
        }
    }
    if ($Name -eq 'adb') {
        foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)) {
            if ($root) { $candidates += Join-Path $root 'platform-tools\adb.exe' }
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    throw "$Name not found. Checked explicit parameter, $envName, PATH and SDK environment. Provide -${Name}Path; or set FLUTTER_ROOT / ANDROID_HOME / ANDROID_SDK_ROOT as applicable."
}

function Protect-JaxLog([string]$Text) {
    $Text = $Text -replace '(?i)\b[0-9a-f]{64}\b','<fingerprint>'
    $Text = $Text -replace '(?i)[A-Z]:[\\/][^\r\n]*','<local-path>'
    foreach ($name in @('serial','deviceSerial','Device')) {
        $value = Get-Variable -Name $name -ValueOnly -ErrorAction SilentlyContinue
        if ($value -is [string] -and $value) { $Text = $Text.Replace($value, '<device>') }
    }
    return $Text
}

function Assert-JaxPackage([string]$Package) {
    if ($Package -notin @('com.example.jax','com.example.jax.worldfixture')) { throw 'Only the explicitly selected Jax Debug package is allowed.' }
}

function Select-JaxDevice([string]$Adb, [string]$Device) {
    $lines = @(& $Adb devices 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'ADB device discovery failed.' }
    $devices = @($lines | Select-Object -Skip 1 | Where-Object { "$_" -match '^\S+\s+(device|offline|unauthorized)(\s|$)' })
    if (-not $Device -and $devices.Count -gt 1) { throw 'Multiple Android devices are connected. Specify -Device.' }
    if (-not $Device -and $devices.Count -eq 1) { $Device = ("$($devices[0])" -split '\s+')[0] }
    if (-not $Device) { throw 'No Android device is connected.' }
    if ($Device -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Invalid device identifier.' }
    if (-not ($devices | Where-Object { "$_" -match ('^' + [regex]::Escape($Device) + '\s+device(\s|$)') })) { throw 'Selected Android device is missing, offline or unauthorized.' }
    return $Device
}

function Assert-JaxDebugDevice([string]$Adb, [string]$Device, [string]$Package) {
    Assert-JaxPackage $Package
    $packages = @(& $Adb -s $Device shell pm list packages $Package 2>&1)
    if ($LASTEXITCODE -ne 0 -or "package:$Package" -notin $packages) { throw 'Package is not installed: expected Jax identity.' }
    $access = @(& $Adb -s $Device shell run-as $Package pwd 2>&1)
    if ($LASTEXITCODE -ne 0 -or (($access -join '').Trim() -notmatch ('^/data/(user/\d+|data)/' + [regex]::Escape($Package) + '$'))) { throw 'Package is not debuggable with run-as.' }
}

function Assert-JaxPrivateOutput([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if ($full.StartsWith($repo + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $relative = $full.Substring($repo.Length + 1)
        if ($relative -notmatch '^\.(local_private|debug_backups|debug_snapshots)[\\/]') { throw 'Runtime output inside the repository must use a private runtime directory.' }
    }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Private output must not traverse a link or junction.' }
        }
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}
