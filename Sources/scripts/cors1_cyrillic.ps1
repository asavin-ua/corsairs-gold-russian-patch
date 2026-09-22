$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$source = Join-Path $patchRoot 'backup\CORS1.original.F32'
$target = Join-Path $gameRoot 'data\CORS1.F32'
$font = [IO.File]::ReadAllBytes($source)

function Read-BE16([int]$offset) { return 256 * $font[$offset] + $font[$offset + 1] }
function Read-BE32([int]$offset) {
    return 16777216 * $font[$offset] + 65536 * $font[$offset + 1] +
        256 * $font[$offset + 2] + $font[$offset + 3]
}
function Write-BE32([int]$offset, [int]$value) {
    $font[$offset] = ($value -shr 24) -band 0xFF
    $font[$offset + 1] = ($value -shr 16) -band 0xFF
    $font[$offset + 2] = ($value -shr 8) -band 0xFF
    $font[$offset + 3] = $value -band 0xFF
}

$height = Read-BE16 8
$first = $font[10]
$last = $font[11]
$widths = Read-BE32 12
$bitmap = Read-BE32 16
$glyphSize = $height * 4

# The original font stops at CP1251 0xE1. Extend its contiguous character
# range through 0xFF so lowercase Cyrillic glyphs can be addressed normally.
$targetLast = 0xFF
if ($last -lt $targetLast) {
    $extraGlyphs = $targetLast - $last
    $oldBitmap = $bitmap
    $expandedBitmap = $oldBitmap + $extraGlyphs
    $expanded = [byte[]]::new($font.Length + $extraGlyphs + $extraGlyphs * $glyphSize)
    [Array]::Copy($font, 0, $expanded, 0, $oldBitmap)
    [Array]::Copy($font, $oldBitmap, $expanded, $expandedBitmap, $font.Length - $oldBitmap)
    $font = $expanded
    $last = $targetLast
    $bitmap = $expandedBitmap
    $font[11] = $last
    Write-BE32 4 $font.Length
    Write-BE32 16 $bitmap
}

function Copy-Glyph([int]$sourceCode, [int]$destinationCode) {
    if ($destinationCode -gt $last) { throw 'Destination is outside CORS1 range.' }
    $sourceIndex = $sourceCode - $first
    $destinationIndex = $destinationCode - $first
    $font[$widths + $destinationIndex] = $font[$widths + $sourceIndex]
    [Array]::Copy($font, $bitmap + $sourceIndex * $glyphSize,
        $font, $bitmap + $destinationIndex * $glyphSize, $glyphSize)
}

function Get-Row([int]$code, [int]$row) {
    return [BitConverter]::ToUInt32($font,
        $bitmap + ($code - $first) * $glyphSize + $row * 4)
}

function Set-Row([int]$code, [int]$row, [uint32]$value) {
    $bytes = [BitConverter]::GetBytes($value)
    [Array]::Copy($bytes, 0, $font,
        $bitmap + ($code - $first) * $glyphSize + $row * 4, 4)
}

function Pixel-Mask([int]$x) { return [uint32]([uint64]1 -shl (31 - $x)) }

function Set-RowPixels([int]$code, [int]$row, [int[]]$pixels) {
    [uint32]$value = 0
    foreach ($x in $pixels) { $value = $value -bor (Pixel-Mask $x) }
    Set-Row $code $row $value
}

function Keep-XRange([int]$code, [int]$row, [int]$minimumX, [int]$maximumX) {
    $source = Get-Row $code $row
    [uint32]$value = 0
    for ($x = $minimumX; $x -le $maximumX; $x++) {
        if (($source -band (Pixel-Mask $x)) -ne 0) {
            $value = $value -bor (Pixel-Mask $x)
        }
    }
    Set-Row $code $row $value
}

function Mirror-Glyph([int]$sourceCode, [int]$destinationCode, [int]$mirrorRight) {
    $font[$widths + ($destinationCode - $first)] = $font[$widths + ($sourceCode - $first)]
    for ($row = 0; $row -lt $height; $row++) {
        $source = Get-Row $sourceCode $row
        [uint32]$value = 0
        for ($x = 0; $x -le $mirrorRight; $x++) {
            if (($source -band (Pixel-Mask $x)) -ne 0) {
                $value = $value -bor (Pixel-Mask ($mirrorRight - $x))
            }
        }
        Set-Row $destinationCode $row $value
    }
}

# Directly reusable uppercase shapes.
Copy-Glyph 0x41 0xC0 # А
Copy-Glyph 0x42 0xC2 # В
Copy-Glyph 0x45 0xC5 # Е
Copy-Glyph 0x4B 0xCA # К
Copy-Glyph 0x4D 0xCC # М
Copy-Glyph 0x48 0xCD # Н
Copy-Glyph 0x4F 0xCE # О
Copy-Glyph 0x50 0xD0 # Р
Copy-Glyph 0x43 0xD1 # С
Copy-Glyph 0x54 0xD2 # Т
Copy-Glyph 0x58 0xD5 # Х

# Г from F without its middle bar; З from numeral 3.
Copy-Glyph 0x46 0xC3
Keep-XRange 0xC3 4 0 2
Copy-Glyph 0x33 0xC7

# Б keeps B's lower bowl but uses a straight upper stem.
Copy-Glyph 0x42 0xC1
for ($row = 2; $row -le 4; $row++) { Keep-XRange 0xC1 $row 0 2 }

# Д is based on A and receives the characteristic base and short feet.
Copy-Glyph 0x41 0xC4
Set-RowPixels 0xC4 9 (0..10)
Set-RowPixels 0xC4 10 @(0, 1, 9, 10)
$font[$widths + (0xC4 - $first)] = 11

# Ж is X with a central vertical stem.
Copy-Glyph 0x58 0xC6
for ($row = 1; $row -le 8; $row++) {
    $value = Get-Row 0xC6 $row
    Set-Row 0xC6 $row ($value -bor (Pixel-Mask 4))
}

# П has a straight top bar and two vertical stems.
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xCF $row 0 }
Set-RowPixels 0xCF 1 (0..7)
for ($row = 2; $row -le 8; $row++) { Set-RowPixels 0xCF $row @(0, 1, 6, 7) }
$font[$widths + (0xCF - $first)] = 8

# Щ uses three vertical stems, a common bottom bar and a short right tail.
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xD9 $row 0 }
for ($row = 1; $row -le 7; $row++) {
    Set-RowPixels 0xD9 $row @(0, 1, 4, 5, 8, 9)
}
Set-RowPixels 0xD9 8 (0..11)
Set-RowPixels 0xD9 9 @(10, 11)
Set-RowPixels 0xD9 10 @(10, 11)
$font[$widths + (0xD9 - $first)] = 12

# Ц is a U-shaped glyph with a short descender.
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xD6 $row 0 }
for ($row = 1; $row -le 7; $row++) { Set-RowPixels 0xD6 $row @(0, 1, 6, 7) }
Set-RowPixels 0xD6 8 (0..9)
Set-RowPixels 0xD6 9 @(8, 9)
Set-RowPixels 0xD6 10 @(8, 9)
$font[$widths + (0xD6 - $first)] = 10

# Ч
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xD7 $row 0 }
for ($row = 1; $row -le 4; $row++) { Set-RowPixels 0xD7 $row @(0, 1, 6, 7) }
Set-RowPixels 0xD7 5 (0..7)
for ($row = 6; $row -le 8; $row++) { Set-RowPixels 0xD7 $row @(6, 7) }
$font[$widths + (0xD7 - $first)] = 8

# Ш
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xD8 $row 0 }
for ($row = 1; $row -le 7; $row++) { Set-RowPixels 0xD8 $row @(0, 1, 4, 5, 8, 9) }
Set-RowPixels 0xD8 8 (0..9)
$font[$widths + (0xD8 - $first)] = 10

# Э
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xDD $row 0 }
Set-RowPixels 0xDD 1 (1..6)
Set-RowPixels 0xDD 2 @(0, 1, 6, 7)
for ($row = 3; $row -le 4; $row++) { Set-RowPixels 0xDD $row @(6, 7) }
Set-RowPixels 0xDD 5 (2..7)
for ($row = 6; $row -le 7; $row++) { Set-RowPixels 0xDD $row @(6, 7) }
Set-RowPixels 0xDD 8 (1..6)
$font[$widths + (0xDD - $first)] = 8

# Lowercase glyphs required by the sentence-case panel headings.
Copy-Glyph 0x61 0xE0 # а
Copy-Glyph 0x6F 0xEE # о
Copy-Glyph 0x65 0xE5 # е
Copy-Glyph 0x6B 0xEA # к
Copy-Glyph 0x6D 0xEC # м
Copy-Glyph 0x70 0xF0 # р
Copy-Glyph 0x63 0xF1 # с
Copy-Glyph 0x79 0xF3 # у
Copy-Glyph 0x78 0xF5 # х

# б
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xE1 $row 0 }
Set-RowPixels 0xE1 2 (1..6)
Set-RowPixels 0xE1 3 @(0, 1)
Set-RowPixels 0xE1 4 (0..5)
for ($row = 5; $row -le 7; $row++) { Set-RowPixels 0xE1 $row @(0, 1, 5, 6) }
Set-RowPixels 0xE1 8 (1..5)
$font[$widths + (0xE1 - $first)] = 7

# н
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xED $row 0 }
for ($row = 3; $row -le 8; $row++) { Set-RowPixels 0xED $row @(0, 1, 5, 6) }
Set-RowPixels 0xED 5 (0..6)
$font[$widths + (0xED - $first)] = 7

# и
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xE8 $row 0 }
Set-RowPixels 0xE8 3 @(0, 1, 5, 6)
Set-RowPixels 0xE8 4 @(0, 1, 4, 5, 6)
Set-RowPixels 0xE8 5 @(0, 1, 3, 4, 5, 6)
Set-RowPixels 0xE8 6 @(0, 1, 2, 3, 5, 6)
for ($row = 7; $row -le 8; $row++) { Set-RowPixels 0xE8 $row @(0, 1, 5, 6) }
$font[$widths + (0xE8 - $first)] = 7

# л
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xEB $row 0 }
Set-RowPixels 0xEB 3 @(3, 4, 5, 6)
Set-RowPixels 0xEB 4 @(2, 3, 5, 6)
for ($row = 5; $row -le 6; $row++) { Set-RowPixels 0xEB $row @(1, 2, 5, 6) }
for ($row = 7; $row -le 8; $row++) { Set-RowPixels 0xEB $row @(0, 1, 5, 6) }
$font[$widths + (0xEB - $first)] = 7

# щ
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xF9 $row 0 }
for ($row = 3; $row -le 7; $row++) { Set-RowPixels 0xF9 $row @(0, 1, 4, 5, 8, 9) }
Set-RowPixels 0xF9 8 (0..11)
Set-RowPixels 0xF9 9 @(10, 11)
Set-RowPixels 0xF9 10 @(10, 11)
$font[$widths + (0xF9 - $first)] = 12

# я
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xFF $row 0 }
Set-RowPixels 0xFF 3 (1..6)
for ($row = 4; $row -le 5; $row++) { Set-RowPixels 0xFF $row @(0, 1, 5, 6) }
Set-RowPixels 0xFF 6 (1..6)
Set-RowPixels 0xFF 7 @(1, 2, 4, 5, 6)
Set-RowPixels 0xFF 8 @(0, 1, 5, 6)
$font[$widths + (0xFF - $first)] = 7

# в
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xE2 $row 0 }
Set-RowPixels 0xE2 3 (0..5)
Set-RowPixels 0xE2 4 @(0, 1, 5, 6)
Set-RowPixels 0xE2 5 (0..5)
for ($row = 6; $row -le 7; $row++) { Set-RowPixels 0xE2 $row @(0, 1, 5, 6) }
Set-RowPixels 0xE2 8 (0..5)
$font[$widths + (0xE2 - $first)] = 7

# г
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xE3 $row 0 }
Set-RowPixels 0xE3 3 (0..5)
for ($row = 4; $row -le 8; $row++) { Set-RowPixels 0xE3 $row @(0, 1) }
$font[$widths + (0xE3 - $first)] = 6

# д
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xE4 $row 0 }
Set-RowPixels 0xE4 3 @(3, 4, 5, 6)
Set-RowPixels 0xE4 4 @(2, 3, 5, 6)
for ($row = 5; $row -le 7; $row++) { Set-RowPixels 0xE4 $row @(1, 2, 5, 6) }
Set-RowPixels 0xE4 8 (0..8)
Set-RowPixels 0xE4 9 @(0, 1, 7, 8)
$font[$widths + (0xE4 - $first)] = 9

# ё is е with a diaeresis.
Copy-Glyph 0xE5 0xB8
Set-RowPixels 0xB8 1 @(1, 4)

# ж
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xE6 $row 0 }
Set-RowPixels 0xE6 3 @(0, 1, 4, 5, 8, 9)
Set-RowPixels 0xE6 4 @(1, 2, 4, 5, 7, 8)
Set-RowPixels 0xE6 5 (2..7)
Set-RowPixels 0xE6 6 (2..7)
Set-RowPixels 0xE6 7 @(1, 2, 4, 5, 7, 8)
Set-RowPixels 0xE6 8 @(0, 1, 4, 5, 8, 9)
$font[$widths + (0xE6 - $first)] = 10

# з
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xE7 $row 0 }
Set-RowPixels 0xE7 3 (1..5)
Set-RowPixels 0xE7 4 @(0, 1, 5, 6)
Set-RowPixels 0xE7 5 (3..6)
Set-RowPixels 0xE7 6 (3..6)
Set-RowPixels 0xE7 7 @(0, 1, 5, 6)
Set-RowPixels 0xE7 8 (1..5)
$font[$widths + (0xE7 - $first)] = 7

# й is и with a breve.
Copy-Glyph 0xE8 0xE9
Set-RowPixels 0xE9 1 @(1, 5)
Set-RowPixels 0xE9 2 (2..4)

# п
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xEF $row 0 }
Set-RowPixels 0xEF 3 (0..6)
for ($row = 4; $row -le 8; $row++) { Set-RowPixels 0xEF $row @(0, 1, 5, 6) }
$font[$widths + (0xEF - $first)] = 7

# т
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xF2 $row 0 }
Set-RowPixels 0xF2 3 (0..6)
for ($row = 4; $row -le 8; $row++) { Set-RowPixels 0xF2 $row @(2, 3, 4) }
$font[$widths + (0xF2 - $first)] = 7

# ч
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xF7 $row 0 }
for ($row = 3; $row -le 5; $row++) { Set-RowPixels 0xF7 $row @(0, 1, 5, 6) }
Set-RowPixels 0xF7 6 (0..6)
for ($row = 7; $row -le 8; $row++) { Set-RowPixels 0xF7 $row @(5, 6) }
$font[$widths + (0xF7 - $first)] = 7

# ш
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xF8 $row 0 }
for ($row = 3; $row -le 7; $row++) { Set-RowPixels 0xF8 $row @(0, 1, 4, 5, 8, 9) }
Set-RowPixels 0xF8 8 (0..9)
$font[$widths + (0xF8 - $first)] = 10

# ь
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xFC $row 0 }
for ($row = 3; $row -le 5; $row++) { Set-RowPixels 0xFC $row @(0, 1) }
Set-RowPixels 0xFC 6 (0..5)
Set-RowPixels 0xFC 7 @(0, 1, 5, 6)
Set-RowPixels 0xFC 8 (0..5)
$font[$widths + (0xFC - $first)] = 7

# ц
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xF6 $row 0 }
for ($row = 3; $row -le 7; $row++) { Set-RowPixels 0xF6 $row @(0, 1, 5, 6) }
Set-RowPixels 0xF6 8 (0..8)
Set-RowPixels 0xF6 9 @(7, 8)
$font[$widths + (0xF6 - $first)] = 9

# ъ
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xFA $row 0 }
Set-RowPixels 0xFA 3 (0..4)
for ($row = 4; $row -le 5; $row++) { Set-RowPixels 0xFA $row @(2, 3) }
Set-RowPixels 0xFA 6 (2..7)
Set-RowPixels 0xFA 7 @(2, 3, 7, 8)
Set-RowPixels 0xFA 8 (2..7)
$font[$widths + (0xFA - $first)] = 9

# ы
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xFB $row 0 }
for ($row = 3; $row -le 5; $row++) { Set-RowPixels 0xFB $row @(0, 1, 8, 9) }
Set-RowPixels 0xFB 6 @(0, 1, 2, 3, 4, 5, 8, 9)
Set-RowPixels 0xFB 7 @(0, 1, 5, 6, 8, 9)
Set-RowPixels 0xFB 8 @(0, 1, 2, 3, 4, 5, 8, 9)
$font[$widths + (0xFB - $first)] = 10

# э
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xFD $row 0 }
Set-RowPixels 0xFD 3 (1..5)
Set-RowPixels 0xFD 4 @(0, 1, 5, 6)
Set-RowPixels 0xFD 5 (3..6)
Set-RowPixels 0xFD 6 (3..6)
Set-RowPixels 0xFD 7 @(0, 1, 5, 6)
Set-RowPixels 0xFD 8 (1..5)
$font[$widths + (0xFD - $first)] = 7

# ю
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xFE $row 0 }
Set-RowPixels 0xFE 3 @(0, 1, 3, 4, 5, 6, 7)
for ($row = 4; $row -le 7; $row++) { Set-RowPixels 0xFE $row @(0, 1, 3, 4, 7, 8) }
Set-RowPixels 0xFE 5 (0..8)
Set-RowPixels 0xFE 8 @(0, 1, 3, 4, 5, 6, 7)
$font[$widths + (0xFE - $first)] = 9

# Я is a mirrored R.
Mirror-Glyph 0x52 0xDF 7

# И is a mirrored N.
Mirror-Glyph 0x4E 0xC8 6

# Й is И with a short upper mark.
Copy-Glyph 0xC8 0xC9
Set-RowPixels 0xC9 0 @(2, 3, 4)

# Л is A without the crossbar.
Copy-Glyph 0x41 0xCB
Set-Row 0xCB 6 (Get-Row 0x41 5)

# У starts from Y and receives a descending left hook.
Copy-Glyph 0x59 0xD3
Set-RowPixels 0xD3 6 @(3, 4)
Set-RowPixels 0xD3 7 @(2, 3, 4)
Set-RowPixels 0xD3 8 @(0, 1, 2, 3)

# Ь from B with its upper bowl removed; Ы adds a narrow I.
Copy-Glyph 0x42 0xDC
for ($row = 1; $row -le 4; $row++) { Keep-XRange 0xDC $row 0 2 }
Copy-Glyph 0xDC 0xDB
for ($row = 1; $row -le 8; $row++) {
    $value = Get-Row 0xDB $row
    $sourceI = Get-Row 0x49 $row
    for ($x = 0; $x -lt 10; $x++) {
        if (($sourceI -band (Pixel-Mask $x)) -ne 0) {
            $value = $value -bor (Pixel-Mask ($x + 9))
        }
    }
    Set-Row 0xDB $row $value
}
$font[$widths + (0xDB - $first)] = 13

[IO.File]::WriteAllBytes($target, $font)
Write-Host 'CORS1.F32 Cyrillic glyphs installed.'
