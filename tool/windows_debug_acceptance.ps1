param(
  [string]$FlutterPath = 'flutter'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$debugDirectory = Join-Path $workspace 'build\windows\x64\runner\Debug'
$debugExecutable = Join-Path $debugDirectory 'jax.exe'
$debugKernel = Join-Path $debugDirectory 'data\flutter_assets\kernel_blob.bin'

function Get-JaxProcessSnapshot {
  param([string]$ExecutablePath)

  $resolvedExecutable = [IO.Path]::GetFullPath($ExecutablePath)
  return @(
    Get-Process -Name 'jax' -ErrorAction SilentlyContinue |
      Where-Object {
        try {
          [string]::Equals(
            [IO.Path]::GetFullPath($_.Path),
            $resolvedExecutable,
            [StringComparison]::OrdinalIgnoreCase
          )
        } catch {
          $false
        }
      } |
      Select-Object Id, StartTime, Path
  )
}

function Stop-NewJaxProcesses {
  param(
    [string]$ExecutablePath,
    [int[]]$ExistingProcessIds
  )

  $created = @(
    Get-JaxProcessSnapshot -ExecutablePath $ExecutablePath |
      Where-Object { $_.Id -notin $ExistingProcessIds }
  )
  if ($created.Count -eq 0) {
    return
  }

  foreach ($processInfo in $created) {
    $process = Get-Process -Id $processInfo.Id -ErrorAction SilentlyContinue
    if ($null -ne $process -and $process.MainWindowHandle -ne 0) {
      $null = $process.CloseMainWindow()
    }
  }

  $deadline = [DateTime]::UtcNow.AddSeconds(5)
  do {
    Start-Sleep -Milliseconds 100
    $remaining = @(
      Get-JaxProcessSnapshot -ExecutablePath $ExecutablePath |
        Where-Object { $_.Id -notin $ExistingProcessIds }
    )
  } while ($remaining.Count -gt 0 -and [DateTime]::UtcNow -lt $deadline)

  foreach ($processInfo in $remaining) {
    Stop-Process -Id $processInfo.Id -Force -ErrorAction SilentlyContinue
  }

  if ($remaining.Count -gt 0) {
    Start-Sleep -Milliseconds 500
  }
  $stillRunning = @(
    Get-JaxProcessSnapshot -ExecutablePath $ExecutablePath |
      Where-Object { $_.Id -notin $ExistingProcessIds }
  )
  if ($stillRunning.Count -gt 0) {
    throw "Windows Debug acceptance left Jax processes running: $($stillRunning.Id -join ', ')"
  }
}

function Assert-NormalDebugEntrypoint {
  param([string]$KernelPath)

  if (-not (Test-Path -LiteralPath $KernelPath)) {
    throw "The restored Debug kernel is missing: $KernelPath"
  }
  $bytes = [IO.File]::ReadAllBytes($KernelPath)
  $text = [Text.Encoding]::UTF8.GetString($bytes)
  if ($text.Contains('package:integration_test/')) {
    throw 'The Debug kernel still contains the integration-test entrypoint.'
  }
}

function Assert-FileUnlocked {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Expected file is missing: $Path"
  }
  try {
    $stream = [IO.File]::Open(
      $Path,
      [IO.FileMode]::Open,
      [IO.FileAccess]::Read,
      [IO.FileShare]::None
    )
    $stream.Dispose()
  } catch {
    throw "The Debug executable remains locked: $Path. $($_.Exception.Message)"
  }
}

Push-Location $workspace
try {
  $baseline = @(Get-JaxProcessSnapshot -ExecutablePath $debugExecutable)
  if ($baseline.Count -gt 0) {
    throw "Close the existing Debug Jax process before acceptance: $($baseline.Id -join ', ')"
  }
  $baselineIds = @($baseline | ForEach-Object { [int]$_.Id })
  $testFailure = $null

  try {
    & $FlutterPath test integration_test/world_category_collapse_preference_test.dart -d windows
    if ($LASTEXITCODE -ne 0) {
      throw "Windows WorldNode integration test failed with exit code $LASTEXITCODE."
    }

    & $FlutterPath test test/ui/world_planning_workflow_test.dart
    if ($LASTEXITCODE -ne 0) {
      throw "Windows Planning workflow test failed with exit code $LASTEXITCODE."
    }
  } catch {
    $testFailure = $_
  } finally {
    $cleanupFailure = $null
    try {
      Stop-NewJaxProcesses -ExecutablePath $debugExecutable -ExistingProcessIds $baselineIds
    } catch {
      $cleanupFailure = $_
    }

    # `flutter test ... -d windows` writes its test entrypoint into the shared
    # Debug bundle. Restore the normal lib/main.dart bundle before handoff.
    & $FlutterPath build windows --debug
    if ($LASTEXITCODE -ne 0) {
      throw "Restoring the normal Windows Debug build failed with exit code $LASTEXITCODE."
    }

    Stop-NewJaxProcesses -ExecutablePath $debugExecutable -ExistingProcessIds $baselineIds
    Assert-NormalDebugEntrypoint -KernelPath $debugKernel
    Assert-FileUnlocked -Path $debugExecutable
    if ($null -ne $cleanupFailure) {
      throw $cleanupFailure
    }
  }

  if ($null -ne $testFailure) {
    throw $testFailure
  }
  Write-Output 'Windows Debug acceptance passed; normal Debug app restored and unlocked.'
} finally {
  Pop-Location
}
