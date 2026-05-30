BeforeAll {
    . "$PSScriptRoot\..\scripts\Find-GitBashExecutable.ps1"
}

Describe 'Find-GitBashExecutable' {

    BeforeEach {
        # Unfiltered catch-all so calls that don't match the specific
        # filters below remain visible to Should -Invoke. See memory note
        # feedback_pester5_mock_fallthrough.
        Mock Get-Command { }
        Mock Test-Path { }
    }

    Context 'bash.exe is on PATH' {

        BeforeEach {
            Mock Get-Command -ParameterFilter { $Name -eq 'bash.exe' } {
                [pscustomobject]@{ Source = 'C:\Tools\bash.exe' }
            }
        }

        It 'returns the path reported by Get-Command' {
            Find-GitBashExecutable | Should -Be 'C:\Tools\bash.exe'
        }

        It 'does not look for git.exe (short-circuits after finding bash)' {
            Find-GitBashExecutable | Out-Null
            Should -Invoke Get-Command -Times 0 `
                -ParameterFilter { $Name -eq 'git.exe' }
        }
    }

    Context 'bash.exe is not on PATH but git.exe is and bash exists alongside it' {

        BeforeEach {
            # bash.exe lookup returns nothing; git.exe lookup returns a
            # plausible Git for Windows install path.
            Mock Get-Command -ParameterFilter { $Name -eq 'git.exe' } {
                [pscustomobject]@{ Source = 'C:\Program Files\Git\cmd\git.exe' }
            }
            # The function derives <git-install>\bin\bash.exe and probes it.
            Mock Test-Path -ParameterFilter {
                $LiteralPath -eq 'C:\Program Files\Git\bin\bash.exe'
            } { $true }
        }

        It 'returns the derived bash.exe path under the Git install bin dir' {
            Find-GitBashExecutable | Should -Be 'C:\Program Files\Git\bin\bash.exe'
        }

        It 'probes the derived path with Test-Path' {
            Find-GitBashExecutable | Out-Null
            Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq 'C:\Program Files\Git\bin\bash.exe'
            }
        }
    }

    Context 'bash.exe is not on PATH, git.exe is, but no bash.exe alongside it' {

        BeforeEach {
            Mock Get-Command -ParameterFilter { $Name -eq 'git.exe' } {
                [pscustomobject]@{ Source = 'C:\Program Files\Git\cmd\git.exe' }
            }
            # Catch-all Test-Path mock returns $null/falsy, so the derived
            # bash.exe is treated as absent.
        }

        It 'throws naming the derived path so the user knows where it looked' {
            { Find-GitBashExecutable } |
                Should -Throw "*C:\Program Files\Git\bin\bash.exe*"
        }
    }

    Context 'neither bash.exe nor git.exe is on PATH' {

        It 'throws with a Git-for-Windows install hint' {
            { Find-GitBashExecutable } |
                Should -Throw '*Install Git for Windows*'
        }

        It 'does not probe Test-Path (no candidate path to check)' {
            { Find-GitBashExecutable } | Should -Throw
            Should -Invoke Test-Path -Times 0
        }
    }
}
