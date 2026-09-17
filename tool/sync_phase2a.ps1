[CmdletBinding()]
param(
    [string]$Device,
    [string]$WindowsDatabase = (Join-Path $env:APPDATA 'Jax\jax.db'),
    [string]$Package,
    [string]$AdbPath,
    [string]$DartPath,
    [switch]$Help,
    [string]$Baseline,
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\.local_private\sync-exports')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Help) { Write-Output 'Read-only developer Debug comparison: stops apps and creates private snapshots; no business writes or apply mode. Example: ./tool/sync_phase2a.ps1 -Package com.example.jax -Device <serial> -WindowsDatabase <db>. WindowsDatabase defaults to APPDATA/Jax/jax.db; OutputRoot defaults to .local_private/sync-exports. Optional -Baseline, -OutputRoot, -AdbPath, -DartPath, -Verbose (private diagnostics). Multiple devices require -Device. See docs/TOOLS.md.'; return }
. (Join-Path $PSScriptRoot 'tool_locator.ps1')
trap { Write-Verbose ($_ | Out-String); throw (Protect-JaxLog $_.Exception.Message) }
Assert-JaxPackage $Package
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$adb = Resolve-JaxTool adb $AdbPath
$dart = Resolve-JaxTool dart $DartPath
$remoteDatabase = 'databases/jax.db'

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    $lines = if ([IO.Path]::GetExtension($File) -in @('.bat', '.cmd')) { & $env:ComSpec /d /c $File @Arguments } else { & $File @Arguments }
    $code = $LASTEXITCODE
    foreach ($line in $lines) { Write-Verbose $line }
    if ($code -ne 0) { throw "Command failed ($code). Use -Verbose privately." }
}
function Get-AdbText([string[]]$Arguments) {
    $text = & $adb -s $script:serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'ADB operation failed.' }
    return ($text -join "`n").Trim()
}
function Export-AdbFile([string]$Remote, [string]$Destination) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $adb; $start.UseShellExecute = $false; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.Arguments = "-s $($script:serial) exec-out run-as $Package cat $Remote"
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
    $result = & $env:ComSpec /d /c $dart run tool/sync_phase2a.dart fingerprint $Json --machine-private
    if ($LASTEXITCODE -ne 0) { throw 'Could not fingerprint snapshot.' }
    return ($result -join "`n").Trim()
}

if (-not (Test-Path -LiteralPath $adb)) { throw "adb not found: $adb" }
if (-not (Test-Path -LiteralPath $WindowsDatabase)) { throw "Windows database not found: $WindowsDatabase" }
$script:serial = Select-JaxDevice $adb $Device
Assert-JaxDebugDevice $adb $script:serial $Package
$packagePath = Get-AdbText @('shell', 'pm', 'path', $Package)
if (-not $packagePath.StartsWith('package:')) { throw "Package is not installed: $Package" }
[void](Get-AdbText @('shell', 'run-as', $Package, 'pwd'))
$runningPid = & $adb -s $script:serial shell pidof $Package 2>$null
$wasRunning = ($runningPid -join '').Trim() -ne ''
Assert-JaxPrivateOutput $OutputRoot
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$directory = Join-Path $OutputRoot "sync_phase2a_$timestamp"
New-Item -ItemType Directory -Path $directory -Force | Out-Null

$safeToRestart = $false
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
    $safeToRestart = $true
    Write-Host 'READ_ONLY_VERIFIED Windows=unchanged Android=unchanged' -ForegroundColor Green
    Write-Host 'Preview plan written privately.'
    Write-Verbose 'Use Debug Sync UI or private plan.'
} finally {
    if ($wasRunning -and $safeToRestart) { & $adb -s $script:serial shell am start -n "$Package/.MainActivity" | Out-Null }
}
