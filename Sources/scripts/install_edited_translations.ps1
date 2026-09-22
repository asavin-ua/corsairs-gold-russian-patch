param(
    [string]$GamePath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$translations = Join-Path $patchRoot 'translations'
if (-not $GamePath) { $GamePath = Split-Path -Parent $patchRoot }
$gameRoot = [IO.Path]::GetFullPath($GamePath).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'corsairs.exe') -PathType Leaf)) {
    throw "corsairs.exe was not found at: $gameRoot"
}

$utf8 = [Text.UTF8Encoding]::new($false, $true)
$cp1251 = [Text.Encoding]::GetEncoding(1251, [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ExceptionFallback)
$installed = 0
foreach ($source in Get-ChildItem -LiteralPath $translations -File -Filter '*.utf8.txt') {
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
    if (-not $target) { throw "Game target was not found for: $($source.Name)" }
    $text = [IO.File]::ReadAllText($source.FullName, $utf8).Replace("`r`n", "`n")
    if ($text.Contains("`r") -or -not $text.EndsWith("`n")) { throw "Invalid source line endings: $($source.Name)" }
    if ($text.Contains([char]0x2014)) { throw "Unsupported em dash U+2014: $($source.Name)" }
    $bytes = $cp1251.GetBytes($text.Replace("`n", "`r`n"))
    [IO.File]::WriteAllBytes($target.FullName, $bytes)
    if ((Get-FileHash -LiteralPath $target.FullName -Algorithm SHA256).Hash -ne ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace('-', '')) {
        throw "Installed checksum failed: $($target.FullName)"
    }
    $installed++
}
if ($installed -ne 108) { throw "Expected 108 translation files, installed $installed." }
Write-Host "Edited translations installed: $installed UTF-8 sources converted to CP1251/CRLF."
