# Unknown or legacy sessions are preserved. No implicit ownership migration.
function Test-JaxOwnedBackup([string]$Root, [string]$Directory) {
    try {
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
        $full = [IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
        if ((Split-Path -Parent $full) -ne $rootFull -or $full -eq $rootFull) { return $false }
        $cursor = $full
        while ($cursor) {
            if ((Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
            $parent = Split-Path -Parent $cursor
            if ($parent -eq $cursor) { break }; $cursor = $parent
        }
        # Refuse linked descendants too; do not traverse a directory link.
        $queue = [Collections.Generic.Queue[string]]::new(); $queue.Enqueue($full)
        while ($queue.Count) {
            foreach ($entry in Get-ChildItem -LiteralPath $queue.Dequeue() -Force) {
                if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
                if ($entry.PSIsContainer) { $queue.Enqueue($entry.FullName) }
            }
        }
        $metadata = Get-Content -LiteralPath (Join-Path $full 'metadata.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        $id = Split-Path -Leaf $full
        if ($id -notmatch '^\d{8}_\d{6}_[a-f0-9]{32}$') { return $false }
        if ($metadata.owner -ne 'jax-sync-backup' -or $metadata.metadataVersion -ne 1 -or $metadata.sessionId -ne $id) { return $false }
        if (($metadata.schemaVersion -isnot [int] -and $metadata.schemaVersion -isnot [long]) -or $metadata.schemaVersion -lt 1 -or ($metadata.protocolVersion -isnot [int] -and $metadata.protocolVersion -isnot [long]) -or $metadata.protocolVersion -lt 1) { return $false }
        [void][DateTimeOffset]::Parse($metadata.createdAtUtc)
        if ($metadata.status -notin @('Success','SYNC_SUCCEEDED','SYNC_FAILED_ROLLED_BACK','SYNC_APPLIED_BASELINE_WRITE_FAILED','CRITICAL_ROLLBACK_FAILURE')) { return $false }
        return $true
    } catch { return $false }
}

function Invoke-JaxBackupRetention {
    param([string]$Root, [ValidateRange(1,50)][int]$Keep = 5, [string]$ActiveSession, [switch]$Apply)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $seen = 0
    foreach ($directory in Get-ChildItem -LiteralPath $Root -Directory -Force | Sort-Object Name -Descending) {
        if (-not (Test-JaxOwnedBackup $Root $directory.FullName)) { Write-Verbose 'Unknown skipped: unowned, malformed or linked directory.'; continue }
        $metadata = Get-Content -LiteralPath (Join-Path $directory.FullName 'metadata.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($directory.FullName -eq $ActiveSession -or $metadata.status -eq 'CRITICAL_ROLLBACK_FAILURE') { Write-Verbose 'Would keep: active or critical session.'; continue }
        $seen++
        if ($seen -le $Keep) { Write-Verbose 'Would keep: retained session.'; continue }
        Write-Output "Would delete Jax-owned session: $($metadata.sessionId)"
        if ($Apply) {
            if (-not (Test-JaxOwnedBackup $Root $directory.FullName)) { throw 'Backup ownership changed before cleanup; stopped.' }
            Remove-Item -LiteralPath $directory.FullName -Recurse -Force -ErrorAction Stop
        }
    }
}
