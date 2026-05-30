<#
.SYNOPSIS
    Resolves the path to Git Bash's bash.exe on Windows.

.DESCRIPTION
    Prefers bash.exe on PATH; falls back to deriving <git-install>\bin\bash.exe
    from git.exe's location so portable Git installs (which often add only
    git.exe to PATH) still work. Throws if neither route resolves.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-GitBashExecutable {
    $onPath = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) {
        throw 'Neither bash.exe nor git.exe found on PATH. Install Git for Windows.'
    }
    # git.exe lives at <git-install>\cmd\git.exe; bash is at <git-install>\bin\bash.exe.
    $candidate = Join-Path `
        (Split-Path -Parent (Split-Path -Parent $git.Source)) 'bin\bash.exe'
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "Could not locate bash.exe (looked on PATH and at '$candidate')."
    }
    return $candidate
}
