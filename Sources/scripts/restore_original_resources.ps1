$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$iniBackup = Join-Path $patchRoot 'backup\L_ENGLIS.original.INI'
$iniTarget = Join-Path $gameRoot 'data\CRK\L_ENGLIS.INI'
$crkBackup = Join-Path $patchRoot 'backup\L_ENGLIS.original.CRK'
$crkTarget = Join-Path $gameRoot 'data\CRK\L_ENGLIS.CRK'
$fontBackup = Join-Path $patchRoot 'backup\FONTBIGB.original.TGA'
$fontTarget = Join-Path $gameRoot 'data\FONTBIGB.TGA'
$bookFontBackup = Join-Path $patchRoot 'backup\BOOK.original.F32'
$bookFontTarget = Join-Path $gameRoot 'data\BOOK.F32'
$cors1Backup = Join-Path $patchRoot 'backup\CORS1.original.F32'
$cors2Backup = Join-Path $patchRoot 'backup\CORS2.original.F32'
$cors3Backup = Join-Path $patchRoot 'backup\CORS3.original.F32'

Copy-Item -LiteralPath $iniBackup -Destination $iniTarget -Force
Copy-Item -LiteralPath $crkBackup -Destination $crkTarget -Force
Copy-Item -LiteralPath $fontBackup -Destination $fontTarget -Force
Copy-Item -LiteralPath $bookFontBackup -Destination $bookFontTarget -Force
Copy-Item -LiteralPath $cors1Backup -Destination (Join-Path $gameRoot 'data\CORS1.F32') -Force
Copy-Item -LiteralPath $cors2Backup -Destination (Join-Path $gameRoot 'data\CORS2.F32') -Force
Copy-Item -LiteralPath $cors3Backup -Destination (Join-Path $gameRoot 'data\CORS3.F32') -Force

Write-Host 'Original language files, FONTBIGB.TGA, and BOOK.F32 restored.'
