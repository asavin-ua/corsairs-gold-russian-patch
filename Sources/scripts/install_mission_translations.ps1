$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$sourceRoot = Join-Path $patchRoot 'translations'
$backupRoot = Join-Path $patchRoot 'backup\missions'
$missionsRoot = Join-Path $gameRoot 'data\missions'
$cp1251 = [Text.Encoding]::GetEncoding(1251)
$utf8 = New-Object Text.UTF8Encoding($false)

$sources = Get-ChildItem -LiteralPath $sourceRoot -File -Filter 'MIS*_*.utf8.txt'
foreach ($source in $sources) {
    if ($source.Name -match '^(MIS\d+)_([A-Za-z]+)_(INT|MSG)_(.+)\.utf8\.txt$') {
        $mission = $Matches[1]
        $nation = $Matches[2]
        $resourceDirectoryName = $Matches[3]
        $targetName = $Matches[4] + '.ENG'
    }
    elseif ($source.Name -match '^(MIS\d+)_([A-Za-z]+)_(.+)\.utf8\.txt$') {
        # Backward-compatible naming used by the existing book introductions.
        $mission = $Matches[1]
        $nation = $Matches[2]
        $resourceDirectoryName = 'INT'
        $targetName = $Matches[3] + '.ENG'
    }
    else {
        continue
    }

    # MSG resources need structural validation and controlled line installation.
    # They are handled only by msg_tool.py / manage_msg_translations.ps1 so a future
    # MSG translation cannot accidentally be installed by this bulk script.
    if ($resourceDirectoryName -eq 'MSG') {
        Write-Warning "Skipped MSG resource; use manage_msg_translations.ps1: $($source.Name)"
        continue
    }
    $missionDirectory = Join-Path $missionsRoot $mission
    $nationDirectory = Get-ChildItem -LiteralPath $missionDirectory -Directory |
        Where-Object { $_.Name -ieq $nation } |
        Select-Object -First 1
    if (-not $nationDirectory) {
        throw "Nation directory not found for $($source.Name)"
    }

    $resourceDirectory = Get-ChildItem -LiteralPath $nationDirectory.FullName -Directory |
        Where-Object { $_.Name -ieq $resourceDirectoryName } |
        Select-Object -First 1
    if (-not $resourceDirectory) {
        throw "Resource directory $resourceDirectoryName not found for $($source.Name)"
    }
    $target = Get-ChildItem -LiteralPath $resourceDirectory.FullName -File |
        Where-Object { $_.Name -ieq $targetName } |
        Select-Object -First 1
    if (-not $target) {
        throw "Target mission file not found for $($source.Name)"
    }

    $relativeTarget = $target.FullName.Substring($missionsRoot.Length).TrimStart('\')
    $backup = Join-Path $backupRoot $relativeTarget
    if (-not (Test-Path -LiteralPath $backup)) {
        $backupDirectory = Split-Path -Parent $backup
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        Copy-Item -LiteralPath $target.FullName -Destination $backup
    }

    $text = [IO.File]::ReadAllText($source.FullName, $utf8)
    $text = [Text.RegularExpressions.Regex]::Replace($text, '(?<!\r)\n', "`r`n")

    [IO.File]::WriteAllText($target.FullName, $text, $cp1251)
    Write-Host "Installed $relativeTarget"
}
