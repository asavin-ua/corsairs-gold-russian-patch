$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent $scriptRoot
$readme = Join-Path $repositoryRoot 'README.md'
$readmeIsInParent = $false
if (-not (Test-Path -LiteralPath $readme -PathType Leaf)) {
    $parentReadme = Join-Path (Split-Path -Parent $repositoryRoot) 'README.md'
    if (Test-Path -LiteralPath $parentReadme -PathType Leaf) {
        $readme = $parentReadme
        $readmeIsInParent = $true
    }
}
$errors = [Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $readme -PathType Leaf)) {
    $errors.Add('README.md is missing.')
}
else {
    $readmeText = [IO.File]::ReadAllText($readme, [Text.Encoding]::UTF8)
    $personalPatterns = [ordered]@{
        'Windows user profile path' = '(?i)[A-Z]:\\Users\\[^\\\s]+'
        'Unix user profile path' = '(?i)(?:/Users|/home)/[^/\s]+'
        'email address' = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
        'file URI' = '(?i)\bfile://'
    }
    foreach ($entry in $personalPatterns.GetEnumerator()) {
        if ([regex]::IsMatch($readmeText, $entry.Value)) {
            $errors.Add("README.md contains a possible $($entry.Key).")
        }
    }
}

$scriptFiles = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
    Where-Object {
        $relativePath = $_.FullName.Substring($repositoryRoot.Length).TrimStart('\')
        $_.Extension -in @('.ps1', '.cmd', '.py') -and
        $relativePath -notlike 'releases\*' -and
        $relativePath -notlike 'tools\pydeps\*'
    }
$absoluteWindowsPath = '(?<![A-Za-z])[A-Za-z]:[\\/]'
$absoluteUserPath = '(?i)(?:/Users|/home)/[^/\s]+'
foreach ($file in $scriptFiles) {
    $text = [IO.File]::ReadAllText($file.FullName)
    if ([regex]::IsMatch($text, $absoluteWindowsPath)) {
        $relative = $file.FullName.Substring($repositoryRoot.Length).TrimStart('\')
        $errors.Add("Script contains a hard-coded drive path: $relative")
    }
    if ([regex]::IsMatch($text, $absoluteUserPath)) {
        $relative = $file.FullName.Substring($repositoryRoot.Length).TrimStart('\')
        $errors.Add("Script contains a hard-coded user path: $relative")
    }
}

foreach ($required in @('CONTRIBUTING.md', '.gitignore', '.gitattributes')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot $required) -PathType Leaf)) {
        $errors.Add("Required repository file is missing: $required")
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'AGENTS.md') -PathType Leaf) -and
    -not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $repositoryRoot) 'AGENTS.md') -PathType Leaf)) {
    $errors.Add('Required repository file is missing: AGENTS.md')
}
if (-not $readmeIsInParent -and -not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'README.md') -PathType Leaf)) {
    $errors.Add('Required repository file is missing: README.md')
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    throw "Repository audit failed with $($errors.Count) problem(s)."
}

Write-Host 'Repository audit: OK'
Write-Host "Audited scripts: $($scriptFiles.Count)"
Write-Host 'README personal-data patterns: none'
Write-Host 'Hard-coded local filesystem paths in scripts: none'
