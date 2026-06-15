<#
.SYNOPSIS
    Fails the build if any PowerShell file under -SourceRoot does not
    parse cleanly.

.DESCRIPTION
    Canonical syntax gate for the Infrastructure-* polyrepo family.
    Called by the reusable ci-powershell.yml workflow alongside the
    unit tests and the bare-`return @()` lint.

    Robustness comes from using the PowerShell language parser itself
    (System.Management.Automation.Language.Parser.ParseFile) rather
    than a regex. The parser is the same component pwsh uses to load a
    script, so a file that passes this gate is guaranteed to at least
    tokenise and bind syntactically - it cannot have an unbalanced
    brace, a stray backtick, a broken here-string, or any other parse
    error. This catches the class of breakage that a unit-test run
    would surface only if the malformed file happened to be dot-sourced
    by a test; files loaded lazily (or only in production) would
    otherwise ship broken.

    Simplicity comes from doing nothing more: this is a pass/fail
    syntax check, not a style or correctness linter (PSScriptAnalyzer
    fills that role). No rules to configure, no severity matrix.

    Covered extensions are .ps1, .psm1 and .psd1 - the three file
    kinds the parser understands (scripts, modules, data/manifest
    files). Parse errors are emitted as GitHub Actions error
    annotations so they show as red squiggles in the PR diff view.
    Local invocation gets the same lines printed plain.

.PARAMETER SourceRoot
    Root directory of the repo under lint. Defaults to the current
    location so the script can be run interactively.

.EXAMPLE
    .\Test-PowerShellParses.ps1 -SourceRoot C:\a_Code\Infrastructure-Vm-Provisioner

.NOTES
    The executable body is guarded by an InvocationName check so the
    file can be dot-sourced from tests to expose the helper functions
    without firing the side-effecting scan. Mirrors the convention
    used by Test-NoBareReturnEmptyArray.ps1.
#>

param(
    [string] $SourceRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Extensions the language parser understands. Kept in script scope so
# both the scan and the OK-line file count read the exact same set;
# bare-literal duplication would invite drift.
$script:ParsablePowerShellExtensions = @('.ps1', '.psm1', '.psd1')

# Path patterns that must never be parsed. .ci-common is the sibling
# checkout of Common-PowerShell created by ci-powershell.yml; excluded
# so the gate applies only to the caller repo's own files and a parse
# error upstream is not blamed on the consumer PR. Unlike the
# bare-return lint, Tests/ is NOT excluded here: a malformed test file
# is itself a defect this gate should catch before Pester discovery
# fails with a noisier error.
$script:DefaultParseExcludePatterns = @(
    '^\.ci-common([\\/]|$)'
)

function Find-ParseErrorHits {
    <#
    .SYNOPSIS
        Returns hit records (Path, LineNumber, Message) for every parse
        error in PowerShell files under -SourceRoot.

    .DESCRIPTION
        Pure: no Write-Host, no exit. Lets tests assert on the result
        without parsing stdout. The script body below emits and exits;
        this function does neither.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $SourceRoot,

        [string[]] $ExcludePatterns = $script:DefaultParseExcludePatterns
    )

    $root = (Resolve-Path -LiteralPath $SourceRoot).Path

    $files = Get-ChildItem -Path $root -Recurse -File |
        Where-Object { $script:ParsablePowerShellExtensions -contains $_.Extension } |
        Where-Object {
            $rel = $_.FullName.Substring($root.Length).TrimStart('\','/')
            foreach ($p in $ExcludePatterns) {
                if ($rel -match $p) { return $false }
            }
            $true
        }

    $hits = foreach ($file in $files) {
        # ParseFile reports every error it can recover past, not just the
        # first, so one malformed file yields one hit per distinct error.
        # The token output is required by the signature but unused here.
        $errors = $null
        $tokens = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName, [ref] $tokens, [ref] $errors) | Out-Null

        foreach ($err in $errors) {
            [pscustomobject]@{
                Path       = $file.FullName
                LineNumber = $err.Extent.StartLineNumber
                Message    = $err.Message
            }
        }
    }

    # Comma-operator wrap so a single hit (or zero hits) round-trips as
    # an array; otherwise the caller's @().Count would scalar-throw.
    # Eats its own dogfood (the bare-return lint that runs beside this).
    return ,@($hits)
}

# Dot-source guard: when invoked as `. .\Test-PowerShellParses.ps1`
# (from tests) the executable body is skipped so the helpers above are
# exposed without firing the scan. Mirrors Test-NoBareReturnEmptyArray.ps1.
if ($MyInvocation.InvocationName -ne '.') {

    $hits = Find-ParseErrorHits -SourceRoot $SourceRoot

    if (@($hits).Count -eq 0) {
        # Files-scanned count for the OK line is computed here (not in
        # the function) because the function's contract is "return
        # hits", not "report progress".
        $root      = (Resolve-Path -LiteralPath $SourceRoot).Path
        $fileCount = (Get-ChildItem -Path $root -Recurse -File |
            Where-Object { $script:ParsablePowerShellExtensions -contains $_.Extension } |
            Where-Object {
                $rel = $_.FullName.Substring($root.Length).TrimStart('\','/')
                foreach ($p in $script:DefaultParseExcludePatterns) {
                    if ($rel -match $p) { return $false }
                }
                $true
            }).Count
        Write-Host "Lint OK: all PowerShell files parse cleanly (files scanned: $fileCount)."
        exit 0
    }

    foreach ($h in $hits) {
        Write-Host (
            "::error file=$($h.Path),line=$($h.LineNumber)::" +
            "PowerShell parse error: $($h.Message)"
        )
    }
    Write-Host "Lint FAILED: $(@($hits).Count) PowerShell parse error(s) found."
    exit 1
}
