$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'sync_phase2b2.ps1'
$dartPath = Join-Path $PSScriptRoot 'sync_phase2b2.dart'
foreach ($path in @($scriptPath, $dartPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing Phase 2B-2 tool: $path" }
}

$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
if ($errors.Count) { throw "PowerShell parse errors: $($errors -join '; ')" }

$content = Get-Content -LiteralPath $scriptPath -Raw
$required = @{
  'requires explicit high-risk confirmation' = 'FIRST_REAL_DUAL_DEVICE_SYNC'
  'uses an exclusive coordinator lock' = '[IO.FileMode]::CreateNew'
  'stops Android before final acquisition' = 'shell am force-stop'
  'uses consistent SQLite snapshots' = "tool/database_snapshot.dart', 'snapshot"
  'requires both readable backups' = "tool/database_snapshot.dart', 'verify"
  'compiles a resolved plan before apply' = "tool/sync_phase2b2.dart', 'compile"
  'uses entity-level Android command' = 'applyMutationPlan'
  'validates both final databases' = "tool/sync_phase2b2.dart', 'verify"
  'writes baseline only after verification' = "tool/sync_phase2b2.dart', 'baseline-write"
  'runs post-sync three-way analysis' = 'PostSyncAnalyze'
  'restores both sides on failure' = 'Restore-Windows $script:report.windowsBackup'
  'reports critical rollback failure' = 'CRITICAL_ROLLBACK_FAILURE'
  'writes structured IPC as UTF-8 without BOM' = '[Text.UTF8Encoding]::new($false)'
  'reads structured JSON explicitly as UTF-8' = '-Raw -Encoding UTF8 | ConvertFrom-Json'
}
foreach ($entry in $required.GetEnumerator()) {
  if (-not $content.Contains($entry.Value)) { throw "Missing Phase 2B-2 contract: $($entry.Key)" }
}

$confirmation = $content.LastIndexOf("if (`$Confirmation -ne 'FIRST_REAL_DUAL_DEVICE_SYNC')")
$stop = $content.LastIndexOf('Stop-Apps')
$windowsApply = $content.LastIndexOf("tool/sync_phase2b2.dart', 'apply-windows")
$androidApply = $content.LastIndexOf('Apply-Android $mutationPath')
$baseline = $content.LastIndexOf("tool/sync_phase2b2.dart', 'baseline-write")
if ($confirmation -lt 0 -or $stop -le $confirmation -or $windowsApply -le $stop -or $androidApply -le $windowsApply -or $baseline -le $androidApply) {
  throw 'Required order is confirmation -> stop -> Windows -> Android -> baseline.'
}

foreach ($forbidden in @('adb uninstall', 'pm clear', 'clear data')) {
  if ($content.Contains($forbidden)) { throw "Forbidden real-sync operation: $forbidden" }
}
Write-Output 'Phase 2B-2 guarded real-sync contract passed.'
