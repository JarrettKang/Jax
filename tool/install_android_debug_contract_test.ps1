$ErrorActionPreference = 'Stop'
$temp = Join-Path $env:TEMP ('jax-install-contract-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$adb = Join-Path $temp 'adb.ps1'
$aapt = Join-Path $temp 'aapt.ps1'
$apk = Join-Path $temp 'fixture.apk'
Set-Content -LiteralPath $apk -Value 'mock APK'
Set-Content -LiteralPath $aapt -Value @'
Write-Output "package: name='$env:JAX_TEST_PACKAGE' versionCode='1'"
Write-Output 'application-debuggable'
$global:LASTEXITCODE = 0
'@
Set-Content -LiteralPath $adb -Value @'
Add-Content -LiteralPath $env:JAX_TEST_LOG -Value ($args -join ' ')
$global:LASTEXITCODE = 0
if ($args[2] -eq 'get-state') { Write-Output 'device' }
elseif ($args[2] -eq 'shell') {
    if ($env:JAX_TEST_EXISTS -eq 'yes') { Write-Output "package:$env:JAX_TEST_PACKAGE" }
} elseif ($args[2] -eq 'install') {
    if ($env:JAX_TEST_FAIL -eq 'yes') { Write-Output 'Failure [INSTALL_FAILED_USER_RESTRICTED]'; $global:LASTEXITCODE = 1 }
    else { Write-Output 'Success' }
} else { throw 'Unexpected adb operation' }
'@
$installer = Join-Path $PSScriptRoot 'install_android_debug.ps1'
$case = 0
foreach ($scenario in @(
    @('com.example.jax', 'yes', 'no', 'com.example.jax', $false, 1),
    @('com.example.jax', 'yes', 'yes', 'com.example.jax', $true, 1),
    @('com.example.jax', 'no', 'no', 'com.example.jax', $true, 0),
    @('com.example.jax.worldfixture', 'yes', 'no', 'com.example.jax', $true, 0),
    @('com.example.jax.worldfixture', 'no', 'no', 'com.example.jax.worldfixture', $false, 1)
)) {
    $case++
    $env:JAX_TEST_PACKAGE = $scenario[0]
    $env:JAX_TEST_EXISTS = $scenario[1]
    $env:JAX_TEST_FAIL = $scenario[2]
    $env:JAX_TEST_LOG = Join-Path $temp "$case.log"
    $failed = $false
    try { & $installer -Device test-device -ApkPath $apk -AdbPath $adb -AaptPath $aapt -Package $scenario[3] | Out-Null }
    catch { $failed = $true; if ("$_" -notmatch 'NO_AUTO_UNINSTALL_REAL_DATA') { throw } }
    if ($failed -ne $scenario[4]) { throw "Case $case unexpected failure=$failed" }
    $calls = if (Test-Path -LiteralPath $env:JAX_TEST_LOG) { @(Get-Content -LiteralPath $env:JAX_TEST_LOG) } else { @() }
    if (@($calls | Where-Object { $_ -match ' install -r ' }).Count -ne $scenario[5]) { throw "Case $case incorrect install count" }
    if ($calls | Where-Object { $_ -match 'uninstall|\bclear\b' }) { throw "Case $case destructive command" }
}
Write-Output "PASS: $case installer safety scenarios. Mock evidence: $temp"
