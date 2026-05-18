<#
.SYNOPSIS
    Shared PowerShell utilities for infrastructure repos.

.DESCRIPTION
    Provides cross-cutting utilities that are not specific to any single
    infrastructure concern (secrets, provisioning, users, etc.).

    Current functions:
    - Assert-RequiredProperties: validates object fields are present and
      non-empty; throws a descriptive error if not.
    - ConvertTo-Array: ensures a value is always an array regardless of
      whether PowerShell unrolled a single-item collection.
    - Invoke-ModuleInstall: installs a PSGallery module if absent or below a
      minimum version, then imports it.
    - Invoke-WithNetworkRetry: runs a scriptblock and retries on transient
      network failures (DNS, connection drops, 5xx) with exponential
      backoff; non-transient errors (4xx, mocks) propagate immediately.
    - New-TransientNetworkRetryStrategy: builds a retry-strategy hashtable
      that matches transient network failures, for use with the upcoming
      Invoke-WithRetry primitive.
    - New-FileLockRetryStrategy: builds a retry-strategy hashtable that
      matches System.IO.IOException (file-lock contention, e.g. Hyper-V
      VMMS handle release after Remove-VM).

    Hyper-V VM helpers (SSH execution, host file server) were moved to the
    Infrastructure.HyperV module to keep this module focused on genuinely
    generic utilities. GitHub API helpers live in Infrastructure.GitHub.

    Each function lives in its own file under Public\ and is dot-sourced
    below so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Top-level utilities (no domain grouping yet).
. "$PSScriptRoot\Public\Assert-RequiredProperties.ps1"
. "$PSScriptRoot\Public\ConvertTo-Array.ps1"
. "$PSScriptRoot\Public\Invoke-ModuleInstall.ps1"

# Retry primitives - grouped because they form a self-contained family
# (loop + predicate strategies + backoff strategies) and their count will
# grow as Step 2-3 of the "generalise retry" plan land. Subdivided by
# strategy category: TransientErrorStrategies\ for ShouldRetry classifiers
# and BackoffStrategies\ for GetDelay providers (the latter introduced in Step 2). Predicate
# strategies are dot-sourced before the loop helpers so the loop's
# relocated classifier helper resolves at module-load time.
. "$PSScriptRoot\Public\Retry\TransientErrorStrategies\New-FileLockRetryStrategy.ps1"
. "$PSScriptRoot\Public\Retry\TransientErrorStrategies\New-TransientNetworkRetryStrategy.ps1"
. "$PSScriptRoot\Public\Retry\Invoke-WithNetworkRetry.ps1"

# Export-ModuleMember controls what is actually callable after Import-Module.
# It takes precedence over FunctionsToExport in the psd1 at runtime, so both
# must be kept in sync. FunctionsToExport serves a separate purpose: it is
# read by Get-Module -ListAvailable, Find-Module, and PSGallery for fast
# discovery without loading the module. The shared Module.Tests.ps1 in the
# run-unit-tests action enforces that every Public\*.ps1 file appears in both.
Export-ModuleMember -Function `
    Assert-RequiredProperties, `
    ConvertTo-Array, `
    Invoke-ModuleInstall, `
    `
    Invoke-WithNetworkRetry, `
    New-FileLockRetryStrategy, `
    New-TransientNetworkRetryStrategy
