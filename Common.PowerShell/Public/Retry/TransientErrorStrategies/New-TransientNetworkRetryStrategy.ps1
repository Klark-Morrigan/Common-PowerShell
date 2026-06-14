<#
.NOTES
    Dot-sourced by Common.PowerShell.psm1. The public surface is
    New-TransientNetworkRetryStrategy; Test-TransientNetworkException is a
    file-private helper kept alongside the factory so the classification
    policy lives next to its sole consumer.
#>

# ---------------------------------------------------------------------------
# Test-TransientNetworkException (private)
#   Walks the exception chain on an ErrorRecord and decides whether the
#   failure is a transient network condition (worth retrying) or a
#   permanent error (a 4xx client response, an argument bug, the mock
#   layer in tests throwing a plain string, etc.).
#
#   Two detection paths, tried in order. Type-based is the canonical /
#   reliable path; message-based is a best-effort fallback for callers
#   whose layer wraps the underlying exception and loses the type.
#
#   1. Type-based (preferred) - walks the InnerException chain:
#      - System.Net.Http.HttpRequestException   (DNS, connection refused,
#                                                socket errors, generic
#                                                HttpClient failures)
#      - System.Net.WebException                (legacy WebClient stack)
#      - System.Net.Sockets.SocketException     (raw socket errors -
#                                                "No such host is known")
#      - System.TimeoutException
#      - System.Threading.Tasks.TaskCanceledException (HttpClient timeout)
#      - HttpResponseException with 5xx status (4xx -> permanent)
#
#   2. Message-based fallback - scans Exception.Message and
#      ErrorDetails.Message for well-known phrases. Used when a caller's
#      layer (e.g. PowerShellGet, which wraps everything in generic
#      Exception types) destroys the type info that path 1 relies on.
#      Pattern matching is brittle to wording shifts so this path is a
#      fallback, not the primary classifier - the cost of a missed
#      pattern is a real flake fails fast, which is the safer side to
#      err on.
#
#   Anything else (e.g. ArgumentException, RuntimeException from a
#   string throw in tests) is treated as permanent so a bug or a test
#   mock does not incur retry delays.
#
#   Kept module-internal (not in Export-ModuleMember) - exposing the
#   policy decision through the strategy factory is enough, and keeping
#   it private leaves room to evolve the classification without breaking
#   callers.
# ---------------------------------------------------------------------------

function Test-TransientNetworkException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    # ------------------------------------------------------------------
    # Path 1 - type-based (preferred)
    # ------------------------------------------------------------------
    $transientTypeNames = @(
        'System.Net.Http.HttpRequestException',
        'System.Net.WebException',
        'System.Net.Sockets.SocketException',
        'System.TimeoutException',
        'System.Threading.Tasks.TaskCanceledException'
    )

    $ex = $ErrorRecord.Exception
    while ($null -ne $ex) {
        $typeName = $ex.GetType().FullName

        # PowerShell 7's Invoke-RestMethod / Invoke-WebRequest emit
        # HttpResponseException for non-success responses. Distinguish 4xx
        # (permanent) from 5xx (transient) by the Response.StatusCode value.
        if ($typeName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $statusCode = [int] $ex.Response.StatusCode
            return ($statusCode -ge 500)
        }

        if ($transientTypeNames -contains $typeName) {
            return $true
        }

        $ex = $ex.InnerException
    }

    # ------------------------------------------------------------------
    # Path 2 - message-based fallback
    #   Both Exception.Message and ErrorDetails.Message are checked
    #   because PowerShellGet sometimes populates only the latter (the
    #   operator-facing text) while Exception.Message stays generic.
    # ------------------------------------------------------------------
    $messages = @()
    if ($ErrorRecord.Exception)    { $messages += $ErrorRecord.Exception.Message }
    if ($ErrorRecord.ErrorDetails) { $messages += $ErrorRecord.ErrorDetails.Message }
    $combined = ($messages -join ' ')

    # Patterns grouped by failure family. Keep the list narrow - the
    # cost of a missed pattern is a real flake failing fast (safe),
    # the cost of a wrong match is a non-transient error being retried
    # for the full attempt budget (annoying).
    $transientMessagePatterns = @(
        # Network-level: DNS, dropped connection, timeout
        'Unable to connect to the remote server',
        'remote name could not be resolved',
        'underlying connection was closed',
        'operation has timed out',
        # HTTP 5xx
        'Service Unavailable',
        'Bad Gateway',
        'Gateway Time-?out',
        'Internal Server Error'
    )

    foreach ($pattern in $transientMessagePatterns) {
        if ($combined -match $pattern) { return $true }
    }

    return $false
}

function New-TransientNetworkRetryStrategy {
    <#
    .SYNOPSIS
        Builds a retry strategy hashtable that matches transient network
        failures (DNS hiccups, dropped connections, 5xx responses,
        HttpClient timeouts).

    .DESCRIPTION
        Returned shape is the standard retry-strategy contract consumed by
        Invoke-WithRetry:

            @{
                Name        = 'TransientNetwork'
                ShouldRetry = { param($err) <bool> }
            }

        Classification is two-path:
          1. Type-based (preferred): walks the InnerException chain for
             known transient .NET network types and HttpResponseException
             status codes.
          2. Message-based fallback: scans Exception.Message and
             ErrorDetails.Message for well-known transient phrases when
             type info has been wrapped away by an upstream layer (e.g.
             PowerShellGet).

        4xx HttpResponseExceptions and non-network errors are classified
        as permanent so the caller fails fast instead of sleeping through
        retries that cannot succeed.

    .EXAMPLE
        Invoke-WithRetry `
            -ScriptBlock   { Invoke-RestMethod $url } `
            -RetryStrategy (New-TransientNetworkRetryStrategy)
    #>
    [CmdletBinding()]
    param()

    return @{
        Name        = 'TransientNetwork'
        ShouldRetry = {
            param([System.Management.Automation.ErrorRecord] $ErrorRecord)
            Test-TransientNetworkException -ErrorRecord $ErrorRecord
        }
    }
}
