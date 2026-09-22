param(
    [ValidateSet('Inspect', 'Apply', 'Restore')]
    [string]$Mode = 'Inspect'
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$gameRoot = Split-Path -Parent $patchRoot
$executable = Join-Path $gameRoot 'corsairs.exe'
$backup = Join-Path $patchRoot 'backup\corsairs.msg-parser-original.exe'

$expectedOriginalHash = '93FD792E80EC085F36BE814A4A244E96FDCB32CE3010F7B91064836C7FC02FE2'
$patchOffset = 0x2BC7D
$originalByte = 0x7C # JL: signed comparison rejects CP1251 bytes.
$patchedByte = 0x72  # JB: ASCII controls still delimit; extended bytes are accepted.

function Get-Sha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
}

function Write-Atomic([string]$Path, [byte[]]$Bytes) {
    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporary = Join-Path $directory ([IO.Path]::GetRandomFileName())
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $executable)) {
    throw "Executable was not found: $executable"
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($executable)
if ($bytes.Length -le $patchOffset) {
    throw "Executable is too short for patch offset 0x$($patchOffset.ToString('X'))."
}
$hash = Get-Sha256 $bytes
$currentByte = $bytes[$patchOffset]

if ($Mode -eq 'Inspect') {
    $state = if ($currentByte -eq $originalByte -and $hash -eq $expectedOriginalHash) {
        'original'
    }
    elseif ($currentByte -eq $patchedByte) {
        'patched'
    }
    else {
        'unknown'
    }
    Write-Host "Executable: $executable"
    Write-Host "SHA-256:    $hash"
    Write-Host ("Byte:        0x{0:X2} at file offset 0x{1:X}" -f $currentByte, $patchOffset)
    Write-Host "State:       $state"
    exit 0
}

if ($Mode -eq 'Restore') {
    if (-not (Test-Path -LiteralPath $backup)) {
        throw "Original backup was not found: $backup"
    }
    [byte[]]$backupBytes = [IO.File]::ReadAllBytes($backup)
    $backupHash = Get-Sha256 $backupBytes
    if ($backupHash -ne $expectedOriginalHash -or $backupBytes[$patchOffset] -ne $originalByte) {
        throw 'The executable backup does not match the expected pristine version.'
    }
    Write-Atomic $executable $backupBytes
    Write-Host "Restored original executable: $executable"
    exit 0
}

if ($currentByte -eq $patchedByte) {
    Write-Host 'MSG parser patch is already installed.'
    exit 0
}
if ($hash -ne $expectedOriginalHash -or $currentByte -ne $originalByte) {
    throw 'Refusing to patch: corsairs.exe does not match the expected pristine version.'
}

if (Test-Path -LiteralPath $backup) {
    [byte[]]$backupBytes = [IO.File]::ReadAllBytes($backup)
    if ((Get-Sha256 $backupBytes) -ne $expectedOriginalHash) {
        throw "Existing backup is not pristine: $backup"
    }
}
else {
    Write-Atomic $backup $bytes
    Write-Host "Created backup: $backup"
}

$bytes[$patchOffset] = $patchedByte
Write-Atomic $executable $bytes
Write-Host ("Patched byte 0x{0:X2} -> 0x{1:X2} at file offset 0x{2:X}." -f $originalByte, $patchedByte, $patchOffset)
Write-Host "Patched executable: $executable"
