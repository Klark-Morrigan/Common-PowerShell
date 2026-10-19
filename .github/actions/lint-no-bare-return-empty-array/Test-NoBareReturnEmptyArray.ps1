<#
.SYNOPSIS
    Fails the build if any production .ps1 under -SourceRoot contains a
    bare `return @()` statement.

.DESCRIPTION
    Canonical lint for the Infrastructure-* polyrepo family. Called by
    the reusable ci-powershell.yml workflow before the unit tests run.

    A bare `return @()` unrolls the empty array on the output stream so
    the caller sees $null instead of an empty array - the producer-side
    dual of the single-match `.Count` scalar trap. Use `return ,@()` to
    preserve array shape across the function boundary. See
    Common-PowerShell's memory entry
    `feedback_powershell_return_empty_array.md` for the failure that
    motivated this lint (JdkProvider.Get-DesiredVersions silently
    skipping the JDK uninstall path).

    The regex `^\s*return\s+@\(\s*\)\s*$` is anchored at line start
    (after whitespace) and end so comments that mention the literal
    text `return @()` are not false-positives. The codebase convention
    puts return on its own line, so this is precise enough without an
    AST walker. Internal whitespace is tolerated.

    Hits are emitted as GitHub Actions error annotations so they show
    as red squiggles in the PR diff view. Local invocation gets the
    same lines printed plain.

.PARAMETER SourceRoot
    Root directory of the repo under lint. Defaults to the current
    location so the script can be run interactively.

.EXAMPLE
    .\Test-NoBareReturnEmptyArray.ps1 -SourceRoot C:\a_Code\Infrastructure-Vm-Provisioner

.NOTES
    The executable body is guarded by an InvocationName check so the
    file can be dot-sourced from tests to expose the helper functions
    without firing the side-effecting scan. Mirrors the convention
    used by Run-IntegrationTests.ps1.
#>

param(
    [string] $SourceRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Shared lint functions, one per file under ..\lib\.
. ([IO.Path]::Combine($PSScriptRoot, '..', 'lib', 'Get-LintExcludePatterns.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, '..', 'lib', 'Test-LintPathExcluded.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, '..', 'lib', 'Get-LintFiles.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, '..', 'lib', 'Write-LintReport.ps1'))

# Regex documented in the file header. Defined here (script scope) so
# both the function and any future helpers see exactly the same shape;
# bare-string duplication would invite drift.
$script:BareReturnEmptyArrayPattern = '^\s*return\s+@\(\s*\)\s*$'

# The shared exclusions plus Tests/: fixtures and mock helpers
# legitimately construct empty arrays in places that look like returns.
$script:BareReturnExcludePatterns = (Get-LintExcludePatterns) + @(
    '(^|[\\/])Tests([\\/]|$)'
)

function Get-BareReturnLintFiles {
    <#
    .SYNOPSIS
        Returns every production .ps1 under -SourceRoot that the lint
        scans.

    .DESCRIPTION
        One list feeds both the scan and the OK line's files-scanned
        count, so the two cannot disagree on what was linted.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $SourceRoot,

        [string[]] $ExcludePatterns = $script:BareReturnExcludePatterns
    )

    $files = Get-LintFiles -SourceRoot $SourceRoot -Extensions '.ps1' -ExcludePatterns $ExcludePatterns

    return ,@($files)
}

function Find-BareReturnEmptyArrayHits {
    <#
    .SYNOPSIS
        Returns hit records (Path, LineNumber, Line) for every bare
        `return @()` in production .ps1 under -SourceRoot.

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

        [string[]] $ExcludePatterns = $script:BareReturnExcludePatterns
    )

    $files = Get-BareReturnLintFiles -SourceRoot $SourceRoot -ExcludePatterns $ExcludePatterns

    # Comma-operator wrap so a single hit (or zero hits) round-trips as
    # an array; otherwise the caller's @().Count would scalar-throw.
    # Eats its own dogfood.
    return ,@($files | Select-String -Pattern $script:BareReturnEmptyArrayPattern)
}

# Dot-source guard: when invoked as `. .\Test-NoBareReturnEmptyArray.ps1`
# (from tests) the executable body is skipped so the helpers above are
# exposed without firing the scan. Mirrors Run-IntegrationTests.ps1.
if ($MyInvocation.InvocationName -ne '.') {

    # Files-scanned count for the OK line is computed here (not in the
    # hit finder) because that function's contract is "return hits", not
    # "report progress".
    $files = Get-BareReturnLintFiles -SourceRoot $SourceRoot
    $hits  = Find-BareReturnEmptyArrayHits -SourceRoot $SourceRoot

    $exitCode = Write-LintReport -Hits $hits `
        -PassMessage "no bare 'return @()' in production .ps1 (files scanned: $($files.Count))." `
        -DescribeHit {
            "Bare 'return @()' unrolls to `$null at the caller. Use 'return ,@()' to preserve array shape."
        } `
        -FindingLabel "bare 'return @()' occurrence(s)"

    exit $exitCode
}
