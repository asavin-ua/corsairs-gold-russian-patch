param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$sourceRoot = Join-Path $patchRoot 'translations'
$backupRoot = Join-Path $patchRoot 'backup\missions'
$missionsRoot = Join-Path $gameRoot 'data\missions'
$tool = Join-Path $patchRoot 'tools\msg_tool.py'

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
$pythonPrefix = @()
if (-not $pythonCommand) {
    $pythonCommand = Get-Command py -ErrorAction SilentlyContinue
    $pythonPrefix = @('-3')
}
if (-not $pythonCommand) {
    throw 'Python 3 was not found in PATH. Install Python for all users or add it to PATH.'
}

$sources = Get-ChildItem -LiteralPath $sourceRoot -File -Filter 'MIS*_MSG_*.utf8.txt'
foreach ($source in $sources) {
    if ($source.Name -notmatch '^(MIS\d+)_([A-Za-z]+)_MSG_(.+)\.utf8\.txt$') {
        throw "Unexpected MSG translation name: $($source.Name)"
    }

    $mission = $Matches[1]
    $nation = $Matches[2]
    $targetName = $Matches[3] + '.ENG'
    $missionDirectory = Join-Path $missionsRoot $mission
    $nationDirectory = Get-ChildItem -LiteralPath $missionDirectory -Directory |
        Where-Object { $_.Name -ieq $nation } |
        Select-Object -First 1
    if (-not $nationDirectory) {
        throw "Nation directory not found for $($source.Name)"
    }
    $msgDirectory = Get-ChildItem -LiteralPath $nationDirectory.FullName -Directory |
        Where-Object { $_.Name -ieq 'MSG' } |
        Select-Object -First 1
    if (-not $msgDirectory) {
        throw "MSG directory not found for $($source.Name)"
    }
    $target = Get-ChildItem -LiteralPath $msgDirectory.FullName -File |
        Where-Object { $_.Name -ieq $targetName } |
        Select-Object -First 1
    if (-not $target) {
        throw "Target MSG file not found for $($source.Name)"
    }

    $relativeTarget = $target.FullName.Substring($missionsRoot.Length).TrimStart('\')
    $backup = Join-Path $backupRoot $relativeTarget
    if (-not (Test-Path -LiteralPath $backup)) {
        $backupDirectory = Split-Path -Parent $backup
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        Copy-Item -LiteralPath $target.FullName -Destination $backup
    }

    $arguments = @(
        '--original', $backup,
        '--translation', $source.FullName,
        '--target', $target.FullName,
        'full'
    )
    if (-not $DryRun) {
        $arguments += @('--apply', '--acknowledge-experimental')
    }
    & $pythonCommand.Source @pythonPrefix $tool @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "MSG installation failed for $($source.Name) with exit code $LASTEXITCODE"
    }
}

Write-Host "Processed MSG translations: $($sources.Count)"
