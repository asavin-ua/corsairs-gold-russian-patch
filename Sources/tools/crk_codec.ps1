param(
    [Parameter(Mandatory)]
    [ValidateSet('Decode', 'Encode')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [string]$InputPath,

    [Parameter(Mandatory)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$inputBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $InputPath))
$outputBytes = New-Object byte[] $inputBytes.Length

for ($i = 0; $i -lt $inputBytes.Length; $i++) {
    if ($Mode -eq 'Decode') {
        $outputBytes[$i] = [byte](($inputBytes[$i] - 127 + 256) % 256)
    }
    else {
        $outputBytes[$i] = [byte](($inputBytes[$i] + 127) % 256)
    }
}

$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
[IO.File]::WriteAllBytes($outputFullPath, $outputBytes)
Write-Host "$Mode complete: $outputFullPath"
