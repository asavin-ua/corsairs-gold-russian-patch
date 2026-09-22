$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$source = Join-Path $patchRoot 'backup\CORS3.original.F32'
$target = Join-Path $gameRoot 'data\CORS3.F32'

function Read-BigEndianUInt16([byte[]]$data, [int]$offset) {
    return 256 * $data[$offset] + $data[$offset + 1]
}

function Read-BigEndianUInt32([byte[]]$data, [int]$offset) {
    return 16777216 * $data[$offset] + 65536 * $data[$offset + 1] +
        256 * $data[$offset + 2] + $data[$offset + 3]
}

function Write-BigEndianUInt32([byte[]]$data, [int]$offset, [int]$value) {
    $data[$offset] = ($value -shr 24) -band 0xFF
    $data[$offset + 1] = ($value -shr 16) -band 0xFF
    $data[$offset + 2] = ($value -shr 8) -band 0xFF
    $data[$offset + 3] = $value -band 0xFF
}

$old = [IO.File]::ReadAllBytes($source)
if ([Text.Encoding]::ASCII.GetString($old, 0, 4) -ne 'FN32') {
    throw 'CORS3.F32 has an unexpected signature.'
}

$height = Read-BigEndianUInt16 $old 8
$firstCode = $old[10]
$oldLastCode = $old[11]
$newLastCode = 0xDF
$widthsOffset = Read-BigEndianUInt32 $old 12
$oldBitmapOffset = Read-BigEndianUInt32 $old 16
$oldCount = $oldLastCode - $firstCode + 1
$newCount = $newLastCode - $firstCode + 1
$glyphSize = $height * 4
$newBitmapOffset = $widthsOffset + $newCount
$newSize = $newBitmapOffset + $newCount * $glyphSize
$font = [byte[]]::new($newSize)

# Copy the header, original width table, and original bitmap blocks.
[Array]::Copy($old, 0, $font, 0, $widthsOffset)
[Array]::Copy($old, $widthsOffset, $font, $widthsOffset, $oldCount)
[Array]::Copy($old, $oldBitmapOffset, $font, $newBitmapOffset, $oldCount * $glyphSize)
$font[11] = $newLastCode
Write-BigEndianUInt32 $font 4 $newSize
Write-BigEndianUInt32 $font 16 $newBitmapOffset

function Copy-Glyph([int]$sourceCode, [int]$destinationCode) {
    $sourceIndex = $sourceCode - $firstCode
    $destinationIndex = $destinationCode - $firstCode
    $font[$widthsOffset + $destinationIndex] = $font[$widthsOffset + $sourceIndex]
    [Array]::Copy(
        $font, $newBitmapOffset + $sourceIndex * $glyphSize,
        $font, $newBitmapOffset + $destinationIndex * $glyphSize,
        $glyphSize)
}

function Get-Row([int]$code, [int]$row) {
    $index = $code - $firstCode
    $offset = $newBitmapOffset + $index * $glyphSize + $row * 4
    return [BitConverter]::ToUInt32($font, $offset)
}

function Set-Row([int]$code, [int]$row, [uint32]$value) {
    $index = $code - $firstCode
    $offset = $newBitmapOffset + $index * $glyphSize + $row * 4
    $rowBytes = [BitConverter]::GetBytes($value)
    [Array]::Copy($rowBytes, 0, $font, $offset, 4)
}

function Pixel-Mask([int]$x) {
    return [uint32]([uint64]1 -shl (31 - $x))
}

function Mirror-Glyph([int]$sourceCode, [int]$destinationCode, [int]$mirrorRight) {
    $font[$widthsOffset + ($destinationCode - $firstCode)] =
        $font[$widthsOffset + ($sourceCode - $firstCode)]
    for ($row = 0; $row -lt $height; $row++) {
        $sourceRow = Get-Row $sourceCode $row
        [uint32]$destinationRow = 0
        for ($x = 0; $x -le $mirrorRight; $x++) {
            if (($sourceRow -band (Pixel-Mask $x)) -ne 0) {
                $destinationRow = $destinationRow -bor (Pixel-Mask ($mirrorRight - $x))
            }
        }
        Set-Row $destinationCode $row $destinationRow
    }
}

function Set-RowPixels([int]$code, [int]$row, [int[]]$pixels) {
    [uint32]$value = 0
    foreach ($x in $pixels) { $value = $value -bor (Pixel-Mask $x) }
    Set-Row $code $row $value
}

function Keep-XRange([int]$code, [int]$row, [int]$minimumX, [int]$maximumX) {
    $source = Get-Row $code $row
    [uint32]$result = 0
    for ($x = $minimumX; $x -le $maximumX; $x++) {
        if (($source -band (Pixel-Mask $x)) -ne 0) {
            $result = $result -bor (Pixel-Mask $x)
        }
    }
    Set-Row $code $row $result
}

function Add-ShiftedGlyph([int]$sourceCode, [int]$destinationCode, [int]$shiftX) {
    for ($row = 0; $row -lt $height; $row++) {
        $source = Get-Row $sourceCode $row
        $destination = Get-Row $destinationCode $row
        for ($x = 0; $x -lt (32 - $shiftX); $x++) {
            if (($source -band (Pixel-Mask $x)) -ne 0) {
                $destination = $destination -bor (Pixel-Mask ($x + $shiftX))
            }
        }
        Set-Row $destinationCode $row $destination
    }
}

# CP1251 uppercase letters whose shapes match Latin glyphs.
Copy-Glyph 0x41 0xC0 # А <- A
Copy-Glyph 0x42 0xC2 # В <- B
Copy-Glyph 0x50 0xD0 # Р <- P
Copy-Glyph 0x43 0xD1 # С <- C
Copy-Glyph 0x4B 0xCA # К <- K
Copy-Glyph 0x4D 0xCC # М <- M
Copy-Glyph 0x48 0xCD # Н <- H
Copy-Glyph 0x4F 0xCE # О <- O
Copy-Glyph 0x54 0xD2 # Т <- T
Copy-Glyph 0x45 0xC5 # Е <- E (0xC5 was a legacy Western glyph)
Copy-Glyph 0x58 0xD5 # Х <- X

# Б: top bar and stem from B, with only its lower bowl retained.
Copy-Glyph 0x42 0xC1
for ($row = 5; $row -le 9; $row++) { Keep-XRange 0xC1 $row 0 6 }

# Г: F without its middle horizontal bar.
Copy-Glyph 0x46 0xC3
for ($row = 9; $row -le 12; $row++) { Keep-XRange 0xC3 $row 0 6 }

# Д is based on the game's pointed A; the lower bar gives it a Cyrillic base.
Copy-Glyph 0x41 0xC4
Set-RowPixels 0xC4 17 @(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14)

# З closely matches the game's numeral 3.
Copy-Glyph 0x33 0xC7

# Ж is X with the characteristic central stem.
Copy-Glyph 0x58 0xC6
for ($row = 4; $row -le 17; $row++) {
    $value = Get-Row 0xC6 $row
    $value = $value -bor (Pixel-Mask 7) -bor (Pixel-Mask 8)
    Set-Row 0xC6 $row $value
}

# И is a horizontally mirrored N in this display font.
Mirror-Glyph 0x4E 0xC8 14

# Й uses the new И body plus a compact breve in the previously empty top rows.
Copy-Glyph 0xC8 0xC9
Set-RowPixels 0xC9 1 @(5, 9)
Set-RowPixels 0xC9 2 @(5, 6, 8, 9)
Set-RowPixels 0xC9 3 @(6, 7, 8)

# Л is the pointed A without its horizontal crossbar.
Copy-Glyph 0x41 0xCB
Set-Row 0xCB 13 (Get-Row 0x41 12)
Set-Row 0xCB 14 (Get-Row 0x41 15)

# П: straight top bar and two vertical stems.
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xCF $row 0 }
Set-RowPixels 0xCF 4 (3..13)
Set-RowPixels 0xCF 5 (1..15)
for ($row = 6; $row -le 16; $row++) {
    Set-RowPixels 0xCF $row @(2,3,4,12,13,14)
}
Set-RowPixels 0xCF 17 @(2,3,13,14)
$font[$widthsOffset + (0xCF - $firstCode)] = 17

# У starts from Y and gets the characteristic descending left hook.
Copy-Glyph 0x59 0xD3
Set-RowPixels 0xD3 13 @(7, 8, 9)
Set-RowPixels 0xD3 14 @(7, 8, 9)
Set-RowPixels 0xD3 15 @(6, 7, 8)
Set-RowPixels 0xD3 16 @(4, 5, 6, 7)
Set-RowPixels 0xD3 17 @(2, 3, 4, 5, 6)

# Ф is O crossed by a full-height central stem.
Copy-Glyph 0x4F 0xD4
for ($row = 2; $row -le 19; $row++) {
    $value = Get-Row 0xD4 $row
    $value = $value -bor (Pixel-Mask 7) -bor (Pixel-Mask 8)
    Set-Row 0xD4 $row $value
}

# Ц: two upright stems, a broad baseline, and a compact right tail.
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xD6 $row 0 }
Set-RowPixels 0xD6 4 @(2,3,4,12,13,14)
Set-RowPixels 0xD6 5 @(1,2,3,4,12,13,14,15)
for ($row = 6; $row -le 14; $row++) {
    Set-RowPixels 0xD6 $row @(2,3,4,12,13,14)
}
Set-RowPixels 0xD6 15 (2..14)
Set-RowPixels 0xD6 16 (1..16)
Set-RowPixels 0xD6 17 @(1,2,14,15,16)
Set-RowPixels 0xD6 18 @(14,15,16)
Set-RowPixels 0xD6 19 @(15,16)
$font[$widthsOffset + (0xD6 - $firstCode)] = 19

# Ч: upper half of H, then only the right stem below the join.
Copy-Glyph 0x48 0xD7
for ($row = 11; $row -le 17; $row++) { Keep-XRange 0xD7 $row 8 16 }

# Ш has three vertical stems joined along the baseline.
Copy-Glyph 0x48 0xD8
for ($row = 4; $row -le 16; $row++) {
    $value = Get-Row 0xD8 $row
    # Remove H's crossbar while retaining the outer stems.
    [uint32]$outer = 0
    for ($x = 0; $x -le 16; $x++) {
        if (($x -le 5 -or $x -ge 10) -and
            ($value -band (Pixel-Mask $x)) -ne 0) {
            $outer = $outer -bor (Pixel-Mask $x)
        }
    }
    $outer = $outer -bor (Pixel-Mask 7) -bor (Pixel-Mask 8)
    Set-Row 0xD8 $row $outer
}
Set-RowPixels 0xD8 17 @(2,3,4,5,6,7,8,9,10,11,12,13,14)

# Щ extends Ш with a short right descender.
Copy-Glyph 0xD8 0xD9
$font[$widthsOffset + (0xD9 - $firstCode)] = 18
$value = Get-Row 0xD9 17
$value = $value -bor (Pixel-Mask 15) -bor (Pixel-Mask 16)
Set-Row 0xD9 17 $value
Set-RowPixels 0xD9 18 @(15,16)
Set-RowPixels 0xD9 19 @(15)

# Ь: B with the upper bowl removed. Ы adds a shifted I on the right.
Copy-Glyph 0x42 0xDC
for ($row = 4; $row -le 9; $row++) { Keep-XRange 0xDC $row 0 6 }
Copy-Glyph 0xDC 0xDB
Add-ShiftedGlyph 0x49 0xDB 13
$font[$widthsOffset + (0xDB - $firstCode)] = 22

# Ю combines a left stem and a shifted O.
for ($row = 0; $row -lt $height; $row++) { Set-Row 0xDE $row 0 }
Add-ShiftedGlyph 0x4F 0xDE 6
for ($row = 4; $row -le 17; $row++) {
    $value = Get-Row 0xDE $row
    $value = $value -bor (Pixel-Mask 1) -bor (Pixel-Mask 2)
    if ($row -ge 9 -and $row -le 12) {
        foreach ($x in 3..7) { $value = $value -bor (Pixel-Mask $x) }
    }
    Set-Row 0xDE $row $value
}
$font[$widthsOffset + (0xDE - $firstCode)] = 22

# Я is a mirrored R.
Mirror-Glyph 0x52 0xDF 15

[IO.File]::WriteAllBytes($target, $font)
Write-Host ('CORS3.F32 extended from 0x{0:X2} to 0x{1:X2}: {2} bytes.' -f `
    $oldLastCode, $newLastCode, $newSize)
