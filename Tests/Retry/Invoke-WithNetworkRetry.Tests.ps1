BeforeAll {
    # Dot-source both files so the loop function and its (relocated)
    # Test-TransientNetworkException helper both land in test scope.
    # The classifier tests themselves migrated to
    # New-TransientNetworkRetryStrategy.Tests.ps1 in step 1 of the
    # "generalise retry" plan; this file retains only the loop-behaviour
    # assertions, which step 3 will subsume into Invoke-WithRetry.Tests.ps1.
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Retry\TransientErrorStrategies\New-TransientNetworkRetryStrategy.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Retry\Invoke-WithNetworkRetry.ps1"
}

Describe 'Invoke-WithNetworkRetry' {

    It 'returns the script block result on first-attempt success' {
        $script:_callCount = 0
        $result = Invoke-WithNetworkRetry -ScriptBlock {
            $script:_callCount++
            return 'ok'
        }

        $result            | Should -Be 'ok'
        $script:_callCount | Should -Be 1
    }

    It 'retries a transient failure and returns the eventual success' {
        $script:_attempts = 0
        $result = Invoke-WithNetworkRetry `
            -InitialDelaySeconds 0 `
            -ScriptBlock {
                $script:_attempts++
                if ($script:_attempts -lt 3) {
                    throw [System.Net.Http.HttpRequestException]::new('dns')
                }
                return 'finally'
            }

        $result            | Should -Be 'finally'
        $script:_attempts  | Should -Be 3
    }

    It 'propagates a permanent failure immediately without retrying' {
        # A plain string throw is non-transient. Test runs in well under
        # 1 second; if the helper retried, the default 2s delay would
        # blow that budget.
        $script:_count = 0
        { Invoke-WithNetworkRetry -ScriptBlock {
            $script:_count++
            throw 'permanent'
        } } | Should -Throw

        $script:_count | Should -Be 1
    }

    It 'gives up after MaxAttempts transient failures and rethrows the underlying error' {
        $script:_tries = 0
        { Invoke-WithNetworkRetry `
              -MaxAttempts 3 `
              -InitialDelaySeconds 0 `
              -ScriptBlock {
                  $script:_tries++
                  throw [System.Net.Http.HttpRequestException]::new('dns')
              }
        } | Should -Throw

        $script:_tries | Should -Be 3
    }
}
