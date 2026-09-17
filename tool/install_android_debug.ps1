# NO_AUTO_UNINSTALL_REAL_DATA: one install -r attempt; never uninstall/clear/retry.
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Device,
    [string]$ApkPath,
    [string]$AdbPath,
    [string]$AaptPath,
    [ValidateSet('com.example.jax', 'com.example.jax.worldfixture')]
    [string]$Package,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'
if ($Help) { Write-Output 'Safe Debug update only. -Device -ApkPath -Package required; -AdbPath/-AaptPath or JAX_ADB_PATH/JAX_AAPT2_PATH/PATH. Supports -WhatIf. One install -r; failure stops. No uninstall or clear. See docs/TOOLS.md.'; return }
$rule = 'NO_AUTO_UNINSTALL_REAL_DATA'
. (Join-Path $PSScriptRoot 'tool_locator.ps1')
trap { Write-Verbose ($_ | Out-String); throw (Protect-JaxLog $_.Exception.Message) }
if (-not $Device -or -not $ApkPath -or -not $Package) { throw "$rule : explicit Device, ApkPath and Package required." }
$AdbPath = Resolve-JaxTool adb $AdbPath
$AaptPath = Resolve-JaxTool aapt2 $AaptPath
foreach ($path in @($ApkPath, $AdbPath, $AaptPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$rule : Required input file missing." }
}
$badging = @(& $AaptPath dump badging $ApkPath 2>&1)
if ($LASTEXITCODE -ne 0) { throw "$rule : Cannot inspect APK." }
$packageLine = $badging | Where-Object { "$_" -match "^package: name='([^']+)'" } | Select-Object -First 1
if (-not $packageLine -or "$packageLine" -notmatch "^package: name='([^']+)'" -or $Matches[1] -ne $Package) {
    throw "$rule : APK package does not match $Package"
}
if (-not ($badging | Where-Object { "$_" -match '^application-debuggable' })) {
    throw "$rule : Only a debuggable APK is allowed"
}
$state = @(& $AdbPath -s $Device get-state 2>&1)
if ($LASTEXITCODE -ne 0 -or ($state -join '').Trim() -ne 'device') { throw "$rule : Device not ready." }
$installed = @(& $AdbPath -s $Device shell pm list packages $Package 2>&1)
if ($LASTEXITCODE -ne 0) { throw "$rule : Cannot inspect installed package." }
if ($Package -eq 'com.example.jax' -and -not ($installed | Where-Object { "$_".Trim() -eq "package:$Package" })) {
    throw "$rule : Real-data package missing. Stop and investigate; this command only updates an existing Jax install."
}
$hash = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash
Write-Output "$rule : package=$Package device=<selected-device> APK hash=$($hash.Substring(0,8))..."
Write-Verbose "device=$Device APK=$ApkPath SHA256=$hash"
if ($PSCmdlet.ShouldProcess("<selected-device> / $Package", 'Update with exactly one adb install -r')) {
    $result = @(& $AdbPath -s $Device install -r $ApkPath 2>&1)
    $code = $LASTEXITCODE
    $result | ForEach-Object { Write-Verbose $_ }
    if ($code -ne 0 -or -not ($result | Where-Object { "$_".Trim() -eq 'Success' })) {
        throw "$rule : Install failed. STOP. No retry or uninstall is permitted. Preserve app data and report the failure."
    }
}
