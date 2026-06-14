BeforeAll {
    # Dot-source the Public file directly so both the exported factory and
    # the file-private Test-TransientNetworkException land in test scope.
    # At the file level Test-TransientNetworkException is just another
    # function; in module form it is not exported.
    . "$PSScriptRoot\..\..\..\Common.PowerShell\Public\Retry\TransientErrorStrategies\New-TransientNetworkRetryStrategy.ps1"

    # Hand-rolled ErrorRecord factory. Pester's ParameterFilter cannot
    # synthesise ErrorRecords for us, and we need the exception chain to
    # walk through specific types for Test-TransientNetworkException's
    # type-based path; ErrorDetails carries the operator-facing message
    # that PowerShellGet sometimes uses for the message-based fallback
    # path.
    function New-TestErrorRecord {
        param(
            [Exception] $Exception,
            [string]    $ErrorDetailsMessage
        )
        $rec = [System.Management.Automation.ErrorRecord]::new(
            $Exception, 'TestError', 'NotSpecified', $null)
        if ($ErrorDetailsMessage) {
            $rec.ErrorDetails =
                [System.Management.Automation.ErrorDetails]::new(
                    $ErrorDetailsMessage)
        }
        return $rec
    }

    # Builds a fake HttpResponseException-shaped object. The real type lives
    # in Microsoft.PowerShell.Commands and is awkward to construct directly,
    # so we mimic its surface (GetType().FullName, Response.StatusCode)
    # using Add-Type once per test run - Test-TransientNetworkException
    # inspects only those two members.
    function New-FakeHttpResponseException {
        param([int] $StatusCode)
        Add-Type -TypeDefinition @"
namespace Microsoft.PowerShell.Commands {
    public class HttpResponseException : System.Exception {
        public object Response { get; set; }
        public HttpResponseException(string message, object response) : base(message) {
            Response = response;
        }
    }
}
"@ -ErrorAction SilentlyContinue
        $response = [PSCustomObject]@{ StatusCode = $StatusCode }
        return [Microsoft.PowerShell.Commands.HttpResponseException]::new('err', $response)
    }
}

Describe 'New-TransientNetworkRetryStrategy' {

    It 'returns a hashtable with Name and ShouldRetry keys' {
        $strategy = New-TransientNetworkRetryStrategy

        $strategy           | Should -BeOfType [hashtable]
        $strategy.Keys      | Should -Contain 'Name'
        $strategy.Keys      | Should -Contain 'ShouldRetry'
        $strategy.ShouldRetry | Should -BeOfType [scriptblock]
    }

    It 'sets Name to TransientNetwork' {
        (New-TransientNetworkRetryStrategy).Name | Should -Be 'TransientNetwork'
    }
}

Describe 'New-TransientNetworkRetryStrategy ShouldRetry predicate' {

    BeforeAll {
        $script:predicate = (New-TransientNetworkRetryStrategy).ShouldRetry
    }

    It 'returns true for HttpRequestException (DNS / connect failure)' {
        $inner = [System.Net.Sockets.SocketException]::new()
        $ex    = [System.Net.Http.HttpRequestException]::new('dns', $inner)
        $rec   = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true for a nested SocketException only reachable via InnerException' {
        # The wrapper (Exception) is a vanilla System.Exception - not on the
        # transient list. The walker must descend into InnerException to find
        # the SocketException underneath.
        $inner = [System.Net.Sockets.SocketException]::new()
        $outer = [Exception]::new('wrapped', $inner)
        $rec   = New-TestErrorRecord -Exception $outer

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true for a 5xx HttpResponseException (server error)' {
        $ex  = New-FakeHttpResponseException -StatusCode 503
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns false for a 4xx HttpResponseException (client error)' {
        # Client errors are permanent - retrying a 404 will keep producing 404.
        $ex  = New-FakeHttpResponseException -StatusCode 404
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeFalse
    }

    It 'returns false for a non-network exception (string throw / RuntimeException)' {
        # Mocks elsewhere throw plain strings; the retry layer must not
        # incur delays on those.
        $ex  = [System.Management.Automation.RuntimeException]::new('boom')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeFalse
    }
}

Describe 'New-TransientNetworkRetryStrategy message-based fallback' {
    # Path 2 of the predicate: used when an upstream layer wraps the
    # typed exception and only the text remains (the PowerShellGet
    # wrapped-exception problem). The patterns intentionally overlap
    # with the type-based cases above so the same underlying failure
    # surfaces transient regardless of which detection path runs.

    BeforeAll {
        $script:predicate = (New-TransientNetworkRetryStrategy).ShouldRetry
    }

    It 'returns true for "remote name could not be resolved" in Exception.Message (DNS)' {
        # The wrapped form of System.Net.Sockets.SocketException - same
        # underlying failure but the type was lost upstream.
        $ex  = [Exception]::new(
            'The remote name could not be resolved: ' +
            "'www.powershellgallery.com'")
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true when the transient signal lives only in ErrorDetails.Message' {
        # PowerShellGet sometimes populates ErrorDetails with the
        # operator-facing text while Exception.Message stays generic.
        $ex  = [Exception]::new('generic wrapper')
        $rec = New-TestErrorRecord -Exception $ex `
                   -ErrorDetailsMessage 'The operation has timed out.'

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true for "Unable to connect to the remote server"' {
        $ex  = [Exception]::new('Unable to connect to the remote server')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true for HTTP 503 Service Unavailable in message text' {
        # Wrapped form of a 5xx HttpResponseException.
        $ex  = [Exception]::new(
            'The remote server returned an error: (503) Service Unavailable.')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true for HTTP 502 Bad Gateway in message text' {
        $ex  = [Exception]::new(
            'The remote server returned an error: (502) Bad Gateway.')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns false for a non-network message even when no type matches' {
        # Path 1 yields false (no transient type in the chain). Path 2
        # yields false (text does not match any pattern). End result
        # must be false so a generic error does not soak up retries.
        $ex  = [Exception]::new(
            'No match was found for the specified search criteria.')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeFalse
    }
}
