<#
.NOTES
    Dot-sourced by Common.PowerShell.psm1. Exit-code sibling of
    Invoke-WithRetry: the same backoff-strategy machinery, but the retry
    decision keys off a native command's exit code rather than a thrown
    exception. Lives alongside Invoke-WithRetry under Public\Retry\.
#>

function Invoke-WithExitCodeRetry {
    <#
    .SYNOPSIS
        Runs a script block wrapping a native command and retries while its
        exit code is non-zero (or in a caller-supplied retryable set),
        pacing attempts with a backoff strategy.

    .DESCRIPTION
        The exit-code counterpart to Invoke-WithRetry. Native commands
        (netsh, git, docker, wsl, ...) signal failure through
        $LASTEXITCODE, not exceptions, so Invoke-WithRetry's ShouldRetry
        predicates - which inspect a caught error - cannot classify them.
        This loop reads $LASTEXITCODE after each attempt instead, and
        reuses the same backoff strategies (@{ Name; GetDelay }) so a
        single backoff family covers both loops.

        Contract: the script block's FINAL statement must be the native
        command whose exit code matters - $LASTEXITCODE is read
        immediately after the block returns. A block whose last statement
        is a cmdlet leaves $LASTEXITCODE reflecting some earlier native
        call (or unset), which this loop cannot detect. Thrown exceptions
        are NOT retried here; they propagate (use Invoke-WithRetry for
        exception-classified retry).

    .PARAMETER ScriptBlock
        The work to attempt. Its pipeline output is the function's return
        value on success (exit 0).

    .PARAMETER BackoffStrategy
        A single backoff hashtable @{ Name; GetDelay }. Defaults to
        New-ExponentialBackoffStrategy. GetDelay is invoked with
        (attempt, $null): an exit-code failure has no ErrorRecord to pass,
        and the shared backoff strategies type their second parameter as
        [ErrorRecord] and key off the attempt number only - so the very
        same strategies that pair with Invoke-WithRetry work here too.

    .PARAMETER MaxAttempts
        Total attempts including the first. Defaults to 3. Pass 1 to
        disable retry.

    .PARAMETER RetryableExitCode
        Exit codes that count as retryable. Empty (the default) means any
        non-zero exit is retryable - the common case. Pass an explicit set
        to retry only known-transient codes and fail fast on the rest.

        This is deliberately a data-driven code set, not a predicate: an
        exit-code set is still "retry on the exit code". For retriability a
        set cannot express - "retry all except these permanent codes",
        ranges, classification over stderr - do not generalise this
        function; throw inside the script block and use Invoke-WithRetry,
        whose ShouldRetry strategies are the home for predicate-based
        classification.

    .PARAMETER OperationName
        Label surfaced in the per-retry warning and the failure message.
        Defaults to 'native command'.

    .EXAMPLE
        Invoke-WithExitCodeRetry `
            -OperationName 'netsh portproxy add' `
            -ScriptBlock {
                & netsh interface portproxy add v4tov4 `
                    listenaddress=0.0.0.0 listenport=2222 `
                    connectaddress=192.168.137.10 connectport=22 | Out-Null
            }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [hashtable] $BackoffStrategy,

        [int] $MaxAttempts = 3,

        [int[]] $RetryableExitCode = @(),

        [string] $OperationName = 'native command'
    )

    # Default the backoff lazily (mirrors Invoke-WithRetry) so callers that
    # pass an explicit strategy do not pay for the factory call, and the
    # parameter default stays free of an executable expression evaluated at
    # parameter-binding time.
    if (-not $BackoffStrategy) {
        $BackoffStrategy = New-ExponentialBackoffStrategy
    }
    Assert-RetryStrategyShape -Strategy $BackoffStrategy `
        -Kind 'Backoff' -ActionKey 'GetDelay'

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $output   = & $ScriptBlock
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            return $output
        }

        # Empty RetryableExitCode => any non-zero is retryable. Otherwise
        # only the listed codes are; anything else fails fast so a genuine
        # error is not retried pointlessly.
        $isRetryable = ($RetryableExitCode.Count -eq 0) -or
                       ($RetryableExitCode -contains $exitCode)
        if (-not $isRetryable) {
            throw "$OperationName failed with non-retryable exit ${exitCode} on attempt $attempt of $MaxAttempts."
        }

        # Last attempt - surface the exit code rather than sleeping then
        # throwing; the underlying failure is what the caller needs to act on.
        if ($attempt -ge $MaxAttempts) {
            throw "$OperationName failed with exit ${exitCode} after $MaxAttempts attempts."
        }

        # GetDelay's second parameter is the ErrorRecord that caused the
        # retry; an exit-code failure has none, so pass $null. The shared
        # backoff strategies type that parameter as [ErrorRecord] and use
        # only $Attempt - passing the int exit code here would fail their
        # type coercion.
        $delay = & $BackoffStrategy.GetDelay $attempt $null

        Write-Warning (
            "$OperationName failed (attempt $attempt/$MaxAttempts, " +
            "exit ${exitCode}). Retrying in ${delay}s ..."
        )
        Start-Sleep -Seconds $delay
    }
}
