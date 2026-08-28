[CmdletBinding()]
param(
    [string]$Device,
    [string]$SourceDatabase = (Join-Path $env:APPDATA 'Jax\jax.db'),
    [string]$Package = 'com.example.jax',
    [string]$BackupRoot = (Join-Path $PSScriptRoot '..\.debug_backups\android'),
    [switch]$SkipBuild,
    [switch]$RestoreLatest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expectedSchema = 11
$databaseRelativePath = 'databases/jax.db'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Invoke-Checked([string]$File, [string[]]$Arguments) {
    if ([IO.Path]::GetExtension($File) -in @('.bat', '.cmd')) {
        $commandOutput = & $env:ComSpec /d /c $File @Arguments
    } else {
        $commandOutput = & $File @Arguments
    }
    $commandExitCode = $LASTEXITCODE
    foreach ($line in $commandOutput) { Write-Host $line }
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
    foreach ($argument in @('-s', $script:deviceSerial, 'exec-out', 'run-as', $Package, 'cat', $RemoteRelativePath)) { [void]$start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $stream = [IO.File]::Create($Destination)
    try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Dispose() }
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue; throw "Could not back up $RemoteRelativePath`: $errorText" }
}
function Get-Tool([string]$Name, [string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "$Name was not found."
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
    if (-not (Test-AndroidFile $databaseRelativePath)) { Write-Host 'Android app has no existing database; no backup is required.'; return $null }
    $rawMain = Join-Path $Directory 'jax.db'
    Export-AdbFile $databaseRelativePath $rawMain
    foreach ($suffix in @('-wal', '-shm')) {
        $remote = "$databaseRelativePath$suffix"
        if (Test-AndroidFile $remote) { Export-AdbFile $remote (Join-Path $Directory "jax.db$suffix") }
    }
    $normalized = Join-Path $Directory 'jax_android_before_import.db'
    Invoke-Checked $script:dartPath @('run', 'tool/database_snapshot.dart', 'snapshot-any', $rawMain, $normalized)
    foreach ($file in @($rawMain, "$rawMain-wal", "$rawMain-shm")) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    Write-Host "Android backup: $normalized"
    return $normalized
}
function Assert-AndroidCurrentSchema {
    $temporary = Join-Path ([IO.Path]::GetTempPath()) "jax-android-schema-$([guid]::NewGuid().ToString('N')).db"
    try {
        Export-AdbFile $databaseRelativePath $temporary
        foreach ($suffix in @('-wal', '-shm')) {
            if (Test-AndroidFile "$databaseRelativePath$suffix") { Export-AdbFile "$databaseRelativePath$suffix" "$temporary$suffix" }
        }
        Invoke-Checked $script:dartPath @('run', 'tool/database_snapshot.dart', 'verify', $temporary)
    } finally {
        foreach ($file in @($temporary, "$temporary-wal", "$temporary-shm")) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    }
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

$androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { '<android-sdk>' }
$script:adbPath = Get-Tool 'adb' @((Join-Path $androidHome 'platform-tools\adb.exe'))
$script:dartPath = Get-Tool 'dart' @('<flutter-sdk>\bin\dart.bat')
$flutterPath = Get-Tool 'flutter' @('<flutter-sdk>\bin\flutter.bat')

$deviceLines = & $script:adbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }
$ready = @($deviceLines | Where-Object { $_ -match '^([^\s]+)\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
$unauthorized = @($deviceLines | Where-Object { $_ -match '\s+unauthorized$' })
if ($unauthorized.Count -gt 0) { throw 'An Android device is unauthorized. Accept the USB debugging prompt, then rerun.' }
if ($Device) {
    if ($ready -notcontains $Device) { throw "Requested device is not connected and authorized: $Device" }
    $script:deviceSerial = $Device
} elseif ($ready.Count -eq 0) { throw 'No authorized Android device is connected.'
} elseif ($ready.Count -gt 1) { throw 'Multiple Android devices are connected. Rerun with -Device <serial>.'
} else { $script:deviceSerial = $ready[0] }

Push-Location $projectRoot
$snapshot = $null
try {
    Write-Step "Target device: $script:deviceSerial"
    if (-not $SkipBuild -and -not $RestoreLatest) {
        Write-Step 'Building and updating the current Android Debug APK'
        Invoke-Checked $flutterPath @('build', 'apk', '--debug')
        Invoke-Adb @('install', '-r', (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-debug.apk'))
    }
    Assert-SafePackage
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    if (-not $RestoreLatest) {
        if (-not (Test-Path -LiteralPath $SourceDatabase)) { throw "Windows source database does not exist: $SourceDatabase" }
        $snapshotDirectory = Join-Path $projectRoot '.debug_snapshots'
        New-Item -ItemType Directory -Path $snapshotDirectory -Force | Out-Null
        $snapshot = Join-Path $snapshotDirectory "jax_windows_$timestamp.db"
        Write-Step 'Creating a transaction-consistent Windows snapshot'
        Invoke-Checked $script:dartPath @('run', 'tool/database_snapshot.dart', 'snapshot', $SourceDatabase, $snapshot)
    }
    $backupDirectory = Join-Path $BackupRoot $timestamp
    Write-Step 'Stopping Android Debug app and backing up its database'
    Invoke-Adb @('shell', 'am', 'force-stop', $Package)
    $backup = New-AndroidBackup $backupDirectory
    Write-Step 'Starting the current Debug app once to apply its normal schema migrations'
    Invoke-Adb @('shell', 'monkey', '-p', $Package, '-c', 'android.intent.category.LAUNCHER', '1')
    Start-Sleep -Seconds 2
    Invoke-Adb @('shell', 'am', 'force-stop', $Package)
    Assert-AndroidCurrentSchema

    if ($RestoreLatest) {
        $restore = Get-ChildItem -LiteralPath $BackupRoot -Filter 'jax_android_before_import.db' -File -Recurse |
            Where-Object { $_.DirectoryName -ne $backupDirectory } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $restore) { throw "No Android backup found under $BackupRoot" }
        Write-Step "Restoring Android backup: $($restore.FullName)"
        Install-Database $restore.FullName -AllowAnySchema
    } else {
        Write-Host "Source: $SourceDatabase"
        Write-Host "Destination: $script:deviceSerial / $Package / $databaseRelativePath"
        Write-Step 'Installing verified snapshot into Android Debug sandbox'
        Install-Database $snapshot
    }
    Write-Step 'Launching Android Jax'
    Invoke-Adb @('shell', 'monkey', '-p', $Package, '-c', 'android.intent.category.LAUNCHER', '1')
    Write-Host '数据已复制到 Android。'
    Write-Host '这不是双向同步；此后 Windows 和 Android 的新记录不会自动合并。'
    if ($backup) { Write-Host "导入前备份保存在：$backup" }
} finally {
    if ($snapshot -and (Test-Path -LiteralPath $snapshot)) { Remove-Item -LiteralPath $snapshot -Force }
    Pop-Location
}
