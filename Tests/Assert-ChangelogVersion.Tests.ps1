BeforeAll {
    . "$PSScriptRoot\..\.github\actions\assert-changelog-version\Assert-ChangelogVersion.ps1"
}

Describe 'Assert-ChangelogVersion' {

    Context 'when the manifest and changelog versions match' {

        BeforeEach {
            Mock Import-PowerShellDataFile {
                [PSCustomObject]@{ ModuleVersion = '8.1.0' }
            }
            Mock Get-Content {
                '# Changelog', '', '## [Unreleased]', '',
                '## [8.1.0] - 2026-06-14', '### Added', '- A thing.', '',
                '## [8.0.0] - 2026-06-13'
            }
        }

        It 'does not throw' {
            { Assert-ChangelogVersion -Psd1 'm.psd1' -Changelog 'CHANGELOG.md' } |
                Should -Not -Throw
        }

        It 'skips the [Unreleased] heading when finding the latest version' {
            # The match must be 8.1.0 (first versioned heading), not Unreleased.
            { Assert-ChangelogVersion -Psd1 'm.psd1' } | Should -Not -Throw
        }

        It 'reads the manifest from the provided psd1 path' {
            Assert-ChangelogVersion -Psd1 'sub\m.psd1' | Out-Null
            Should -Invoke Import-PowerShellDataFile -Times 1 -Exactly `
                -ParameterFilter { $Path -eq 'sub\m.psd1' }
        }
    }

    Context 'when the versions diverge' {

        It 'throws naming both versions' {
            Mock Import-PowerShellDataFile {
                [PSCustomObject]@{ ModuleVersion = '8.2.0' }
            }
            Mock Get-Content {
                '## [Unreleased]', '## [8.1.0] - 2026-06-14'
            }

            { Assert-ChangelogVersion -Psd1 'm.psd1' } |
                Should -Throw '*ModuleVersion ''8.2.0''*does not match*''8.1.0''*'
        }
    }

    Context 'when the changelog has no version section' {

        It 'throws' {
            Mock Import-PowerShellDataFile {
                [PSCustomObject]@{ ModuleVersion = '8.1.0' }
            }
            Mock Get-Content { '# Changelog', '', '## [Unreleased]' }

            { Assert-ChangelogVersion -Psd1 'm.psd1' } |
                Should -Throw '*version section found*'
        }
    }

    Context 'when the manifest has no ModuleVersion' {

        It 'throws' {
            Mock Import-PowerShellDataFile { [PSCustomObject]@{ } }
            Mock Get-Content { '## [8.1.0] - 2026-06-14' }

            { Assert-ChangelogVersion -Psd1 'm.psd1' } |
                Should -Throw '*no ModuleVersion*'
        }
    }
}
