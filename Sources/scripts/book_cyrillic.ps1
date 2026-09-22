$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$source = Join-Path $patchRoot 'backup\BOOK.original.F32'
$target = Join-Path $gameRoot 'data\BOOK.F32'
$old = [IO.File]::ReadAllBytes($source)

function Read-BE16([byte[]]$data, [int]$offset) {
    return 256 * $data[$offset] + $data[$offset + 1]
}
function Read-BE32([byte[]]$data, [int]$offset) {
    return 16777216 * $data[$offset] + 65536 * $data[$offset + 1] +
        256 * $data[$offset + 2] + $data[$offset + 3]
}
function Write-BE32([byte[]]$data, [int]$offset, [int]$value) {
    $data[$offset] = ($value -shr 24) -band 0xFF
    $data[$offset + 1] = ($value -shr 16) -band 0xFF
    $data[$offset + 2] = ($value -shr 8) -band 0xFF
    $data[$offset + 3] = $value -band 0xFF
}

$height = Read-BE16 $old 8
$first = $old[10]
$oldLast = $old[11]
$newLast = 0xFF
$widths = Read-BE32 $old 12
$oldBitmap = Read-BE32 $old 16
$oldCount = $oldLast - $first + 1
$newCount = $newLast - $first + 1
$glyphSize = $height * 4
$newBitmap = $widths + $newCount
$newSize = $newBitmap + $newCount * $glyphSize
$fontData = [byte[]]::new($newSize)

[Array]::Copy($old, 0, $fontData, 0, $widths)
[Array]::Copy($old, $widths, $fontData, $widths, $oldCount)
[Array]::Copy($old, $oldBitmap, $fontData, $newBitmap, $oldCount * $glyphSize)
$fontData[11] = $newLast
Write-BE32 $fontData 4 $newSize
Write-BE32 $fontData 16 $newBitmap

$cp1251 = [Text.Encoding]::GetEncoding(1251)
$typeface = New-Object Drawing.Font('Georgia', 16, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$format = [Drawing.StringFormat]::GenericTypographic
$format.FormatFlags = $format.FormatFlags -bor [Drawing.StringFormatFlags]::MeasureTrailingSpaces

function Render-Glyph([int]$code) {
    $character = $cp1251.GetString([byte[]]@($code))
    $canvas = New-Object Drawing.Bitmap 40, $height
    $graphics = [Drawing.Graphics]::FromImage($canvas)
    $graphics.Clear([Drawing.Color]::Black)
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
    $graphics.DrawString($character, $typeface, [Drawing.Brushes]::White, 0, -1, $format)

    $minimumX = 40
    $maximumX = -1
    for ($y = 0; $y -lt $height; $y++) {
        for ($x = 0; $x -lt 32; $x++) {
            if ($canvas.GetPixel($x, $y).R -gt 64) {
                if ($x -lt $minimumX) { $minimumX = $x }
                if ($x -gt $maximumX) { $maximumX = $x }
            }
        }
    }

    $index = $code - $first
    $destination = $newBitmap + $index * $glyphSize
    if ($maximumX -lt $minimumX) {
        $fontData[$widths + $index] = 6
    }
    else {
        $glyphWidth = [Math]::Min(30, $maximumX - $minimumX + 1)
        $fontData[$widths + $index] = [Math]::Min(31, $glyphWidth + 1)
        for ($y = 0; $y -lt $height; $y++) {
            [uint32]$row = 0
            for ($x = 0; $x -lt $glyphWidth; $x++) {
                if ($canvas.GetPixel($minimumX + $x, $y).R -gt 64) {
                    $row = $row -bor [uint32]([uint64]1 -shl (30 - $x))
                }
            }
            $rowBytes = [BitConverter]::GetBytes($row)
            [Array]::Copy($rowBytes, 0, $fontData, $destination + $y * 4, 4)
        }
    }

    $graphics.Dispose()
    $canvas.Dispose()
}

# Yo/yo and the contiguous CP1251 Cyrillic alphabet.
Render-Glyph 0xA8
Render-Glyph 0xB8
for ($code = 0xC0; $code -le 0xFF; $code++) { Render-Glyph $code }

$typeface.Dispose()
[IO.File]::WriteAllBytes($target, $fontData)
Write-Host "BOOK.F32 Cyrillic range installed: 0xA8, 0xB8, 0xC0-0xFF."
