$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$selectedLines = @(
    4, 5, 6, 8, 9, 13, 14, 15, 18, 19, 23, 24, 25, 29, 33, 34, 35, 36,
    39, 40, 41, 44, 48, 49, 50, 55, 56, 60, 61, 62, 66, 67, 68, 69, 73, 74,
    76, 77, 78, 80, 85, 86, 87, 89, 94, 95, 96, 100, 101, 104
)

$readme = Join-Path $patchRoot 'README.md'
$manageMsg = Join-Path $scriptRoot 'manage_msg_translations.ps1'
$installMsg = Join-Path $scriptRoot 'install_msg_translations.ps1'
$installMainMenu = Join-Path $scriptRoot 'install_main_menu.ps1'
$patchExe = Join-Path $scriptRoot 'patch_msg_parser.ps1'
$msgTool = Join-Path $patchRoot 'tools\msg_tool.py'
$originalMsg = Join-Path $patchRoot 'backup\missions\MIS01\BLU\MSG\MIS01BLU.ENG'
$translationMsg = Join-Path $patchRoot 'translations\MIS01_BLU_MSG_MIS01BLU.utf8.txt'
$installedMsg = Join-Path $gameRoot 'data\missions\MIS01\BLU\MSG\MIS01BLU.ENG'
$originalCrk = Join-Path $patchRoot 'backup\L_ENGLIS.original.CRK'
$installedCrk = Join-Path $gameRoot 'data\CRK\L_ENGLIS.CRK'
$installedSmallFont = Join-Path $gameRoot 'data\CORS1.F32'
$missionTranslations = Join-Path $patchRoot 'translations'
$missionBackupRoot = Join-Path $patchRoot 'backup\missions'
$missionsRoot = Join-Path $gameRoot 'data\missions'
$executable = Join-Path $gameRoot 'corsairs.exe'
$executableBackup = Join-Path $patchRoot 'backup\corsairs.msg-parser-original.exe'

$requiredFiles = @(
    $readme,
    $manageMsg,
    $installMsg,
    $installMainMenu,
    $patchExe,
    $msgTool,
    $originalMsg,
    $translationMsg,
    $installedMsg,
    $originalCrk,
    $installedCrk,
    $installedSmallFont,
    $executable,
    $executableBackup
)
foreach ($path in $requiredFiles) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

$expectedOriginalExeHash = '93FD792E80EC085F36BE814A4A244E96FDCB32CE3010F7B91064836C7FC02FE2'
$expectedPatchedExeHash = '2070286F84C78EDC7C6BC70CC774293EAD36B4BB3B5E5C76860BE1EF231824F4'
$patchOffset = 0x2BC7D
$patchedByte = 0x72

$backupExeHash = (Get-FileHash -LiteralPath $executableBackup -Algorithm SHA256).Hash
if ($backupExeHash -ne $expectedOriginalExeHash) {
    throw "Unexpected executable backup hash: $backupExeHash"
}
$exeHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
if ($exeHash -ne $expectedPatchedExeHash) {
    throw "The MSG parser executable patch is not installed: $exeHash"
}
$exeBytes = [IO.File]::ReadAllBytes($executable)
if ($exeBytes[$patchOffset] -ne $patchedByte) {
    throw ("Unexpected executable byte 0x{0:X2} at offset 0x{1:X}." -f $exeBytes[$patchOffset], $patchOffset)
}

function Get-ByteHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Test-Crlf([byte[]]$Bytes, [string]$Path) {
    $count = 0
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 13) {
            if ($i + 1 -ge $Bytes.Length -or $Bytes[$i + 1] -ne 10) {
                throw "$Path contains a standalone CR byte."
            }
        }
        elseif ($Bytes[$i] -eq 10) {
            if ($i -eq 0 -or $Bytes[$i - 1] -ne 13) {
                throw "$Path contains a standalone LF byte."
            }
            $count++
        }
    }
    if ($Bytes.Length -lt 2 -or $Bytes[$Bytes.Length - 2] -ne 13 -or $Bytes[$Bytes.Length - 1] -ne 10) {
        throw "$Path does not end with CRLF."
    }
    return $count
}

$cp1251 = [Text.Encoding]::GetEncoding(1251)
$utf8 = New-Object Text.UTF8Encoding($false, $true)

function Read-CrkText([string]$Path) {
    $encodedBytes = [IO.File]::ReadAllBytes($Path)
    $decodedBytes = [byte[]]::new($encodedBytes.Length)
    for ($i = 0; $i -lt $encodedBytes.Length; $i++) {
        $decodedBytes[$i] = ($encodedBytes[$i] - 127) -band 0xFF
    }
    return $cp1251.GetString($decodedBytes)
}

$originalCrkText = Read-CrkText $originalCrk
$installedCrkText = Read-CrkText $installedCrk
$installedCrkHash = (Get-FileHash -LiteralPath $installedCrk -Algorithm SHA256).Hash
$messagesEnglish = 'Messages.'
$messagesRussian = $cp1251.GetString([byte[]]@(0xD1,0xEE,0xEE,0xE1,0xF9,0xE5,0xED,0xE8,0xFF,0x2E))
$targetsRussian = $cp1251.GetString([byte[]]@(0xD6,0xE5,0xEB,0xE8,0x2E))
$installerSource = [IO.File]::ReadAllText($installMainMenu, [Text.Encoding]::ASCII)
$installerTranslations = [ordered]@{}
$installerPattern = "(?m)^\s*'(?<key>[^']+)'\s*=\s*From-Cp1251\s+@\((?<bytes>[^)]*)\)"
foreach ($match in [regex]::Matches($installerSource, $installerPattern)) {
    [byte[]]$valueBytes = @(
        [regex]::Matches($match.Groups['bytes'].Value, '0x[0-9A-Fa-f]{2}') |
            ForEach-Object { [Convert]::ToByte($_.Value.Substring(2), 16) }
    )
    $installerTranslations[$match.Groups['key'].Value] = $cp1251.GetString($valueBytes)
}

$originalMessagesPattern = '(?m)^086[ \t]*=[ \t]*' + [regex]::Escape($messagesEnglish) + '[ \t]*\r?$'
$installedMessagesPattern = '(?m)^086[ \t]*=[ \t]*' + [regex]::Escape($messagesRussian) + '[ \t]*\r?$'
$installedTargetsPattern = '(?m)^088[ \t]*=[ \t]*' + [regex]::Escape($targetsRussian) + '[ \t]*\r?$'
if ([regex]::Matches($originalCrkText, $originalMessagesPattern).Count -ne 1) {
    throw 'Original CRK does not contain exactly one 086 = Messages. record.'
}
if ([regex]::Matches($installedCrkText, $installedMessagesPattern).Count -ne 1) {
    throw 'Installed CRK does not contain the translated record 086.'
}
if ([regex]::Matches($installedCrkText, $installedTargetsPattern).Count -ne 1) {
    throw 'Installed CRK does not contain the translated record 088.'
}
$smallFontKeys = @(
    '086', '088', 'CS_ACHAT', 'CS_VENTE', 'CS_REPARER', 'CS_CONSTRUIRE',
    'CS_RECRUTER', 'CS_UPGRADER', 'CS_LOWDETAILS', 'CS_HIGHDETAILS',
    'CS_ALLURE', 'CS_EQUIPAGE', 'CS_CANONS', 'CS_TONNAGE', 'CS_CHARPENTE',
    'CS_CALESECHE', 'CS_NIVEAU', 'CS_ETAT', 'CS_RAPIDITE',
    'CS_NOOTHERSHIPINTOWN', 'CS_ENNEMYSURRENDER', 'CS_YOURMENSURRENDER'
) + @(24..31 | ForEach-Object { '{0:D3}' -f $_ }) +
    @(65..97 | ForEach-Object { '{0:D3}' -f $_ })
$interfaceText = ''
foreach ($entry in $installerTranslations.GetEnumerator()) {
    $value = $entry.Value
    $pattern = '(?m)^' + [regex]::Escape($entry.Key) + '[ \t]*=[ \t]*' +
        [regex]::Escape($value) + '[ \t]*\r?$'
    $sourcePattern = '(?m)^' + [regex]::Escape($entry.Key) + '[ \t]*='
    $expectedCount = [regex]::Matches($originalCrkText, $sourcePattern).Count
    if ($expectedCount -lt 1) {
        throw "Installer record $($entry.Key) is absent from the original CRK."
    }
    if ([regex]::Matches($installedCrkText, $pattern).Count -ne $expectedCount) {
        throw "Installed CRK does not contain translated record $($entry.Key)."
    }
    if ($smallFontKeys -contains $entry.Key) { $interfaceText += $value }
}

$tutorialCertificateKeys = @(
    $installerTranslations.Keys |
        Where-Object { $_ -match '^CS_TUTORIAL[1-4]_L[1-6]$' }
)
if ($tutorialCertificateKeys.Count -ne 21) {
    throw "Expected 21 translated tutorial-certificate records, found $($tutorialCertificateKeys.Count)."
}
$surrenderKeys = @('CS_ENNEMYSURRENDER', 'CS_YOURMENSURRENDER')
foreach ($key in $surrenderKeys) {
    if (-not $installerTranslations.Contains($key)) {
        throw "Missing translated surrender record $key."
    }
}

# CORS1 is used for the panel heading. Every Cyrillic byte in the translated
# heading must have both a width and bitmap data in the installed font.
$smallFont = [IO.File]::ReadAllBytes($installedSmallFont)
function Read-FontBE16([int]$Offset) {
    return 256 * $smallFont[$Offset] + $smallFont[$Offset + 1]
}
function Read-FontBE32([int]$Offset) {
    return 16777216 * $smallFont[$Offset] + 65536 * $smallFont[$Offset + 1] +
        256 * $smallFont[$Offset + 2] + $smallFont[$Offset + 3]
}
$fontHeight = Read-FontBE16 8
$fontFirst = $smallFont[10]
$fontLast = $smallFont[11]
$fontWidths = Read-FontBE32 12
$fontBitmap = Read-FontBE32 16
$fontDeclaredLength = Read-FontBE32 4
$fontGlyphCount = $fontLast - $fontFirst + 1
if ($fontDeclaredLength -ne $smallFont.Length) {
    throw "CORS1 declared size differs from its file size."
}
if ($fontBitmap - $fontWidths -ne $fontGlyphCount) {
    throw "CORS1 width-table size differs from its character range."
}
if ($smallFont.Length - $fontBitmap -ne $fontGlyphCount * $fontHeight * 4) {
    throw "CORS1 bitmap size differs from its character range."
}
foreach ($code in @($cp1251.GetBytes($interfaceText) | Sort-Object -Unique)) {
    if ($code -lt 0x80) { continue }
    if ($code -lt $fontFirst -or $code -gt $fontLast) {
        throw ('CORS1 does not cover title byte 0x{0:X2}.' -f $code)
    }
    $glyphIndex = $code - $fontFirst
    if ($smallFont[$fontWidths + $glyphIndex] -eq 0) {
        throw ('CORS1 title glyph 0x{0:X2} has zero width.' -f $code)
    }
    $glyphStart = $fontBitmap + $glyphIndex * $fontHeight * 4
    $hasPixels = $false
    for ($i = $glyphStart; $i -lt $glyphStart + $fontHeight * 4; $i++) {
        if ($smallFont[$i] -ne 0) { $hasPixels = $true; break }
    }
    if (-not $hasPixels) {
        throw ('CORS1 title glyph 0x{0:X2} has no pixels.' -f $code)
    }
}

$originalBytes = [IO.File]::ReadAllBytes($originalMsg)
$installedBytes = [IO.File]::ReadAllBytes($installedMsg)
$originalCrlf = Test-Crlf $originalBytes $originalMsg
$installedCrlf = Test-Crlf $installedBytes $installedMsg
if ($originalCrlf -ne $installedCrlf) {
    throw "CRLF count differs: $installedCrlf installed != $originalCrlf original."
}

$originalText = $cp1251.GetString($originalBytes)
$installedText = $cp1251.GetString($installedBytes)
$originalLines = $originalText.Substring(0, $originalText.Length - 2) -split "`r`n"
$installedLines = $installedText.Substring(0, $installedText.Length - 2) -split "`r`n"

$translationText = [IO.File]::ReadAllText($translationMsg, $utf8).Replace("`r`n", "`n")
if ($translationText.Contains("`r")) {
    throw "$translationMsg contains a standalone CR character."
}
if (-not $translationText.EndsWith("`n")) {
    throw "$translationMsg must end with a newline."
}
$translationLines = $translationText.Substring(0, $translationText.Length - 1) -split "`n"
if ($translationLines.Count -ne $originalLines.Count) {
    throw "Translation line count differs from the original."
}

[string[]]$expectedLines = $originalLines.Clone()
$allowedAsciiText = @(
    'Saint Eustatius', 'Sainte Croix', 'Saint Croix', 'San Juan', 'Vieques',
    'Saint Martin', 'LE FRINGANT', 'Fortune', 'Chance', 'GP'
)
foreach ($lineNumber in $selectedLines) {
    $translatedLine = $translationLines[$lineNumber - 1]
    $asciiProbe = $translatedLine
    foreach ($allowedText in $allowedAsciiText) {
        $asciiProbe = $asciiProbe.Replace($allowedText, '')
    }
    if ($asciiProbe -cmatch '[A-Za-z]') {
        throw "Translated line $lineNumber contains unexpected ASCII letters."
    }
    if ($translatedLine.Length -ne $translatedLine.TrimEnd().Length) {
        throw "Translated line $lineNumber contains trailing whitespace."
    }
    $expectedLines[$lineNumber - 1] = $translatedLine
}

$expectedBytes = $cp1251.GetBytes(($expectedLines -join "`r`n") + "`r`n")
$expectedHash = Get-ByteHash $expectedBytes
$installedHash = Get-ByteHash $installedBytes
if ($installedHash -ne $expectedHash) {
    throw "Installed MSG differs from the selected lines of the translation source: $installedHash"
}

$changedLines = for ($i = 0; $i -lt $originalLines.Count; $i++) {
    if ($installedLines[$i] -cne $originalLines[$i]) { $i + 1 }
}
if (($changedLines -join ',') -ne ($selectedLines -join ',')) {
    throw "Unexpected installed MSG lines differ from the original: $($changedLines -join ',')"
}

$verifiedBooks = 0
foreach ($source in Get-ChildItem -LiteralPath $missionTranslations -File -Filter 'MIS*_INT*.utf8.txt') {
    if ($source.Name -notmatch '^(MIS\d+)_([A-Za-z]+)_INT(.+)\.utf8\.txt$') {
        throw "Unexpected mission-book translation name: $($source.Name)"
    }
    $mission = $Matches[1]
    $nation = $Matches[2]
    $targetName = 'INT' + $Matches[3] + '.ENG'
    $target = Join-Path $missionsRoot "$mission\$nation\INT\$targetName"
    $backup = Join-Path $missionBackupRoot "$mission\$nation\INT\$targetName"
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        throw "Installed mission book is missing: $target"
    }
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
        throw "Mission book backup is missing: $backup"
    }

    $sourceText = [IO.File]::ReadAllText($source.FullName, $utf8).Replace("`r`n", "`n")
    if ($sourceText.Contains([char]0x2014)) {
        throw "Mission book contains unsupported em dash U+2014: $($source.Name)"
    }
    if ($sourceText.Contains("`r")) {
        throw "$($source.FullName) contains a standalone CR character."
    }
    if (-not $sourceText.EndsWith("`n")) {
        throw "$($source.FullName) must end with a newline."
    }
    $sourceDirectives = @($sourceText -split "`n" | Where-Object { $_ -match '^>' })
    $backupText = $cp1251.GetString([IO.File]::ReadAllBytes($backup)).Replace("`r`n", "`n")
    $backupDirectives = @($backupText -split "`n" | Where-Object { $_ -match '^>' })
    if (($sourceDirectives -join "`n") -cne ($backupDirectives -join "`n")) {
        throw "Mission book directives differ from the original: $($source.Name)"
    }
    if ($sourceDirectives.Count -eq 0 -or $sourceDirectives[-1] -cne '>B.') {
        throw "Mission book does not end with the >B. directive: $($source.Name)"
    }

    $expectedBookBytes = $cp1251.GetBytes($sourceText.Replace("`n", "`r`n"))
    $installedBookBytes = [IO.File]::ReadAllBytes($target)
    [void](Test-Crlf $installedBookBytes $target)
    if ((Get-ByteHash $installedBookBytes) -ne (Get-ByteHash $expectedBookBytes)) {
        throw "Installed mission book differs from its translation source: $target"
    }
    $verifiedBooks++
}

$verifiedMissionMessages = 0
foreach ($source in Get-ChildItem -LiteralPath $missionTranslations -File -Filter 'MIS*_MSG_*.utf8.txt') {
    if ($source.Name -notmatch '^(MIS\d+)_([A-Za-z]+)_MSG_(.+)\.utf8\.txt$') {
        throw "Unexpected mission-message translation name: $($source.Name)"
    }
    $mission = $Matches[1]
    $nation = $Matches[2]
    $targetName = $Matches[3] + '.ENG'
    $nationDirectory = Get-ChildItem -LiteralPath (Join-Path $missionsRoot $mission) -Directory |
        Where-Object { $_.Name -ieq $nation } |
        Select-Object -First 1
    $msgDirectory = Get-ChildItem -LiteralPath $nationDirectory.FullName -Directory |
        Where-Object { $_.Name -ieq 'MSG' } |
        Select-Object -First 1
    $target = Get-ChildItem -LiteralPath $msgDirectory.FullName -File |
        Where-Object { $_.Name -ieq $targetName } |
        Select-Object -First 1
    $relativeTarget = $target.FullName.Substring($missionsRoot.Length).TrimStart('\')
    $backup = Join-Path $missionBackupRoot $relativeTarget
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
        throw "Mission MSG backup is missing: $backup"
    }

    $sourceText = [IO.File]::ReadAllText($source.FullName, $utf8).Replace("`r`n", "`n")
    if ($sourceText.Contains([char]0x2014)) {
        throw "Mission MSG contains unsupported em dash U+2014: $($source.Name)"
    }
    if ($sourceText.Contains("`r") -or -not $sourceText.EndsWith("`n")) {
        throw "Mission MSG source has invalid line endings: $($source.Name)"
    }
    $sourceLines = $sourceText.Substring(0, $sourceText.Length - 1) -split "`n"
    $backupBytes = [IO.File]::ReadAllBytes($backup)
    [void](Test-Crlf $backupBytes $backup)
    $backupText = $cp1251.GetString($backupBytes)
    $backupLines = $backupText.Substring(0, $backupText.Length - 2) -split "`r`n"
    if ($sourceLines.Count -ne $backupLines.Count) {
        throw "Mission MSG line count differs from original: $($source.Name)"
    }
    for ($i = 0; $i -lt $sourceLines.Count; $i++) {
        $isSourceStructure = $sourceLines[$i] -match '^\[[^\]]+\]$|^(ACTIVATION|REALIZATION|FAILURE)\s*=$'
        $isBackupStructure = $backupLines[$i] -match '^\[[^\]]+\]$|^(ACTIVATION|REALIZATION|FAILURE)\s*=$'
        if (($isSourceStructure -or $isBackupStructure) -and $sourceLines[$i] -cne $backupLines[$i]) {
            throw "Mission MSG structural line $($i + 1) differs from original: $($source.Name)"
        }
    }

    $expectedMsgBytes = $cp1251.GetBytes($sourceText.Replace("`n", "`r`n"))
    $installedMissionMsgBytes = [IO.File]::ReadAllBytes($target.FullName)
    [void](Test-Crlf $installedMissionMsgBytes $target.FullName)
    if ((Get-ByteHash $installedMissionMsgBytes) -ne (Get-ByteHash $expectedMsgBytes)) {
        throw "Installed mission MSG differs from its translation source: $($target.FullName)"
    }
    $verifiedMissionMessages++
}

& $manageMsg -Mode SelfTest
if ($LASTEXITCODE -ne 0) {
    throw "MSG self-test failed with exit code $LASTEXITCODE"
}

Write-Host 'Translation workspace verification: OK'
Write-Host "Patched executable SHA-256: $exeHash"
Write-Host "Installed MSG SHA-256:      $installedHash"
Write-Host "Installed CRK SHA-256:      $installedCrkHash"
Write-Host "Installed MSG bytes:        $($installedBytes.Length)"
Write-Host "CRLF records:               $installedCrlf"
Write-Host "Translated physical lines:  $($selectedLines -join ', ')"
Write-Host "Verified mission books:     $verifiedBooks"
Write-Host "Verified mission messages:  $verifiedMissionMessages"
Write-Host "Interface record 086:       $messagesRussian"
Write-Host "Interface record 088:       $targetsRussian"
Write-Host 'City interface records:     labels and contextual help 065-097'
Write-Host "Tutorial certificate lines: $($tutorialCertificateKeys.Count)"
Write-Host "Surrender prompts:          $($surrenderKeys.Count)"
