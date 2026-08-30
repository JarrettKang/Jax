[CmdletBinding()]
param(
    [string]$Device,
    [string]$WindowsDatabase = (Join-Path $env:APPDATA 'Jax\jax.db'),
    [string]$Package = 'com.example.jax',
    [string]$Baseline,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\.debug_snapshots')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { '<android-sdk>' }
$adb = Join-Path $androidHome 'platform-tools\adb.exe'
$dart = '<flutter-sdk>\bin\dart.bat'
$remoteDatabase = 'databases/jax.db'

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    $lines = if ([IO.Path]::GetExtension($File) -in @('.bat', '.cmd')) { & $env:ComSpec /d /c $File @Arguments } else { & $File @Arguments }
    $code = $LASTEXITCODE
    foreach ($line in $lines) { Write-Host $line }
    if ($code -ne 0) { throw "Command failed ($code): $File $($Arguments -join ' ')" }
}
function Get-AdbText([string[]]$Arguments) {
    $text = & $adb -s $script:serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ')`n$($text -join "`n")" }
    return ($text -join "`n").Trim()
}
function Export-AdbFile([string]$Remote, [string]$Destination) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $adb; $start.UseShellExecute = $false; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    foreach ($argument in @('-s', $script:serial, 'exec-out', 'run-as', $Package, 'cat', $Remote)) { [void]$start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $stream = [IO.File]::Create($Destination)
    try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Dispose() }
    $errorText = $process.StandardError.ReadToEnd(); $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Could not read $Remote`: $errorText" }
}
function Test-AndroidFile([string]$Remote) {
    & $adb -s $script:serial shell run-as $Package test -f $Remote
    return $LASTEXITCODE -eq 0
}
function Capture-Android([string]$Directory, [string]$Name) {
    $raw = Join-Path $Directory "$Name.raw.db"
    Export-AdbFile $remoteDatabase $raw
    foreach ($suffix in @('-wal', '-shm')) { if (Test-AndroidFile "$remoteDatabase$suffix") { Export-AdbFile "$remoteDatabase$suffix" "$raw$suffix" } }
    $safe = Join-Path $Directory "$Name.db"
    Invoke-Checked $dart @('run', 'tool/database_snapshot.dart', 'snapshot', $raw, $safe)
    return $safe
}
function Export-Snapshot([string]$Database, [string]$Json) { Invoke-Checked $dart @('run', 'tool/sync_phase2a.dart', 'export', $Database, $Json) }
function Fingerprint([string]$Json) {
    $result = & $env:ComSpec /d /c $dart run tool/sync_phase2a.dart fingerprint $Json
    if ($LASTEXITCODE -ne 0) { throw 'Could not fingerprint snapshot.' }
    return ($result -join "`n").Trim()
}

if (-not (Test-Path -LiteralPath $adb)) { throw "adb not found: $adb" }
if (-not (Test-Path -LiteralPath $WindowsDatabase)) { throw "Windows database not found: $WindowsDatabase" }
$devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '^([^\s]+)\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if ($Device) {
    if ($Device -notin $devices) { throw "Requested device is not connected: $Device" }
    $script:serial = $Device
} elseif ($devices.Count -eq 1) { $script:serial = $devices[0] }
elseif ($devices.Count -eq 0) { throw 'No authorized Android device is connected.' }
else { throw 'Multiple Android devices are connected. Rerun with -Device <serial>.' }

$packagePath = Get-AdbText @('shell', 'pm', 'path', $Package)
if (-not $packagePath.StartsWith('package:')) { throw "Package is not installed: $Package" }
[void](Get-AdbText @('shell', 'run-as', $Package, 'pwd'))
$runningPid = & $adb -s $script:serial shell pidof $Package 2>$null
$wasRunning = ($runningPid -join '').Trim() -ne ''
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$directory = Join-Path $OutputRoot "sync_phase2a_$timestamp"
New-Item -ItemType Directory -Path $directory -Force | Out-Null

try {
    & $adb -s $script:serial shell am force-stop $Package | Out-Null
    $windowsBefore = Join-Path $directory 'windows_before.db'
    Invoke-Checked $dart @('run', 'tool/database_snapshot.dart', 'snapshot', $WindowsDatabase, $windowsBefore)
    $androidBefore = Capture-Android $directory 'android_before'
    $windowsJson = Join-Path $directory 'windows.json'; $androidJson = Join-Path $directory 'android.json'
    Export-Snapshot $windowsBefore $windowsJson; Export-Snapshot $androidBefore $androidJson
    $plan = Join-Path $directory 'sync_plan.json'
    $compare = @('run', 'tool/sync_phase2a.dart', 'compare', $windowsJson, $androidJson, $plan)
    if ($Baseline) { $compare += $Baseline }
    Invoke-Checked $dart $compare

    $windowsAfter = Join-Path $directory 'windows_after.db'
    Invoke-Checked $dart @('run', 'tool/database_snapshot.dart', 'snapshot', $WindowsDatabase, $windowsAfter)
    $androidAfter = Capture-Android $directory 'android_after'
    $windowsAfterJson = Join-Path $directory 'windows_after.json'; $androidAfterJson = Join-Path $directory 'android_after.json'
    Export-Snapshot $windowsAfter $windowsAfterJson; Export-Snapshot $androidAfter $androidAfterJson
    if ((Fingerprint $windowsJson) -ne (Fingerprint $windowsAfterJson)) { throw 'Windows business facts changed during Analyze.' }
    if ((Fingerprint $androidJson) -ne (Fingerprint $androidAfterJson)) { throw 'Android business facts changed during Analyze.' }
    Write-Host 'READ_ONLY_VERIFIED Windows=unchanged Android=unchanged' -ForegroundColor Green
    Write-Host "Preview plan: $plan"
    Write-Host "Windows Debug UI: `$env:JAX_SYNC_PLAN='$plan'; .\build\windows\x64\runner\Debug\jax.exe"
} finally {
    if ($wasRunning) { & $adb -s $script:serial shell am start -n "$Package/.MainActivity" | Out-Null }
}
