$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'sync_phase2a.ps1'
$content = Get-Content -LiteralPath $scriptPath -Raw

$required = @{
  'requires explicit serial for multiple devices' = 'Multiple Android devices are connected'
  'checks installed package' = 'pm'', ''path'
  'checks debug sandbox access' = 'run-as'', $Package, ''pwd'
  'takes consistent SQLite copies' = 'tool/database_snapshot.dart'', ''snapshot'
  'runs preview compare' = 'tool/sync_phase2a.dart'', ''compare'
  'verifies Windows business facts' = 'Windows business facts changed during Analyze'
  'verifies Android business facts' = 'Android business facts changed during Analyze'
  'restarts only a previously running app' = 'if ($wasRunning)'
}
foreach ($entry in $required.GetEnumerator()) {
  if (-not $content.Contains($entry.Value)) { throw "Missing Phase 2A contract: $($entry.Key)" }
}
foreach ($forbidden in @('Install-Database', 'adb install', 'tombstone ack', 'DELETE FROM', 'UPDATE events')) {
  if ($content.Contains($forbidden)) { throw "Phase 2A script contains forbidden write path: $forbidden" }
}
Write-Output 'Phase 2A ADB read-only acquisition contract passed.'
