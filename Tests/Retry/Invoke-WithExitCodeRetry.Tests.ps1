BeforeAll {
    # Dot-source the loop plus the default-backoff factory it falls back to
    # when no -BackoffStrategy is supplied.
    . "$PSScriptRoot\..\..\Common.PowerShell\Private\Retry\Assert-RetryStrategyShape.ps1"
    . "$PSScriptRoot\..\..\Common.PowerShell\Public\Retry\BackoffStrategies\New-ExponentialBackoffStrategy.ps1"
    . "$PSScriptRoot\..\..\Common.PowerShell\Public\Retry\Invoke-WithExitCodeRetry.ps1"

    # Test-only zero-delay backoff so the suite stays fast and deterministic.
    function New-NoSleepBackoff {
        @{
            Name     = 'NoSleep'
            GetDelay = { param($Attempt, $ExitCode) 0 }
        }
    }

    # Exit-code plan consumed by $script:_planBlock. Set-ExitCodePlan stages
    # one exit code per attempt (last value repeated if the loop overruns)
    # and resets the call counter. $script:_planBlock is a plain block (NOT
    # a closure) defined in this file's scope, so its $script: references
    # resolve to the same scope Set-ExitCodePlan and the assertions use -
    # GetNewClosure would rebind $script: to a private module scope and the
    # counter would be invisible here. Native commands set $LASTEXITCODE
    # globally; the block mirrors that so the loop reads it exactly as it
    # would after a real `& netsh ...`.
    $script:_planBlock = {
        $idx = [Math]::Min($script:_calls, $script:_codes.Count - 1)
        $script:_calls++
        $global:LASTEXITCODE = $script:_codes[$idx]
        "out-$($script:_calls)"
    }
    function Set-ExitCodePlan {
        param([int[]] $Codes)
        $script:_codes = $Codes
        $script:_calls = 0
    }
}

Describe 'Invoke-WithExitCodeRetry - happy path' {

    It 'returns the block output on first-attempt success without sleeping' {
        # Backoff throws so the test fails loudly if the loop ever sleeps on
        # a successful first attempt.
        $explodingBackoff = @{
            Name     = 'Exploding'
            GetDelay = { param($a, $e) throw 'GetDelay must not be called on success' }
        }
        Set-ExitCodePlan -Codes @(0)

        $result = Invoke-WithExitCodeRetry `
            -BackoffStrategy $explodingBackoff `
            -ScriptBlock     $script:_planBlock

        $result        | Should -Be 'out-1'
        $script:_calls | Should -Be 1
    }
}

Describe 'Invoke-WithExitCodeRetry - parameter validation' {

    It 'throws when -ScriptBlock is omitted (mandatory)' {
        { Invoke-WithExitCodeRetry } | Should -Throw
    }

    It 'throws a descriptive error when the backoff strategy is missing GetDelay' {
        $badBackoff = @{ Name = 'Broken' }

        { Invoke-WithExitCodeRetry `
            -BackoffStrategy $badBackoff `
            -ScriptBlock     { $global:LASTEXITCODE = 0 }
        } | Should -Throw "*'GetDelay'*"
    }
}

Describe 'Invoke-WithExitCodeRetry - retry decision' {

    It 'retries while the exit code is non-zero and stops on success' {
        Set-ExitCodePlan -Codes @(1, 1, 0)

        $result = Invoke-WithExitCodeRetry `
            -BackoffStrategy (New-NoSleepBackoff) `
            -ScriptBlock     $script:_planBlock

        $result        | Should -Be 'out-3'
        $script:_calls | Should -Be 3
    }

    It 'gives up after MaxAttempts and throws with the exit code and count' {
        Set-ExitCodePlan -Codes @(7)

        { Invoke-WithExitCodeRetry `
            -BackoffStrategy (New-NoSleepBackoff) `
            -MaxAttempts     3 `
            -ScriptBlock     $script:_planBlock
        } | Should -Throw '*exit 7 after 3 attempts*'

        $script:_calls | Should -Be 3
    }

    It 'fails fast (single call, no sleep) on an exit code outside -RetryableExitCode' {
        # GetDelay throws so the test fails if the loop ever sleeps on a
        # non-retryable failure - the strongest guarantee no retry happened.
        $explodingBackoff = @{
            Name     = 'Exploding'
            GetDelay = { param($a, $e) throw 'must not sleep on non-retryable' }
        }
        Set-ExitCodePlan -Codes @(1)

        { Invoke-WithExitCodeRetry `
            -BackoffStrategy    $explodingBackoff `
            -RetryableExitCode  2 `
            -ScriptBlock        $script:_planBlock
        } | Should -Throw '*non-retryable exit 1*'

        $script:_calls | Should -Be 1
    }

    It 'retries only the listed codes when -RetryableExitCode is set' {
        Set-ExitCodePlan -Codes @(1, 0)

        $result = Invoke-WithExitCodeRetry `
            -BackoffStrategy   (New-NoSleepBackoff) `
            -RetryableExitCode 1 `
            -ScriptBlock       $script:_planBlock

        $result        | Should -Be 'out-2'
        $script:_calls | Should -Be 2
    }
}

Describe 'Invoke-WithExitCodeRetry - backoff integration' {

    It 'invokes GetDelay with the attempt number and a null error slot' {
        # The shared backoff strategies type their second GetDelay
        # parameter as [ErrorRecord]; an exit-code failure has none, so the
        # loop passes $null. Verifying that keeps the loop compatible with
        # every existing strategy (an int there would fail type coercion).
        $script:_delayCalls = New-Object System.Collections.Generic.List[object]
        $fakeBackoff = @{
            Name     = 'Fake'
            GetDelay = {
                param($Attempt, $LastError)
                $script:_delayCalls.Add([pscustomobject]@{ Attempt = $Attempt; LastError = $LastError })
                return 0
            }
        }
        Set-ExitCodePlan -Codes @(4, 5, 0)

        Invoke-WithExitCodeRetry `
            -BackoffStrategy $fakeBackoff `
            -MaxAttempts     3 `
            -ScriptBlock     $script:_planBlock | Out-Null

        # Two failures before the third-attempt success -> two GetDelay calls.
        $script:_delayCalls.Count        | Should -Be 2
        $script:_delayCalls[0].Attempt   | Should -Be 1
        $script:_delayCalls[0].LastError | Should -BeNullOrEmpty
        $script:_delayCalls[1].Attempt   | Should -Be 2
        $script:_delayCalls[1].LastError | Should -BeNullOrEmpty
    }

    It 'defaults to New-ExponentialBackoffStrategy when -BackoffStrategy is omitted' {
        $script:_observedDelays = @()
        # Shadow Start-Sleep in this scope only - keeps the suite fast and
        # Pester-version agnostic.
        function Start-Sleep {
            param([int] $Seconds)
            $script:_observedDelays += $Seconds
        }
        Set-ExitCodePlan -Codes @(1)

        try {
            Invoke-WithExitCodeRetry `
                -MaxAttempts 3 `
                -ScriptBlock $script:_planBlock | Out-Null
        } catch { } # exhaustion is expected; we only care about the delays

        # Exponential defaults: 2 * 2^(attempt - 1) capped at 30 -> 2, 4.
        $script:_observedDelays | Should -Be @(2, 4)
    }
}

Describe 'Invoke-WithExitCodeRetry - warning output' {

    It 'surfaces OperationName and the exit code in the retry warning' {
        Set-ExitCodePlan -Codes @(1, 0)

        Invoke-WithExitCodeRetry `
            -OperationName   'netsh portproxy add' `
            -BackoffStrategy (New-NoSleepBackoff) `
            -MaxAttempts     2 `
            -WarningAction   SilentlyContinue `
            -WarningVariable warnings `
            -ScriptBlock     $script:_planBlock | Out-Null

        $warnings.Count      | Should -Be 1
        [string]$warnings[0] | Should -Match 'netsh portproxy add'
        [string]$warnings[0] | Should -Match 'exit 1'
    }
}
