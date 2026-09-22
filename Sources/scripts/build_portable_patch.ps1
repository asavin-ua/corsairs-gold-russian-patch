param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$templateRoot = Join-Path $patchRoot 'portable'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $patchRoot 'releases' }
$releaseName = 'Corsairs_Gold_Russian_Patch_1.0_2026-09-13'
$stagingRoot = Join-Path $OutputDirectory $releaseName
$obsoleteArchivePath = Join-Path $OutputDirectory ($releaseName + '.zip')

if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
if (Test-Path -LiteralPath $obsoleteArchivePath) { Remove-Item -LiteralPath $obsoleteArchivePath -Force }
[IO.Directory]::CreateDirectory($stagingRoot) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $stagingRoot 'payload')) | Out-Null

foreach ($name in @('Install-RussianPatch.ps1', 'Install_Russian_Patch.cmd', 'Install_With_Backup.cmd', 'Verify_Russian_Patch.cmd', 'Uninstall_Russian_Patch.cmd', 'Prepare-TranslationWorkspace.ps1', 'Prepare_Translation_Workspace.cmd')) {
    Copy-Item -LiteralPath (Join-Path $templateRoot $name) -Destination (Join-Path $stagingRoot $name)
}
Copy-Item -LiteralPath (Join-Path $templateRoot 'release_README.template.md') -Destination (Join-Path $stagingRoot 'README.md')
Copy-Item -LiteralPath (Join-Path $templateRoot 'release_AGENTS.template.md') -Destination (Join-Path $stagingRoot 'AGENTS.md')
foreach ($name in @('.gitignore', '.gitattributes')) {
    Copy-Item -LiteralPath (Join-Path $patchRoot $name) -Destination (Join-Path $stagingRoot $name)
}

$sourceReleaseRoot = Join-Path $stagingRoot 'Sources'
[IO.Directory]::CreateDirectory($sourceReleaseRoot) | Out-Null
foreach ($directoryName in @('translations', 'scripts', 'tools', 'portable')) {
    Copy-Item -LiteralPath (Join-Path $patchRoot $directoryName) -Destination (Join-Path $sourceReleaseRoot $directoryName) -Recurse
}
foreach ($documentName in @('CONTRIBUTING.md', '.gitignore', '.gitattributes')) {
    Copy-Item -LiteralPath (Join-Path $patchRoot $documentName) -Destination (Join-Path $sourceReleaseRoot $documentName)
}
[IO.Directory]::CreateDirectory((Join-Path $sourceReleaseRoot 'docs')) | Out-Null
Copy-Item -LiteralPath (Join-Path $patchRoot 'docs\TRANSLATION_TECHNICAL_NOTES.md') -Destination (Join-Path $sourceReleaseRoot 'docs\TRANSLATION_TECHNICAL_NOTES.md')

$relativeFiles = [Collections.Generic.List[string]]::new()
foreach ($relative in @('data\CRK\L_ENGLIS.CRK', 'data\CORS1.F32', 'data\CORS3.F32', 'data\BOOK.F32')) {
    $relativeFiles.Add($relative)
}

foreach ($source in Get-ChildItem -LiteralPath (Join-Path $patchRoot 'translations') -File -Filter '*.utf8.txt') {
    if ($source.Name -match '^(MIS\d+)_([A-Za-z]+)_INT(.+)\.utf8\.txt$') {
        $directory = Join-Path $gameRoot "data\missions\$($Matches[1])\$($Matches[2])\INT"
        $wantedName = 'INT' + $Matches[3] + '.ENG'
    }
    elseif ($source.Name -match '^(MIS\d+)_([A-Za-z]+)_MSG_(.+)\.utf8\.txt$') {
        $directory = Join-Path $gameRoot "data\missions\$($Matches[1])\$($Matches[2])\MSG"
        $wantedName = $Matches[3] + '.ENG'
    }
    else { continue }
    $target = Get-ChildItem -LiteralPath $directory -File | Where-Object { $_.Name -ieq $wantedName } | Select-Object -First 1
    if (-not $target) { throw "Installed translated target was not found for $($source.Name)" }
    $relativeFiles.Add($target.FullName.Substring($gameRoot.Length).TrimStart('\'))
}

if ($relativeFiles.Count -ne 112) { throw "Expected 112 payload resources, found $($relativeFiles.Count)." }
$records = [Collections.Generic.List[object]]::new()
foreach ($relative in $relativeFiles) {
    $source = Join-Path $gameRoot $relative
    $destination = Join-Path (Join-Path $stagingRoot 'payload') $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    $records.Add([pscustomobject]@{
        Path = $relative
        Size = (Get-Item -LiteralPath $destination).Length
        Sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToUpperInvariant()
    })
}

$manifest = [ordered]@{
    PatchVersion = '1.0'
    BuildDate = '2026-09-13'
    OriginalExecutableSha256 = '93FD792E80EC085F36BE814A4A244E96FDCB32CE3010F7B91064836C7FC02FE2'
    PatchedExecutableSha256 = '2070286F84C78EDC7C6BC70CC774293EAD36B4BB3B5E5C76860BE1EF231824F4'
    ExecutablePatchOffset = 0x2BC7D
    ExecutableOriginalByte = 0x7C
    ExecutablePatchedByte = 0x72
    Files = $records
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stagingRoot 'manifest.json') -Encoding UTF8

Write-Host "Portable release directory built: $stagingRoot"
Write-Host "Payload resources:   $($records.Count)"
