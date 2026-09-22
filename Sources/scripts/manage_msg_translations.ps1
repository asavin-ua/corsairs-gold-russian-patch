param(
    [ValidateSet('Inspect', 'Install', 'Full', 'Restore', 'SelfTest')]
    [string]$Mode = 'Install',
    [int[]]$Line = @(),
    [switch]$DryRun,
    [switch]$AllowExperimentalFull
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$patchRoot = Split-Path -Parent $scriptRoot
$tool = Join-Path $patchRoot 'tools\msg_tool.py'

$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
$pythonPrefix = @()
if (-not $pythonCommand) {
    $pythonCommand = Get-Command py -ErrorAction SilentlyContinue
    $pythonPrefix = @('-3')
}
if (-not $pythonCommand) {
    throw 'Python 3 was not found in PATH. Install Python for all users or add it to PATH.'
}

[string[]]$toolArguments = @(switch ($Mode) {
    'Inspect'  { @('inspect', '--verbose') }
    'SelfTest' { @('self-test') }
    'Restore'  {
        if ($DryRun) { @('restore') } else { @('restore', '--apply') }
    }
    'Install' {
        $arguments = @('install')
        foreach ($number in $Line) { $arguments += @('--line', [string]$number) }
        if (-not $DryRun) { $arguments += '--apply' }
        $arguments
    }
    'Full' {
        $arguments = @('full')
        if (-not $DryRun) {
            if (-not $AllowExperimentalFull) {
                throw 'Full MSG installation is not fully tested. Use -AllowExperimentalFull only for an intentional test.'
            }
            $arguments += @('--apply', '--acknowledge-experimental')
        }
        $arguments
    }
})

& $pythonCommand.Source @pythonPrefix $tool @toolArguments
if ($LASTEXITCODE -ne 0) {
    throw "msg_tool.py failed with exit code $LASTEXITCODE"
}
