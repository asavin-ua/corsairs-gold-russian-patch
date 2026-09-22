param(
    [string]$GamePath
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = Join-Path $packageRoot 'Sources'

function Get-GameRoot([string]$Path) {
    if (-not $Path) { $Path = Read-Host 'Enter the Corsairs Gold folder (the folder containing corsairs.exe)' }
    $resolved = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path.Trim('"'))).TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $resolved 'corsairs.exe') -PathType Leaf)) {
        throw "corsairs.exe was not found at: $resolved"
    }
    return $resolved
}

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "The Sources folder is missing: $sourceRoot"
}

$gameRoot = Get-GameRoot $GamePath
$workspace = Join-Path $gameRoot 'Russian_Patch'
if (Test-Path -LiteralPath $workspace) {
    throw "A Russian_Patch workspace already exists: $workspace"
}

Copy-Item -LiteralPath $sourceRoot -Destination $workspace -Recurse
Copy-Item -LiteralPath (Join-Path $packageRoot 'README.md') -Destination (Join-Path $workspace 'README.md')
Copy-Item -LiteralPath (Join-Path $packageRoot 'AGENTS.md') -Destination (Join-Path $workspace 'AGENTS.md')

Write-Host "Translation workspace prepared: $workspace"
Write-Host 'Edit UTF-8 files in Russian_Patch\translations, then run scripts\install_edited_translations.ps1.'
