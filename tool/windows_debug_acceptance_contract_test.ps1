$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'windows_debug_acceptance.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Missing Windows Debug acceptance script: $scriptPath"
}

$content = Get-Content -LiteralPath $scriptPath -Raw
$requiredPatterns = @{
  'records pre-existing Jax processes' = 'Get-JaxProcessSnapshot'
  'always performs cleanup' = 'finally'
  'restores the normal Debug entrypoint' = 'build windows --debug'
  'checks for integration-test contamination' = 'Assert-NormalDebugEntrypoint'
  'checks that the executable is unlocked' = 'Assert-FileUnlocked'
}

foreach ($requirement in $requiredPatterns.GetEnumerator()) {
  if ($content -notmatch [regex]::Escape($requirement.Value)) {
    throw "The acceptance script does not satisfy: $($requirement.Key)"
  }
}

Write-Output 'Windows Debug acceptance script contract passed.'
