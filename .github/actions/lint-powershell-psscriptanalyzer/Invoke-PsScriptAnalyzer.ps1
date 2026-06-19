<#
.SYNOPSIS
    Fails the build if PSScriptAnalyzer reports any diagnostic at or above
    the configured severity for the PowerShell files under -SourceRoot.

.DESCRIPTION
    Canonical style/correctness lint for the Infrastructure-* polyrepo
    family, sitting beside the syntax gate (Test-PowerShellParses.ps1) and
    the bare-`return @()` lint (Test-NoBareReturnEmptyArray.ps1). Where the
    parse gate is a pass/fail syntax floor, this gate runs the full
    PSScriptAnalyzer default rule set - the deeper static layer the parse
    gate's header explicitly defers to ("PSScriptAnalyzer fills that role").

    The rule set and severity bar are NOT hard-coded here. They live in
    PSScriptAnalyzerSettings.psd1 next to this script, passed to
    Invoke-ScriptAnalyzer via -Settings, so a local run and the CI run
    enforce exactly the same rules and cannot drift. Tune rules there.

    Robustness comes from delegating to the analyzer itself rather than
    re-implementing any rule: Invoke-ScriptAnalyzer is the same engine the
    rest of the ecosystem uses, so a file that passes here is clean by the
    community-standard definition. The module is installed on demand if
    absent, mirroring how the unit-test action installs Pester.

    Diagnostics are emitted as GitHub Actions error annotations
    (::error file=...,line=...) so they surface as red squiggles in the PR
    diff view; local invocation prints the same lines plain.

.PARAMETER SourceRoot
    Root directory of the repo under lint. Defaults to the current location
    so the script can be run interactively.

.PARAMETER SettingsPath
    Path to the PSScriptAnalyzer settings file. Defaults to the
    PSScriptAnalyzerSettings.psd1 co-located with this script - the single
    source of truth for the rule set and severity bar.

.EXAMPLE
    .\Invoke-PsScriptAnalyzer.ps1 -SourceRoot C:\a_Code\Common-PowerShell

.NOTES
    The executable body is guarded by an InvocationName check so the file
    can be dot-sourced from tests to expose Find-ScriptAnalyzerHits without
    firing the side-effecting scan or the module install. Mirrors the
    convention used by Test-PowerShellParses.ps1.
#>

param(
    [string] $SourceRoot = (Get-Location).Path,

    [string] $SettingsPath = (Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Path patterns that must never be analysed. .ci-common is the sibling
# checkout of Common-PowerShell created by ci-powershell.yml; excluded so
# the gate applies only to the caller repo's own files and an upstream
# finding is not blamed on the consumer PR. Kept identical to the parse
# gate's exclusion set so the two static gates scan the same surface.
$script:DefaultAnalyzerExcludePatterns = @(
    '^\.ci-common([\\/]|$)'
)

function Install-ScriptAnalyzerIfMissing {
    <#
    .SYNOPSIS
        Ensures PSScriptAnalyzer is importable, installing it for the
        current user if no copy is present.

    .DESCRIPTION
        Side-effecting on purpose and kept separate from the pure scan so
        tests can dot-source the scan without triggering a module install.
        Mirrors the on-demand Pester install in the run-unit-tests action.
    #>
    [CmdletBinding()]
    param()

    $existing = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $existing) {
        Write-Host 'PSScriptAnalyzer not found - installing ...' -ForegroundColor Cyan
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
    }

    Import-Module PSScriptAnalyzer
}

function Find-ScriptAnalyzerHits {
    <#
    .SYNOPSIS
        Returns hit records (Path, LineNumber, Severity, RuleName, Message)
        for every PSScriptAnalyzer diagnostic under -SourceRoot.

    .DESCRIPTION
        Pure: no Write-Host, no exit, no install. Lets tests assert on the
        result without parsing stdout. The script body below emits and
        exits; this function does neither. PSScriptAnalyzer must already be
        importable (the body calls Install-ScriptAnalyzerIfMissing first).
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $SourceRoot,

        [Parameter(Mandatory)]
        [string] $SettingsPath,

        [string[]] $ExcludePatterns = $script:DefaultAnalyzerExcludePatterns
    )

    $root = (Resolve-Path -LiteralPath $SourceRoot).Path

    # -Recurse walks the whole tree; the settings file decides the rules and
    # severity. The post-filter drops diagnostics from excluded paths -
    # Invoke-ScriptAnalyzer has no per-path exclude that survives -Recurse,
    # so the cut is applied here on the absolute ScriptPath of each result.
    $diagnostics = Invoke-ScriptAnalyzer -Path $root -Recurse -Settings $SettingsPath

    $hits = foreach ($d in $diagnostics) {
        $rel = $d.ScriptPath.Substring($root.Length).TrimStart('\', '/')

        $excluded = $false
        foreach ($p in $ExcludePatterns) {
            if ($rel -match $p) { $excluded = $true; break }
        }
        if ($excluded) { continue }

        [pscustomobject]@{
            Path       = $d.ScriptPath
            LineNumber = $d.Line
            Severity   = $d.Severity
            RuleName   = $d.RuleName
            Message    = $d.Message
        }
    }

    # Comma-operator wrap so a single hit (or zero hits) round-trips as an
    # array; otherwise the caller's @().Count would scalar-throw. Eats its
    # own dogfood (the bare-return lint that runs beside this).
    return ,@($hits)
}

# Dot-source guard: when invoked as `. .\Invoke-PsScriptAnalyzer.ps1` (from
# tests) the executable body is skipped so the helpers above are exposed
# without installing the module or firing the scan. Mirrors
# Test-PowerShellParses.ps1.
if ($MyInvocation.InvocationName -ne '.') {

    Install-ScriptAnalyzerIfMissing

    $hits = Find-ScriptAnalyzerHits -SourceRoot $SourceRoot -SettingsPath $SettingsPath

    if (@($hits).Count -eq 0) {
        Write-Host 'Lint OK: PSScriptAnalyzer reported no diagnostics.'
        exit 0
    }

    foreach ($h in $hits) {
        Write-Host (
            "::error file=$($h.Path),line=$($h.LineNumber)::" +
            "PSScriptAnalyzer [$($h.Severity)] $($h.RuleName): $($h.Message)"
        )
    }
    Write-Host "Lint FAILED: $(@($hits).Count) PSScriptAnalyzer diagnostic(s) found."
    exit 1
}
