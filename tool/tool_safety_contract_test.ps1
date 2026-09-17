# Isolated executable tests. No real ADB, SDK, device or Jax database is used.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'tool_locator.ps1')
. (Join-Path $PSScriptRoot 'backup_retention.ps1')
$temp = Join-Path ([IO.Path]::GetTempPath()) ('jax-tool-safety-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
function Assert([bool]$Value, [string]$Message) { if (-not $Value) { throw $Message } }
$saved = @{}
foreach ($name in @('PATH','ANDROID_HOME','ANDROID_SDK_ROOT','FLUTTER_ROOT','JAX_ADB_PATH','JAX_DART_PATH','JAX_FLUTTER_PATH')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, $null) }
try {
    $bin = Join-Path $temp 'bin'; New-Item -ItemType Directory $bin | Out-Null
    $adb = Join-Path $bin 'adb.exe'; [IO.File]::WriteAllText($adb, 'mock')
    Assert ((Resolve-JaxTool adb $adb) -eq $adb) 'Explicit tool lookup failed'
    $env:PATH = $bin
    Assert ((Resolve-JaxTool adb) -eq $adb) 'PATH lookup failed'
    $env:PATH = ''
    $sdk = Join-Path $temp 'sdk'; New-Item -ItemType Directory (Join-Path $sdk 'platform-tools') | Out-Null
    Copy-Item -LiteralPath $adb -Destination (Join-Path $sdk 'platform-tools/adb.exe')
    foreach ($name in @('ANDROID_HOME','ANDROID_SDK_ROOT')) {
        [Environment]::SetEnvironmentVariable($name,$sdk)
        Assert ((Resolve-JaxTool adb) -eq (Join-Path $sdk 'platform-tools/adb.exe')) 'SDK lookup failed'
        [Environment]::SetEnvironmentVariable($name,$null)
    }
    $flutterRoot = Join-Path $temp 'flutter'; New-Item -ItemType Directory (Join-Path $flutterRoot 'bin') | Out-Null
    [IO.File]::WriteAllText((Join-Path $flutterRoot 'bin/dart.bat'),'mock')
    $env:FLUTTER_ROOT = $flutterRoot
    Assert ((Resolve-JaxTool dart) -eq (Join-Path $flutterRoot 'bin/dart.bat')) 'Flutter-derived Dart failed'
    $failed=$false; try { Resolve-JaxTool adb | Out-Null } catch { $failed=$true }
    Assert $failed 'Missing tool must fail'
} finally { foreach ($entry in $saved.GetEnumerator()) { [Environment]::SetEnvironmentVariable($entry.Key,$entry.Value) } }

$root = Join-Path $temp 'backups'; New-Item -ItemType Directory $root | Out-Null
function New-Owned([int]$Number) {
    $id = '20260901_00000' + $Number + '_' + ('a' * 32)
    $directory = Join-Path $root $id; New-Item -ItemType Directory $directory | Out-Null
    @{owner='jax-sync-backup';metadataVersion=1;sessionId=$id;createdAtUtc='2026-09-01T00:00:00Z';schemaVersion=24;protocolVersion=11;status='Success'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'metadata.json')
    return $directory
}
$old=New-Owned 0; $new=New-Owned 1; $bad=New-Owned 2
Set-Content -LiteralPath (Join-Path $bad 'metadata.json') '{}'
$unknown=Join-Path $root 'personal'; New-Item -ItemType Directory $unknown | Out-Null
Assert (Test-JaxOwnedBackup $root $old) 'Owned session rejected'
Assert (-not (Test-JaxOwnedBackup $root $root)) 'Root accepted'
Assert (-not (Test-JaxOwnedBackup $root (Join-Path $root '..'))) 'Traversal accepted'
Invoke-JaxBackupRetention -Root $root -Keep 1 | Out-Null
Assert (Test-Path $old) 'Dry run deleted data'
Invoke-JaxBackupRetention -Root $root -Keep 1 -Apply | Out-Null
Assert (-not (Test-Path $old)) 'Apply did not delete old owned session'
Assert ((Test-Path $new) -and (Test-Path $bad) -and (Test-Path $unknown)) 'Unknown data deleted'
$junction=Join-Path $root 'linked'
New-Item -ItemType Junction -Path $junction -Target $new | Out-Null
Assert (-not (Test-JaxOwnedBackup $root $junction)) 'Junction accepted'
# Also reject an otherwise valid session containing a linked descendant.
New-Item -ItemType Junction -Path (Join-Path $new 'outside') -Target $unknown | Out-Null
Assert (-not (Test-JaxOwnedBackup $root $new)) 'Linked descendant accepted'
Write-Output 'PASS: locator, owned retention, malformed metadata, unknown directories, dry-run, apply and junction guards. Temporary evidence retained outside repository.'
