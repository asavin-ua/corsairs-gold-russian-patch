param(
    [string]$GamePath,
    [ValidateSet('Install', 'Verify', 'Uninstall')]
    [string]$Mode = 'Install',
    [switch]$CreateBackup
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$payloadRoot = Join-Path $packageRoot 'payload'
$manifestPath = Join-Path $packageRoot 'manifest.json'
$backupFolderName = 'Russian_Patch_Backup_1.0'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-GameCandidate([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try { $resolved = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim('"'))) }
    catch { return $null }
    if ((Test-Path -LiteralPath (Join-Path $resolved 'corsairs.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $resolved 'data\missions') -PathType Container)) {
        return $resolved.TrimEnd('\')
    }
    return $null
}

function Resolve-GameRoot([string]$RequestedPath) {
    $requested = Get-GameCandidate $RequestedPath
    if ($requested) { return $requested }
    if ($RequestedPath) { throw "Corsairs Gold was not found at: $RequestedPath" }

    $candidates = [Collections.Generic.List[string]]::new()
    $known = @(
        (Get-Location).Path,
        $packageRoot,
        (Split-Path -Parent $packageRoot),
        (Join-Path ${env:ProgramFiles} 'Corsairs Gold'),
        (Join-Path ${env:ProgramFiles(x86)} 'Corsairs Gold')
    )
    foreach ($path in $known) {
        $candidate = Get-GameCandidate $path
        if ($candidate -and -not $candidates.Contains($candidate)) { $candidates.Add($candidate) }
    }

    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($registryPath in $registryPaths) {
        foreach ($entry in @(Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match 'Corsairs Gold'
        })) {
            $candidate = Get-GameCandidate $entry.InstallLocation
            if (-not $candidate -and $entry.DisplayIcon) {
                $candidate = Get-GameCandidate (Split-Path -Parent ($entry.DisplayIcon -replace ',\d+$', '').Trim('"'))
            }
            if ($candidate -and -not $candidates.Contains($candidate)) { $candidates.Add($candidate) }
        }
    }

    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) {
        Write-Host 'Several Corsairs Gold installations were found:'
        for ($i = 0; $i -lt $candidates.Count; $i++) { Write-Host "[$($i + 1)] $($candidates[$i])" }
        $choice = Read-Host 'Choose installation number'
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $candidates.Count) {
            return $candidates[[int]$choice - 1]
        }
        throw 'Invalid installation number.'
    }

    $entered = Read-Host 'Enter the Corsairs Gold folder (the folder containing corsairs.exe)'
    $candidate = Get-GameCandidate $entered
    if (-not $candidate) { throw 'The selected folder is not a Corsairs Gold installation.' }
    return $candidate
}

function Copy-Atomic([string]$Source, [string]$Destination) {
    $directory = Split-Path -Parent $Destination
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ([IO.Path]::GetRandomFileName())
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary -Force
        Move-Item -LiteralPath $temporary -Destination $Destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing package manifest: $manifestPath" }
if (-not (Test-Path -LiteralPath $payloadRoot -PathType Container)) { throw "Missing package payload: $payloadRoot" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$gameRoot = Resolve-GameRoot $GamePath
$executable = Join-Path $gameRoot 'corsairs.exe'
$backupRoot = Join-Path $gameRoot $backupFolderName
$backupManifestPath = Join-Path $backupRoot 'backup-manifest.json'

foreach ($file in $manifest.Files) {
    $payload = Join-Path $payloadRoot $file.Path
    if (-not (Test-Path -LiteralPath $payload -PathType Leaf)) { throw "Payload file is missing: $($file.Path)" }
    if ((Get-Sha256 $payload) -cne $file.Sha256) { throw "Payload checksum failed: $($file.Path)" }
}

if ($Mode -eq 'Verify') {
    $errors = [Collections.Generic.List[string]]::new()
    if ((Get-Sha256 $executable) -cne $manifest.PatchedExecutableSha256) { $errors.Add('corsairs.exe is not patched.') }
    foreach ($file in $manifest.Files) {
        $target = Join-Path $gameRoot $file.Path
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { $errors.Add("Missing: $($file.Path)") }
        elseif ((Get-Sha256 $target) -cne $file.Sha256) { $errors.Add("Checksum mismatch: $($file.Path)") }
    }
    if ($errors.Count) { throw ($errors -join [Environment]::NewLine) }
    Write-Host "Russian patch verification: OK ($($manifest.Files.Count) resources and patched executable)."
    Write-Host "Game: $gameRoot"
    exit 0
}

if ($Mode -eq 'Uninstall') {
    if (-not (Test-Path -LiteralPath $backupManifestPath -PathType Leaf)) {
        throw "Backup manifest was not found: $backupManifestPath"
    }
    $backupManifest = Get-Content -LiteralPath $backupManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($file in $backupManifest.Files) {
        $backup = Join-Path $backupRoot $file.Path
        if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "Backup file is missing: $($file.Path)" }
        if ((Get-Sha256 $backup) -cne $file.Sha256) { throw "Backup checksum failed: $($file.Path)" }
    }
    foreach ($file in $backupManifest.Files) {
        Copy-Atomic (Join-Path $backupRoot $file.Path) (Join-Path $gameRoot $file.Path)
    }
    Write-Host 'Original files restored. The backup folder was retained for safety:'
    Write-Host $backupRoot
    exit 0
}

$exeHash = Get-Sha256 $executable
if ($exeHash -cne $manifest.OriginalExecutableSha256 -and $exeHash -cne $manifest.PatchedExecutableSha256) {
    throw "Unsupported corsairs.exe (SHA-256 $exeHash). This patch supports the English Corsairs Gold executable listed in README.txt."
}

$alreadyInstalled = $exeHash -ceq $manifest.PatchedExecutableSha256
if ($alreadyInstalled) {
    foreach ($file in $manifest.Files) {
        $target = Join-Path $gameRoot $file.Path
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-Sha256 $target) -cne $file.Sha256) {
            $alreadyInstalled = $false
            break
        }
    }
}
if ($alreadyInstalled) {
    Write-Host 'Russian patch is already installed and verified.'
    Write-Host "Game: $gameRoot"
    exit 0
}

if ($CreateBackup -and (Test-Path -LiteralPath $backupManifestPath -PathType Leaf)) {
    throw "An incomplete or different installation exists. Restore it first with Uninstall_Russian_Patch.cmd. Backup: $backupRoot"
}

$backupRecords = [Collections.Generic.List[object]]::new()
$pathsToBackUp = @('corsairs.exe') + @($manifest.Files | ForEach-Object { $_.Path })
foreach ($relative in $pathsToBackUp) {
    $target = Join-Path $gameRoot $relative
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Required game file is missing: $relative" }
}

$memoryRollback = @{}
if ($CreateBackup) {
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    foreach ($relative in $pathsToBackUp) {
        $target = Join-Path $gameRoot $relative
        $backup = Join-Path $backupRoot $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
        Copy-Item -LiteralPath $target -Destination $backup -Force
        $backupRecords.Add([pscustomobject]@{ Path = $relative; Sha256 = Get-Sha256 $backup })
    }
    $backupManifest = [ordered]@{
        PatchVersion = $manifest.PatchVersion
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        GamePath = $gameRoot
        Files = $backupRecords
    }
    $backupManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $backupManifestPath -Encoding UTF8
}
else {
    foreach ($relative in $pathsToBackUp) {
        $memoryRollback[$relative] = [IO.File]::ReadAllBytes((Join-Path $gameRoot $relative))
    }
}

try {
    foreach ($file in $manifest.Files) {
        Copy-Atomic (Join-Path $payloadRoot $file.Path) (Join-Path $gameRoot $file.Path)
    }
    if ($exeHash -ceq $manifest.OriginalExecutableSha256) {
        [byte[]]$bytes = [IO.File]::ReadAllBytes($executable)
        $offset = [int]$manifest.ExecutablePatchOffset
        if ($bytes[$offset] -ne [byte]$manifest.ExecutableOriginalByte) { throw 'Unexpected executable byte at patch offset.' }
        $bytes[$offset] = [byte]$manifest.ExecutablePatchedByte
        [IO.File]::WriteAllBytes($executable, $bytes)
    }
    if ((Get-Sha256 $executable) -cne $manifest.PatchedExecutableSha256) { throw 'Patched executable checksum failed.' }
    foreach ($file in $manifest.Files) {
        if ((Get-Sha256 (Join-Path $gameRoot $file.Path)) -cne $file.Sha256) { throw "Installed checksum failed: $($file.Path)" }
    }
}
catch {
    if ($CreateBackup) {
        foreach ($record in $backupRecords) {
            Copy-Atomic (Join-Path $backupRoot $record.Path) (Join-Path $gameRoot $record.Path)
        }
    }
    else {
        foreach ($relative in $memoryRollback.Keys) {
            [IO.File]::WriteAllBytes((Join-Path $gameRoot $relative), [byte[]]$memoryRollback[$relative])
        }
    }
    throw
}

Write-Host "Russian patch installed and verified: $($manifest.Files.Count) resources and patched executable."
Write-Host "Game:   $gameRoot"
if ($CreateBackup) { Write-Host "Backup: $backupRoot" }
else { Write-Host 'Persistent backup: not created (default clean-install mode).' }
Write-Host 'Restart the game completely before checking translated text.'
