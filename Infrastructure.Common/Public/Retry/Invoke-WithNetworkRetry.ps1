<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. Test-TransientNetworkException
    (the classification helper this loop calls) lives next to
    New-TransientNetworkRetryStrategy.ps1, which is loaded in the same module
    scope - so the call below resolves at runtime.

    This file is slated for removal once consumers migrate to the
    Invoke-WithRetry primitive plus the strategy factories
    (see docs/dev/implementation/07 - generalise retry/plan.md, Step 4).
#>

# ---------------------------------------------------------------------------
# Invoke-WithNetworkRetry
#   Runs $ScriptBlock and retries on transient network failures with
#   exponential backoff. Non-transient failures (4xx, validation errors,
#   mock-thrown strings in tests) propagate immediately so the operator
#   gets a fast, actionable error instead of waiting through retries
#   that cannot succeed.
#
#   Default policy: 3 attempts total, delays of 2s and 4s between them.
#   That covers brief DNS hiccups and short-lived connectivity drops
#   without making a hard failure feel sluggish.
#
#   Parameter override is provided so callers (and tests) can tighten
#   or loosen the policy. The helper is intentionally tiny and stateless;
#   any larger retry strategy (circuit breaker, jitter) belongs in a
#   dedicated module, not here.
# ---------------------------------------------------------------------------

function Invoke-WithNetworkRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        # Surfaced in the warning so the operator can tell which call is
        # being retried (e.g. "Adoptium API lookup" vs "tarball download").
        [string] $OperationName = 'network call',

        # Total attempts including the first try. 1 disables retry entirely
        # (useful in tests where the failure is deterministic).
        [int] $MaxAttempts = 3,

        # Seconds to wait before the first retry. Doubles each subsequent
        # attempt. 2 -> 4 -> 8 ... bounded by the attempt count above.
        [int] $InitialDelaySeconds = 2
    )

    $delay = $InitialDelaySeconds
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            # Permanent errors (4xx, mocks, argument bugs) skip retry so
            # callers see the original failure without added latency.
            if (-not (Test-TransientNetworkException -ErrorRecord $_)) {
                throw
            }

            # Last attempt - propagate so the caller sees the underlying
            # network error rather than a generic "gave up" wrapper.
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            Write-Warning (
                "$OperationName failed (attempt $attempt/$MaxAttempts): " +
                "$($_.Exception.Message). Retrying in ${delay}s ..."
            )
            Start-Sleep -Seconds $delay
            $delay *= 2
        }
    }
}
