BeforeAll {
    # wsl stub - uses $args to avoid parameter-binding conflicts with the
    # -d / -- / -c flags passed by the function. Tests redefine via Mock.
    function wsl { $global:LASTEXITCODE = 0 }

    . "$PSScriptRoot\..\PowerShell.Common\Public\Assert-WslHasBash.ps1"
}

Describe 'Assert-WslHasBash' {

    Context 'bash is on PATH' {

        It 'returns without throwing when the probe exits 0' {
            # `command -v bash` resolves to a path and exits 0 - simulate
            # the typical Ubuntu / Debian state.
            Mock wsl { $global:LASTEXITCODE = 0; return '/usr/bin/bash' }

            { Assert-WslHasBash } | Should -Not -Throw
        }

        It 'targets the default distro when -DistroName is omitted' {
            Mock wsl { $global:LASTEXITCODE = 0; return '/usr/bin/bash' }

            Assert-WslHasBash

            # No -d flag in argv when DistroName is unset.
            Should -Invoke wsl -Times 1 `
                -ParameterFilter { -not ($args -contains '-d') }
        }

        It 'passes -d <name> through to wsl when DistroName is supplied' {
            Mock wsl { $global:LASTEXITCODE = 0; return '/usr/bin/bash' }

            Assert-WslHasBash -DistroName 'Ubuntu-24.04'

            # Both -d and the supplied distro name should appear in argv.
            Should -Invoke wsl -Times 1 `
                -ParameterFilter {
                    ($args -contains '-d') -and ($args -contains 'Ubuntu-24.04')
                }
        }
    }

    Context 'bash is missing' {
        # ------------------------------------------------------------------
        # Mirrors the Wsl2NotReady contract from Assert-Wsl2Ready: callers
        # catch the WslMissingBash: prefix to surface a clear remediation
        # hint rather than re-deriving the diagnosis from a deeper failure
        # later in the bridge chain.

        It 'throws WslMissingBash when command -v bash exits non-zero' {
            # docker-desktop's shape: probe exits 1, no output.
            Mock wsl { $global:LASTEXITCODE = 1; return '' }

            { Assert-WslHasBash } |
                Should -Throw -ExpectedMessage 'WslMissingBash:*'
        }

        It 'mentions the default distro hint when DistroName is omitted' {
            # No name passed, so the message points the operator at
            # `wsl --list --verbose` and the docker-desktop remediation.
            Mock wsl { $global:LASTEXITCODE = 1; return '' }

            { Assert-WslHasBash } |
                Should -Throw -ExpectedMessage '*docker-desktop*'
        }

        It 'names the failing distro in the thrown message when DistroName is supplied' {
            Mock wsl { $global:LASTEXITCODE = 1; return '' }

            { Assert-WslHasBash -DistroName 'my-distro' } |
                Should -Throw -ExpectedMessage "*my-distro*"
        }

        It 'surfaces the probe exit code in the thrown message' {
            # Non-1 exit (e.g. wsl itself errored) must reach the operator
            # so they can tell "bash not found" from "distro not running".
            Mock wsl { $global:LASTEXITCODE = 42; return 'distro not started' }

            { Assert-WslHasBash } |
                Should -Throw -ExpectedMessage '*exit 42*'
        }
    }
}
