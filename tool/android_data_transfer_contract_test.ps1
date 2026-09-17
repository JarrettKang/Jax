$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'copy_windows_data_to_android.ps1'
$helperPath = Join-Path $PSScriptRoot 'database_snapshot.dart'
foreach ($path in @($scriptPath, $helperPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing transfer tool file: $path" }
}

$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
if ($errors.Count) { throw "PowerShell parse errors: $($errors -join '; ')" }

$content = Get-Content -LiteralPath $scriptPath -Raw
$required = @{
  'requires an explicit device when ambiguous' = 'Multiple Android devices are connected'
  'validates selected Debug device' = 'Assert-JaxDebugDevice'
  'requires a debuggable package' = 'Package is not debuggable with run-as'
  'stops the app before database access' = "'am', 'force-stop'"
  'backs up Android before import' = 'New-AndroidBackup'
  'uses a consistent Windows snapshot' = "'snapshot', `$SourceDatabase"
  'removes stale WAL and SHM' = '$databaseRelativePath-wal'
  'round-trip verifies imported bytes' = 'Imported Android database differs'
  'defaults to preview' = 'DRY_RUN'
  'requires dual confirmation' = '-not $Apply -or -not $ConfirmOverwrite'
  'rolls back failed overwrite' = 'Install-Database $backup'
}
foreach ($entry in $required.GetEnumerator()) {
  if ($content -notmatch [regex]::Escape($entry.Value)) { throw "Missing safety contract: $($entry.Key)" }
}

$backupIndex = $content.IndexOf('$backup = New-AndroidBackup')
$installIndex = $content.IndexOf('Install-Database $snapshot')
if ($backupIndex -lt 0 -or $installIndex -le $backupIndex) {
  throw 'Required order is verified backup -> overwrite. Implicit migration is forbidden.'
}

$helper = Get-Content -LiteralPath $helperPath -Raw
foreach ($token in @('VACUUM INTO', 'PRAGMA user_version', 'PRAGMA integrity_check', 'PRAGMA foreign_key_check')) {
  if ($helper -notmatch [regex]::Escape($token)) { throw "Snapshot helper is missing: $token" }
}

Write-Output 'Android Debug data-transfer safety contract passed.'
