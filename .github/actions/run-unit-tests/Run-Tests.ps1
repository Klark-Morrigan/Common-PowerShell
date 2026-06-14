<#
.SYNOPSIS
    Runs unit tests for a PowerShell repo.

.DESCRIPTION
    Canonical implementation for the Infrastructure-* polyrepo family.
    Called by the run-unit-tests composite action in CI, and by the
    root-level Run-Tests.ps1 wrapper for local dev.

    Installs Pester 5 if not already present, then runs every *.Tests.ps1
    file found under <TestsRoot>\Tests\, excluding:
    - Tests\Integration.DockerHost\ - tests run inside a Docker container
      (see run-integration-tests action).
    - Tests\Integration.DockerTarget\ - tests run on the host and connect
      via SSH to a Docker container (see build-ssh-test-image action).

    Also injects the shared Module.Tests.ps1 from this action directory,
    which verifies that every Public\*.ps1 file is registered in the module
    manifest and psm1. Requires the repo to follow the convention:
    a single subdirectory whose name matches its .psd1 (e.g.
    Common.PowerShell\Common.PowerShell.psd1). If no such directory
    is found the shared test is skipped silently.

.PARAMETER TestsRoot
    Root directory of the repo under test. Tests\ must be a direct child.

.PARAMETER LogPath
    When set, every output stream of the run is redirected into this file
    instead of the console, and old logs in the same directory are pruned
    (see -LogRetention). Redirecting inside the script keeps the caller's
    command line a single bare invocation with no redirection operator,
    which is the only shape an automated permission resolver can auto-allow.
    Point this at a DEDICATED directory, not a shared TEMP root, or the
    retention sweep will also consider neighbouring matching files.

.PARAMETER LogRetention
    Most-recent log files to keep in the -LogPath directory after each run.
    0 disables pruning. Ignored unless -LogPath is set.

.PARAMETER LogRetentionFilter
    Wildcard the retention sweep matches log files against. Narrow this when
    -LogPath shares a directory with unrelated files. Ignored unless
    -LogPath is set.

.EXAMPLE
    .\Run-Tests.ps1 -TestsRoot C:\a_Code\Infrastructure-Secrets

.EXAMPLE
    .\Run-Tests.ps1 -TestsRoot C:\a_Code\Infrastructure-Wsl `
                    -LogPath   C:\Temp\ps-tests\wsl.log

    Runs silently, capturing all output to wsl.log and keeping the 10 most
    recent *.log files in C:\Temp\ps-tests.
#>

param(
    [string] $TestsRoot = $PSScriptRoot,

    [string] $LogPath,

    [int] $LogRetention = 10,

    [string] $LogRetentionFilter = '*.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. ([IO.Path]::Combine($PSScriptRoot, '..', 'Helpers.ps1'))

# ---------------------------------------------------------------------------
# Helper functions - one per file under lib\, dot-sourced so they are available
# both to the main block below and to unit tests that dot-source this script.
# They take sibling-file paths as parameters rather than deriving them from
# $PSScriptRoot, which inside a dot-sourced function would resolve to lib\.
# ---------------------------------------------------------------------------

. ([IO.Path]::Combine($PSScriptRoot, 'lib', 'Get-UnitTestFiles.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'lib', 'Invoke-UnitTestRun.ps1'))
. ([IO.Path]::Combine($PSScriptRoot, 'lib', 'Limit-TestLogRetention.ps1'))

# ---------------------------------------------------------------------------
# Main execution - skipped when dot-sourced for unit testing.
# ---------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {

    # Set by Invoke-UnitTestRun, possibly from inside an output redirect, which
    # is why it is a script-scoped variable and not the function's return value.
    $script:UnitTestFailedCount = 0

    # Resolved here, where $PSScriptRoot is the action directory, then injected
    # into the helpers (which live under lib\ and cannot derive them safely).
    $sharedModuleTest   = [IO.Path]::Combine($PSScriptRoot, 'Module.Tests.ps1')
    # run-unit-tests -> actions -> .github -> <repo root> -> module Public dir.
    $retainedItemHelper = [IO.Path]::Combine($PSScriptRoot, '..', '..', '..',
        'Common.PowerShell', 'Public', 'Limit-RetainedItem.ps1')

    if ($LogPath) {
        # Self-logging mode. Redirect every stream of the run into $LogPath here,
        # inside the script, so the CALLER's command stays a single bare
        # `& '...Run-Tests.ps1' -TestsRoot ... -LogPath ...` with no redirection
        # operator. That bare shape is the only one a command-permission resolver
        # can safely auto-allow, so repeated runs stop prompting. The captured
        # log is read back afterwards (e.g. by read-log-tail).
        $logDirectory = Split-Path -Parent $LogPath
        if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }

        & {
            Invoke-UnitTestRun -TestsRoot $TestsRoot `
                               -SharedModuleTestPath $sharedModuleTest
        } *> $LogPath

        Limit-TestLogRetention -LogDirectory           $logDirectory `
                               -Filter                 $LogRetentionFilter `
                               -MaxItems               $LogRetention `
                               -RetainedItemHelperPath $retainedItemHelper

        # One concise line to the console (the only output the caller sees in
        # log mode), so pass/fail is known without opening the log.
        Write-Host "Unit tests complete - $($script:UnitTestFailedCount) failed. Log: $LogPath"
    }
    else {
        Invoke-UnitTestRun -TestsRoot $TestsRoot `
                           -SharedModuleTestPath $sharedModuleTest
    }

    if ($script:UnitTestFailedCount -gt 0) { exit 1 }
    exit 0
}
