<#
.SYNOPSIS
WARNING: destructive ONE-WAY developer copy, not Sync.
.DESCRIPTION
Default dry-run. Requires explicit source, device and -Apply -ConfirmOverwrite.
Source and target backups are verified before overwrite; round-trip verification and rollback follow.
No build, install, migration, uninstall or clear. See docs/TOOLS.md.
.EXAMPLE
./tool/copy_windows_data_to_android.ps1 -SourceDatabase <db> -Device <serial> -Package com.jarrett.jax
#>
[CmdletBinding()]
param(
 [string]$Device, [string]$SourceDatabase, [string]$Package = 'com.jarrett.jax',
 [string]$BackupRoot = (Join-Path $PSScriptRoot '..\.local_private\backups\android-copy'),
 [string]$AdbPath, [string]$DartPath,
 [switch]$Apply, [switch]$ConfirmOverwrite, [switch]$Help
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Help) { Get-Help $PSCommandPath -Detailed; return }
. (Join-Path $PSScriptRoot 'tool_locator.ps1')
trap { Write-Verbose ($_ | Out-String); throw (Protect-JaxLog $_.Exception.Message) }
if (-not $SourceDatabase -or -not $Device -or -not $Package) { throw 'Explicit -SourceDatabase and -Device required; Package must be valid. Multiple Android devices are connected only by explicit serial.' }
Assert-JaxPackage $Package
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$databaseRelativePath = 'databases/jax.db'
$script:adbPath = Resolve-JaxTool adb $AdbPath
$script:dartPath = Resolve-JaxTool dart $DartPath
$script:deviceSerial = Select-JaxDevice $script:adbPath $Device
Assert-JaxDebugDevice $script:adbPath $script:deviceSerial $Package
Assert-JaxPrivateOutput $BackupRoot
Write-Host "WARNING: destructive one-way overwrite, NOT Sync.`nPLAN: replace database`nTARGET: <selected-device> / $Package / <explicit-source>`nCHANGES: overwrite Android database`nSAFETY CHECKS: Debug identity, current schema, verified backup, round-trip"
Write-Verbose "Source=$SourceDatabase Device=$Device Package=$Package"
if (-not $Apply -or -not $ConfirmOverwrite) { Write-Host 'DRY_RUN: no device writes. Both -Apply -ConfirmOverwrite required.'; return }
function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Invoke-Checked([string]$File, [string[]]$Arguments) {
    if ([IO.Path]::GetExtension($File) -in @('.bat', '.cmd')) {
        $commandOutput = & $env:ComSpec /d /c $File @Arguments
    } else {
        $commandOutput = & $File @Arguments
    }
    $commandExitCode = $LASTEXITCODE
    foreach ($line in $commandOutput) { Write-Verbose $line }
    if ($commandExitCode -ne 0) { throw "Command failed ($commandExitCode): $File $($Arguments -join ' ')" }
}
function Invoke-Adb([string[]]$Arguments) { Invoke-Checked $script:adbPath (@('-s', $script:deviceSerial) + $Arguments) }
function Get-AdbText([string[]]$Arguments) {
    $text = & $script:adbPath @('-s', $script:deviceSerial) @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ')`n$($text -join "`n")" }
    return ($text -join "`n").Trim()
}
function Export-AdbFile([string]$RemoteRelativePath, [string]$Destination) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $script:adbPath
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Arguments = "-s $($script:deviceSerial) exec-out run-as $Package cat $RemoteRelativePath"
    $process = [Diagnostics.Process]::Start($start)
    $stream = [IO.File]::Create($Destination)
    try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Dispose() }
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue; throw "Could not back up $RemoteRelativePath`: $errorText" }
}
function Assert-SafePackage {
    $path = Get-AdbText @('shell', 'pm', 'path', $Package)
    if (-not $path.StartsWith('package:')) { throw "Debug package is not installed: $Package" }
    $runAs = Get-AdbText @('shell', 'run-as', $Package, 'pwd')
    if (-not $runAs.EndsWith($Package)) { throw "Package is not debuggable with run-as: $Package" }
}
function Test-AndroidFile([string]$RelativePath) {
    & $script:adbPath @('-s', $script:deviceSerial, 'shell', 'run-as', $Package, 'test', '-f', $RelativePath)
    return $LASTEXITCODE -eq 0
}
function New-AndroidBackup([string]$Directory) {
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    if (-not (Test-AndroidFile $databaseRelativePath)) { throw 'Existing target database required for verified backup.' }
    $rawMain = Join-Path $Directory 'jax.db'
    Export-AdbFile $databaseRelativePath $rawMain
    foreach ($suffix in @('-wal', '-shm')) {
        $remote = "$databaseRelativePath$suffix"
        if (Test-AndroidFile $remote) { Export-AdbFile $remote (Join-Path $Directory "jax.db$suffix") }
    }
    $normalized = Join-Path $Directory 'jax_android_before_import.db'
    Invoke-Checked $script:dartPath @('run', 'tool/database_snapshot.dart', 'snapshot', $rawMain, $normalized)
    foreach ($file in @($rawMain, "$rawMain-wal", "$rawMain-shm")) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    Write-Host 'Android backup verified privately.'
    return $normalized
}
function Install-Database([string]$Database, [switch]$AllowAnySchema) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $remote = "/data/local/tmp/jax-import-$stamp.db"
    Invoke-Adb @('push', $Database, $remote)
    try {
        Invoke-Adb @('shell', 'am', 'force-stop', $Package)
        Invoke-Adb @('shell', "cat '$remote' | run-as $Package sh -c 'cat > $databaseRelativePath.import'")
        Invoke-Adb @('shell', 'run-as', $Package, 'rm', '-f', "$databaseRelativePath-wal", "$databaseRelativePath-shm")
        Invoke-Adb @('shell', 'run-as', $Package, 'mv', "$databaseRelativePath.import", $databaseRelativePath)
        Invoke-Adb @('shell', 'run-as', $Package, 'chmod', '600', $databaseRelativePath)
        $roundTrip = Join-Path ([IO.Path]::GetTempPath()) "jax-roundtrip-$stamp.db"
        try {
            Export-AdbFile $databaseRelativePath $roundTrip
            $verifyMode = if ($AllowAnySchema) { 'verify-any' } else { 'verify' }
            Invoke-Checked $script:dartPath @('run', 'tool/database_snapshot.dart', $verifyMode, $roundTrip)
            if ((Get-FileHash $Database).Hash -ne (Get-FileHash $roundTrip).Hash) { throw 'Imported Android database differs from the verified snapshot.' }
        } finally { Remove-Item -LiteralPath $roundTrip -Force -ErrorAction SilentlyContinue }
    } finally { Invoke-Adb @('shell', 'rm', '-f', $remote) }
}


Push-Location $projectRoot
$backup = $null
$overwriteStarted = $false
try {
 $session = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N')
 $directory = Join-Path $BackupRoot $session
 New-Item -ItemType Directory -Path $directory -ErrorAction Stop | Out-Null
 $snapshot = Join-Path $directory 'source.db'
 Invoke-Checked $script:dartPath @('run', 'tool/database_snapshot.dart', 'snapshot', $SourceDatabase, $snapshot)
 Invoke-Adb @('shell', 'am', 'force-stop', $Package)
 $backup = New-AndroidBackup $directory
 Invoke-Checked $script:dartPath @('run', 'tool/database_snapshot.dart', 'verify', $backup)
 $overwriteStarted = $true
 Install-Database $snapshot
 Write-Host 'COPY_COMPLETE: schema/integrity/FK/round-trip verified. Private backup retained; app remains stopped.'
} catch {
 if ($overwriteStarted -and $backup) {
  try { Install-Database $backup; Write-Host 'ROLLBACK_VERIFIED: app remains stopped.' }
  catch { throw 'CRITICAL_ROLLBACK_FAILURE: stop and preserve backup. No automatic retry.' }
 }
 throw 'COPY_FAILED: stopped; private backup retained if acquired. No destructive install fallback.'
} finally { Pop-Location }
