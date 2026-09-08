# NO_AUTO_UNINSTALL_REAL_DATA: one install -r attempt; never uninstall/clear/retry.
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Device,
    [Parameter(Mandatory)][string]$ApkPath,
    [Parameter(Mandatory)][string]$AdbPath,
    [Parameter(Mandatory)][string]$AaptPath,
    [ValidateSet('com.example.jax', 'com.example.jax.worldfixture')]
    [string]$Package = 'com.example.jax'
)
$ErrorActionPreference = 'Stop'
$rule = 'NO_AUTO_UNINSTALL_REAL_DATA'
foreach ($path in @($ApkPath, $AdbPath, $AaptPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$rule : Missing file $path" }
}
$badging = @(& $AaptPath dump badging $ApkPath 2>&1)
if ($LASTEXITCODE -ne 0) { throw "$rule : Cannot inspect APK: $badging" }
$packageLine = $badging | Where-Object { "$_" -match "^package: name='([^']+)'" } | Select-Object -First 1
if (-not $packageLine -or "$packageLine" -notmatch "^package: name='([^']+)'" -or $Matches[1] -ne $Package) {
    throw "$rule : APK package does not match $Package"
}
if (-not ($badging | Where-Object { "$_" -match '^application-debuggable' })) {
    throw "$rule : Only a debuggable APK is allowed"
}
$state = @(& $AdbPath -s $Device get-state 2>&1)
if ($LASTEXITCODE -ne 0 -or ($state -join '').Trim() -ne 'device') { throw "$rule : Device not ready: $state" }
$installed = @(& $AdbPath -s $Device shell pm list packages $Package 2>&1)
if ($LASTEXITCODE -ne 0) { throw "$rule : Cannot inspect installed package: $installed" }
if ($Package -eq 'com.example.jax' -and -not ($installed | Where-Object { "$_".Trim() -eq "package:$Package" })) {
    throw "$rule : Real-data package missing. Stop and investigate; this command only updates an existing Jax install."
}
$hash = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash
Write-Output "$rule : package=$Package device=$Device SHA256=$hash"
if ($PSCmdlet.ShouldProcess("$Device / $Package", 'Update with exactly one adb install -r')) {
    $result = @(& $AdbPath -s $Device install -r $ApkPath 2>&1)
    $code = $LASTEXITCODE
    $result | Write-Output
    if ($code -ne 0 -or -not ($result | Where-Object { "$_".Trim() -eq 'Success' })) {
        throw "$rule : Install failed. STOP. No retry or uninstall is permitted. Preserve app data and report the failure."
    }
}
