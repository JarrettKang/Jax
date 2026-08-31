[CmdletBinding()]
param(
    [ValidateSet('Analyze', 'Apply')]
    [string]$Action = 'Analyze',
    [string]$Device,
    [string]$Resolution,
    [string]$Confirmation,
    [string]$WindowsDatabase = (Join-Path $env:APPDATA 'Jax\jax.db'),
    [string]$Package = 'com.example.jax',
    [string]$StorageRoot,
    [int]$StorageLayoutVersion = -1,
    [int]$BackupRetention = 0,
    [string]$OutputRoot,
    [string]$BackupRoot,
    [string]$Baseline,
    [int]$KeepWindowsProcessId = 0,
    [switch]$NoLaunchPreview,
    [string]$StatusPath,
    [string]$ResultPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$OutputEncoding = $utf8NoBom
[Console]::OutputEncoding = $utf8NoBom
[Console]::InputEncoding = $utf8NoBom
$storageConfigPath = Join-Path $env:APPDATA 'Jax\sync_storage.json'
if (-not $StorageRoot) {
    if (Test-Path -LiteralPath $storageConfigPath) {
        $storageConfig = Get-Content -LiteralPath $storageConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $StorageRoot = $storageConfig.root
        if ($StorageLayoutVersion -lt 0) { $StorageLayoutVersion = [int]$storageConfig.layoutVersion }
        if ($BackupRetention -le 0) { $BackupRetention = [int]$storageConfig.backupRetention }
    } else {
        $StorageRoot = Join-Path $env:APPDATA 'Jax'
        if ($StorageLayoutVersion -lt 0) { $StorageLayoutVersion = 0 }
    }
}
if ($StorageLayoutVersion -lt 0) { $StorageLayoutVersion = 1 }
if ($BackupRetention -lt 1 -or $BackupRetention -gt 50) { $BackupRetention = 5 }
if (-not $Baseline) {
    $Baseline = if ($StorageLayoutVersion -eq 0) { Join-Path $StorageRoot 'sync\last_successful_sync.json' } else { Join-Path $StorageRoot 'baseline\last_successful_sync.json' }
}
if (-not $BackupRoot) { $BackupRoot = if ($StorageLayoutVersion -eq 0) { Join-Path $StorageRoot 'sync_backups' } else { Join-Path $StorageRoot 'backups' } }
if (-not $OutputRoot) { $OutputRoot = Join-Path $StorageRoot 'sessions' }
$androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { '<android-sdk>' }
$adb = Join-Path $androidHome 'platform-tools\adb.exe'
$dart = '<flutter-sdk>\bin\dart.bat'
$remoteDatabase = 'databases/jax.db'
$windowsExe = Join-Path $projectRoot 'build\windows\x64\runner\Debug\jax.exe'
$lockPath = Join-Path $StorageRoot '.active_session.lock'
$script:serial = $null
$script:session = $null
$script:androidWasRunning = $false
$script:windowsWasRunning = $false
$script:applyStarted = $false
$script:backupsReady = $false
$script:report = [ordered]@{
    action = $Action
    status = 'Initializing'
    device = $Device
    package = $Package
    stages = [Collections.Generic.List[string]]::new()
}

function Set-Stage([string]$Stage) {
    $script:report.status = $Stage
    $script:report.stages.Add($Stage)
    Write-Host "SYNC_STAGE $Stage"
    Write-ExternalJson $StatusPath ([ordered]@{ status = $Stage; stages = $script:report.stages; timestamp = (Get-Date).ToString('o') })
}

function Write-ExternalJson([string]$Path, [object]$Value) {
    if (-not $Path) { return }
    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $staged = "$Path.pending"
    [IO.File]::WriteAllText($staged, ($Value | ConvertTo-Json -Depth 30), $script:utf8NoBom)
    Move-Item -LiteralPath $staged -Destination $Path -Force
}

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    $lines = if ([IO.Path]::GetExtension($File) -in @('.bat', '.cmd')) { & $env:ComSpec /d /c $File @Arguments } else { & $File @Arguments }
    $code = $LASTEXITCODE
    foreach ($line in $lines) { Write-Host $line }
    if ($code -ne 0) { throw "Command failed ($code): $File $($Arguments -join ' ')" }
    return @($lines)
}

function Get-AdbText([string[]]$Arguments) {
    $text = & $adb -s $script:serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB failed: $($Arguments -join ' ')`n$($text -join "`n")" }
    return ($text -join "`n").Trim()
}

function Export-AdbFile([string]$Remote, [string]$Destination) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $adb
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    # Windows PowerShell 5.1 uses .NET Framework ProcessStartInfo, which has no
    # ArgumentList property. These values are validated serial/package/relative
    # app paths and contain no shell metacharacters; stdout remains binary.
    $start.Arguments = "-s $($script:serial) exec-out run-as $Package cat $Remote"
    $process = [Diagnostics.Process]::Start($start)
    $stream = [IO.File]::Create($Destination)
    try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Dispose() }
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Could not read $Remote`: $errorText" }
}

function Test-AndroidFile([string]$Remote) {
    & $adb -s $script:serial shell run-as $Package test -f $Remote
    return $LASTEXITCODE -eq 0
}

function Capture-Android([string]$Directory, [string]$Name) {
    $raw = Join-Path $Directory "$Name.raw.db"
    Export-AdbFile $remoteDatabase $raw
    foreach ($suffix in @('-wal', '-shm')) {
        if (Test-AndroidFile "$remoteDatabase$suffix") { Export-AdbFile "$remoteDatabase$suffix" "$raw$suffix" }
    }
    $safe = Join-Path $Directory "$Name.db"
    Invoke-Checked $dart @('run', 'tool/database_snapshot.dart', 'snapshot', $raw, $safe) | Out-Null
    return $safe
}

function Export-Snapshot([string]$Database, [string]$Json) {
    Invoke-Checked $dart @('run', 'tool/sync_phase2a.dart', 'export', $Database, $Json) | Out-Null
}

function Fingerprint([string]$SnapshotJson) {
    $text = & $env:ComSpec /d /c $dart run tool/sync_phase2a.dart fingerprint $SnapshotJson
    if ($LASTEXITCODE -ne 0) { throw "Could not fingerprint $SnapshotJson" }
    return ($text -join "`n").Trim()
}

function Stop-Apps {
    Set-Stage 'StoppingApps'
    $runningPid = & $adb -s $script:serial shell pidof $Package 2>$null
    $script:androidWasRunning = ($runningPid -join '').Trim() -ne ''
    & $adb -s $script:serial shell am force-stop $Package | Out-Null
    $jax = @(Get-Process jax -ErrorAction SilentlyContinue)
    $script:windowsWasRunning = $jax.Count -gt 0
    foreach ($process in $jax) {
        if ($KeepWindowsProcessId -le 0 -or $process.Id -ne $KeepWindowsProcessId) { Stop-Process -Id $process.Id -Force }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while (@(Get-Process jax -ErrorAction SilentlyContinue | Where-Object { $KeepWindowsProcessId -le 0 -or $_.Id -ne $KeepWindowsProcessId }).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (@(Get-Process jax -ErrorAction SilentlyContinue | Where-Object { $KeepWindowsProcessId -le 0 -or $_.Id -ne $KeepWindowsProcessId }).Count -gt 0) { throw 'Windows Jax did not stop.' }
}

function Start-Apps {
    Set-Stage 'RestartingApps'
    if ($KeepWindowsProcessId -le 0 -and (Test-Path -LiteralPath $windowsExe)) { Start-Process -FilePath $windowsExe | Out-Null }
    & $adb -s $script:serial shell am start -n "$Package/.MainActivity" | Out-Null
}

function Start-SyncPreview([string]$Plan, [string]$WindowsJson, [string]$AndroidJson, [string]$ResolutionPath) {
    Set-Stage 'Resolving'
    $env:JAX_SYNC_PLAN = $Plan
    $env:JAX_SYNC_WINDOWS_SNAPSHOT = $WindowsJson
    $env:JAX_SYNC_ANDROID_SNAPSHOT = $AndroidJson
    $env:JAX_SYNC_RESOLUTION = $ResolutionPath
    $env:JAX_SYNC_DEVICE = $script:serial
    $env:JAX_SYNC_PROJECT_ROOT = $projectRoot
    if (Test-Path -LiteralPath $Baseline) { $env:JAX_SYNC_BASELINE = $Baseline } else { Remove-Item Env:JAX_SYNC_BASELINE -ErrorAction SilentlyContinue }
    try {
        if (-not (Test-Path -LiteralPath $windowsExe)) { throw "Windows Debug executable not found: $windowsExe" }
        Start-Process -FilePath $windowsExe | Out-Null
        & $adb -s $script:serial shell am start -n "$Package/.MainActivity" | Out-Null
    } finally {
        foreach ($name in @('JAX_SYNC_PLAN', 'JAX_SYNC_WINDOWS_SNAPSHOT', 'JAX_SYNC_ANDROID_SNAPSHOT', 'JAX_SYNC_RESOLUTION', 'JAX_SYNC_DEVICE', 'JAX_SYNC_PROJECT_ROOT', 'JAX_SYNC_BASELINE')) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
    }
}

function Push-AppFile([string]$Local, [string]$RemoteName) {
    $temporary = "/data/local/tmp/$RemoteName"
    Invoke-Checked $adb @('-s', $script:serial, 'push', $Local, $temporary) | Out-Null
    Get-AdbText @('shell', 'chmod', '644', $temporary) | Out-Null
    Get-AdbText @('shell', 'run-as', $Package, 'cp', $temporary, "files/$RemoteName") | Out-Null
    Get-AdbText @('shell', 'rm', '-f', $temporary) | Out-Null
    return "/data/user/0/$Package/files/$RemoteName"
}

function Apply-Android([string]$MutationPath) {
    Set-Stage 'ApplyingAndroid'
    $commandName = "sync_command_$($script:session).json"
    $resultName = "sync_result_$($script:session).json"
    $remoteResult = "/data/user/0/$Package/files/$resultName"
    $mutation = Get-Content -LiteralPath $MutationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $command = [ordered]@{
        action = 'applyMutationPlan'
        resultPath = $remoteResult
        mutationPlan = $mutation
    }
    $localCommand = Join-Path $script:sessionDirectory $commandName
    [IO.File]::WriteAllText($localCommand, ($command | ConvertTo-Json -Depth 100), $script:utf8NoBom)
    $remoteCommand = Push-AppFile $localCommand $commandName
    Get-AdbText @('shell', 'run-as', $Package, 'rm', '-f', "files/$resultName") | Out-Null
    & $adb -s $script:serial shell am start -n "$Package/.MainActivity" --es jax_sync_command $remoteCommand | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while (-not (Test-AndroidFile "files/$resultName") -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-AndroidFile "files/$resultName")) { throw 'Android Debug sync command timed out.' }
    $localResult = Join-Path $script:sessionDirectory $resultName
    Export-AdbFile "files/$resultName" $localResult
    & $adb -s $script:serial shell am force-stop $Package | Out-Null
    $result = Get-Content -LiteralPath $localResult -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $result.ok) { throw "Android Apply failed: $($result.error)" }
    $script:report.androidResult = $result
    Set-Stage 'ValidatingAndroid'
}

function Restore-Windows([string]$Backup) {
    $expected = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Jax\jax.db'))
    $actual = [IO.Path]::GetFullPath($WindowsDatabase)
    if ($actual -ne $expected) { throw "Unsafe Windows restore target: $actual" }
    $staged = "$actual.restore"
    Copy-Item -LiteralPath $Backup -Destination $staged -Force
    foreach ($candidate in @($actual, "$actual-wal", "$actual-shm")) { if (Test-Path -LiteralPath $candidate) { Remove-Item -LiteralPath $candidate -Force } }
    Move-Item -LiteralPath $staged -Destination $actual
}

function Restore-Android([string]$Backup) {
    $remote = "/data/local/tmp/jax_restore_$($script:session).db"
    Invoke-Checked $adb @('-s', $script:serial, 'push', $Backup, $remote) | Out-Null
    Get-AdbText @('shell', 'chmod', '644', $remote) | Out-Null
    Get-AdbText @('shell', 'run-as', $Package, 'cp', $remote, 'databases/jax.db.restore') | Out-Null
    Get-AdbText @('shell', 'run-as', $Package, 'rm', '-f', 'databases/jax.db-wal', 'databases/jax.db-shm') | Out-Null
    Get-AdbText @('shell', 'run-as', $Package, 'mv', 'databases/jax.db.restore', 'databases/jax.db') | Out-Null
    Get-AdbText @('shell', 'rm', '-f', $remote) | Out-Null
}

function Write-Report {
    if ($null -ne $script:sessionDirectory) {
        [IO.File]::WriteAllText((Join-Path $script:sessionDirectory 'sync_session_report.json'), ($script:report | ConvertTo-Json -Depth 20), $script:utf8NoBom)
    }
    Write-ExternalJson $ResultPath $script:report
}

function Complete-BackupSession([string]$Status, [bool]$Cleanup) {
    if (-not $script:report.Contains('windowsBackup')) { return }
    $backupDirectory = Split-Path -Parent $script:report.windowsBackup
    Write-ExternalJson (Join-Path $backupDirectory 'metadata.json') ([ordered]@{
        status = $Status
        timestamp = $script:session
        report = (Join-Path $script:sessionDirectory 'sync_session_report.json')
    })
    if (-not $Cleanup) { return }
    $sessions = @(Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    $normalSeen = 0
    foreach ($candidate in $sessions) {
        if ($candidate.FullName -eq $backupDirectory) { $normalSeen++; continue }
        $metadataPath = Join-Path $candidate.FullName 'metadata.json'
        $candidateStatus = $null
        if (Test-Path -LiteralPath $metadataPath) {
            try { $candidateStatus = (Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json).status } catch { $candidateStatus = $null }
        }
        if ($candidateStatus -eq 'CRITICAL_ROLLBACK_FAILURE') { continue }
        $normalSeen++
        if ($normalSeen -gt $BackupRetention) { Remove-Item -LiteralPath $candidate.FullName -Recurse -Force }
    }
}

if (-not (Test-Path -LiteralPath $adb)) { throw "adb not found: $adb" }
if (-not (Test-Path -LiteralPath $WindowsDatabase)) { throw "Windows database not found: $WindowsDatabase" }
$devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '^([^\s]+)\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
if ($Device) {
    if ($Device -notin $devices) { throw "Requested device is not connected: $Device" }
    $script:serial = $Device
} elseif ($devices.Count -eq 1) { $script:serial = $devices[0] }
elseif ($devices.Count -eq 0) { throw 'No authorized Android device is connected.' }
else { throw 'Multiple Android devices are connected. Specify -Device.' }
$script:report.device = $script:serial
$packagePath = Get-AdbText @('shell', 'pm', 'path', $Package)
if (-not $packagePath.StartsWith('package:')) { throw "Package is not installed: $Package" }
[void](Get-AdbText @('shell', 'run-as', $Package, 'pwd'))

$lockDirectory = Split-Path -Parent $lockPath
New-Item -ItemType Directory -Path $lockDirectory -Force | Out-Null
$lockStream = $null
try {
    try {
        $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    } catch [IO.IOException] {
        throw 'SYNC_SESSION_ACTIVE: another real sync session is already running.'
    }
    $script:session = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:sessionDirectory = Join-Path $OutputRoot "sync_phase2b2_$($script:session)"
    New-Item -ItemType Directory -Path $script:sessionDirectory -Force | Out-Null
    $script:report.timestamp = $script:session
    $script:report.sessionDirectory = $script:sessionDirectory
    $script:report.storageRoot = $StorageRoot
    $script:report.storageLayoutVersion = $StorageLayoutVersion
    $script:report.backupRetention = $BackupRetention
    $script:report.baselinePath = $Baseline

    if ($Action -eq 'Apply') {
        if ($Confirmation -ne 'FIRST_REAL_DUAL_DEVICE_SYNC') { throw 'CONFIRMATION_REQUIRED: exact high-risk confirmation is missing.' }
        if (-not $Resolution -or -not (Test-Path -LiteralPath $Resolution)) { throw 'A resolution JSON file is required.' }
    }

    Stop-Apps
    Set-Stage 'Analyzing'
    $windowsDbCopy = Join-Path $script:sessionDirectory 'windows_before_sync.db'
    Invoke-Checked $dart @('run', 'tool/database_snapshot.dart', 'snapshot', $WindowsDatabase, $windowsDbCopy) | Out-Null
    $androidDbCopy = Capture-Android $script:sessionDirectory 'android_before_sync'
    $windowsJson = Join-Path $script:sessionDirectory 'windows.json'
    $androidJson = Join-Path $script:sessionDirectory 'android.json'
    Export-Snapshot $windowsDbCopy $windowsJson
    Export-Snapshot $androidDbCopy $androidJson
    $planPath = Join-Path $script:sessionDirectory 'sync_plan.json'
    $compare = @('run', 'tool/sync_phase2a.dart', 'compare', $windowsJson, $androidJson, $planPath)
    if (Test-Path -LiteralPath $Baseline) { $compare += $Baseline }
    Invoke-Checked $dart $compare | Out-Null
    $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:report.preWindowsFingerprint = $plan.windowsSourceFingerprint
    $script:report.preAndroidFingerprint = $plan.androidSourceFingerprint
    $script:report.preBaselineFingerprint = if ($plan.PSObject.Properties.Name -contains 'baselineFingerprint') { $plan.baselineFingerprint } else { $null }
    $script:report.analysisSummary = $plan.summary
    $script:report.warnings = $plan.warnings
    $script:report.planPath = $planPath
    $script:report.windowsSnapshotPath = $windowsJson
    $script:report.androidSnapshotPath = $androidJson

    if ($Action -eq 'Analyze') {
        $template = Join-Path $script:sessionDirectory 'resolution.json'
        Invoke-Checked $dart @('run', 'tool/sync_phase2b2.dart', 'resolution-template', $planPath, $template) | Out-Null
        $script:report.resolutionTemplate = $template
        $script:report.status = 'AnalysisReady'
        Write-Report
        Write-Host "SYNC_ANALYZE_READY plan=$planPath resolution=$template"
        if ($NoLaunchPreview) {
            & $adb -s $script:serial shell am start -n "$Package/.MainActivity" | Out-Null
        } else {
            Start-SyncPreview $planPath $windowsJson $androidJson $template
        }
        return
    }

    Set-Stage 'DryRun'
    $mutationPath = Join-Path $script:sessionDirectory 'mutation_plan.json'
    $compile = @('run', 'tool/sync_phase2b2.dart', 'compile', $planPath, $windowsJson, $androidJson, $Resolution, $mutationPath)
    if (Test-Path -LiteralPath $Baseline) { $compile += $Baseline }
    $compileOutput = Invoke-Checked $dart $compile
    $mutation = Get-Content -LiteralPath $mutationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:report.windowsOperations = @($mutation.windowsOperations).Count
    $script:report.androidOperations = @($mutation.androidOperations).Count
    $script:report.windowsOperationSummary = $mutation.windowsSummary
    $script:report.androidOperationSummary = $mutation.androidSummary
    $script:report.resolvedConflicts = $mutation.resolvedConflicts
    $script:report.expectedFinalFingerprint = $mutation.expectedFinalFingerprint
    $backupDirectory = Join-Path $BackupRoot $script:session
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    $windowsBackup = Join-Path $backupDirectory 'windows_before_sync.db'
    $androidBackup = Join-Path $backupDirectory 'android_before_sync.db'
    Set-Stage 'BackingUpWindows'
    Copy-Item -LiteralPath $windowsDbCopy -Destination $windowsBackup
    Invoke-Checked $dart @('run', 'tool/database_snapshot.dart', 'verify', $windowsBackup) | Out-Null
    Set-Stage 'BackingUpAndroid'
    Copy-Item -LiteralPath $androidDbCopy -Destination $androidBackup
    Invoke-Checked $dart @('run', 'tool/database_snapshot.dart', 'verify', $androidBackup) | Out-Null
    $script:backupsReady = $true
    $script:report.windowsBackup = $windowsBackup
    $script:report.androidBackup = $androidBackup
    $script:report.windowsBackupFingerprint = Fingerprint $windowsJson
    $script:report.androidBackupFingerprint = Fingerprint $androidJson
    Set-Stage 'BackupsReady'

    $script:applyStarted = $true
    Set-Stage 'ApplyingWindows'
    Invoke-Checked $dart @('run', 'tool/sync_phase2b2.dart', 'apply-windows', $WindowsDatabase, $mutationPath, $windowsBackup) | Out-Null
    Set-Stage 'ValidatingWindows'
    Apply-Android $mutationPath
    Set-Stage 'FinalVerification'
    Invoke-Checked $dart @('run', 'tool/sync_phase2b2.dart', 'verify', $WindowsDatabase, $mutationPath) | Out-Null
    $androidFinal = Capture-Android $script:sessionDirectory 'android_final'
    Invoke-Checked $dart @('run', 'tool/sync_phase2b2.dart', 'verify', $androidFinal, $mutationPath) | Out-Null

    Set-Stage 'WritingBaseline'
    try {
        Invoke-Checked $dart @('run', 'tool/sync_phase2b2.dart', 'baseline-write', $Baseline, $mutationPath) | Out-Null
        $baselineOutput = Invoke-Checked $dart @('run', 'tool/sync_phase2b2.dart', 'baseline-read', $Baseline)
        $script:report.baselineResult = ($baselineOutput -join "`n")
    } catch {
        $script:report.status = 'SYNC_APPLIED_BASELINE_WRITE_FAILED'
        $script:report.error = "Business data is synchronized and verified, but the baseline could not be persisted: $_"
        Write-Report
        Complete-BackupSession $script:report.status $true
        Start-Apps
        Write-Warning $script:report.error
        return
    }

    Set-Stage 'PostSyncAnalyze'
    $postWindows = Join-Path $script:sessionDirectory 'windows_post.db'
    Invoke-Checked $dart @('run', 'tool/database_snapshot.dart', 'snapshot', $WindowsDatabase, $postWindows) | Out-Null
    $postAndroid = Capture-Android $script:sessionDirectory 'android_post'
    $postWindowsJson = Join-Path $script:sessionDirectory 'windows_post.json'
    $postAndroidJson = Join-Path $script:sessionDirectory 'android_post.json'
    Export-Snapshot $postWindows $postWindowsJson
    Export-Snapshot $postAndroid $postAndroidJson
    $postPlan = Join-Path $script:sessionDirectory 'post_sync_plan.json'
    Invoke-Checked $dart @('run', 'tool/sync_phase2a.dart', 'compare', $postWindowsJson, $postAndroidJson, $postPlan, $Baseline) | Out-Null
    $post = Get-Content -LiteralPath $postPlan -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:report.postSyncSummary = $post.summary
    if ($post.summary.onlyWindows -ne 0 -or $post.summary.onlyAndroid -ne 0 -or $post.summary.different -ne 0 -or $post.summary.manualConflicts -ne 0 -or $post.summary.listConflicts -ne 0 -or $post.summary.invariantConflicts -ne 0) {
        throw 'FINAL_STATE_MISMATCH: post-sync Analyze still contains synchronized differences.'
    }
    $script:report.finalFingerprint = $mutation.expectedFinalFingerprint
    $script:report.status = 'Success'
    Write-Report
    Complete-BackupSession $script:report.status $true
    Start-Apps
    Write-Host "FIRST_REAL_DUAL_DEVICE_SYNC_SUCCESS report=$(Join-Path $script:sessionDirectory 'sync_session_report.json')"
} catch {
    $failure = $_
    $script:report.error = "$failure"
    if ($script:applyStarted -and $script:backupsReady) {
        try {
            Set-Stage 'RollingBack'
            & $adb -s $script:serial shell am force-stop $Package | Out-Null
            Restore-Windows $script:report.windowsBackup
            Restore-Android $script:report.androidBackup
            $rollbackWindows = Join-Path $script:sessionDirectory 'rollback_windows.json'
            $rollbackAndroidDb = Capture-Android $script:sessionDirectory 'rollback_android'
            $rollbackAndroid = Join-Path $script:sessionDirectory 'rollback_android.json'
            Export-Snapshot $WindowsDatabase $rollbackWindows
            Export-Snapshot $rollbackAndroidDb $rollbackAndroid
            if ((Fingerprint $rollbackWindows) -ne $script:report.preWindowsFingerprint -or (Fingerprint $rollbackAndroid) -ne $script:report.preAndroidFingerprint) {
                throw 'Restored fingerprints differ from pre-sync state.'
            }
            $script:report.status = 'SYNC_FAILED_ROLLED_BACK'
            Write-Report
            Complete-BackupSession $script:report.status $true
            Start-Apps
            throw "SYNC_FAILED_ROLLED_BACK: $failure"
        } catch {
            if ($script:report.status -ne 'SYNC_FAILED_ROLLED_BACK') {
                $script:report.status = 'CRITICAL_ROLLBACK_FAILURE'
                $script:report.rollbackError = "$_"
                Write-Report
                Complete-BackupSession $script:report.status $false
                throw "CRITICAL_ROLLBACK_FAILURE: $_"
            }
            throw
        }
    }
    $script:report.status = 'FailedBeforeApply'
    Write-Report
    try { Start-Apps } catch { Write-Warning "Could not restart apps after pre-Apply failure: $_" }
    throw
} finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
    if (Test-Path -LiteralPath $lockPath) { Remove-Item -LiteralPath $lockPath -Force }
}
