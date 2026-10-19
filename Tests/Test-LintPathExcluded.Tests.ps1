BeforeAll {

    . "$PSScriptRoot\..\.github\actions\lib\Get-LintExcludePatterns.ps1"
    . "$PSScriptRoot\..\.github\actions\lib\Test-LintPathExcluded.ps1"
}

Describe 'Test-LintPathExcluded' {

    It 'excludes a file whose path relative to the root matches a pattern' {

        Test-LintPathExcluded -RootPath 'C:\repo' -FilePath 'C:\repo\Tests\X.Tests.ps1' `
            -ExcludePatterns @('^Tests([\\/]|$)') | Should -BeTrue
    }

    It 'keeps a file no pattern matches' {

        Test-LintPathExcluded -RootPath 'C:\repo' -FilePath 'C:\repo\src\X.ps1' `
            -ExcludePatterns @('^Tests([\\/]|$)') | Should -BeFalse
    }

    It 'matches against the relative path, not the root' {

        # The root itself holds "Tests"; only the part beneath it counts.
        Test-LintPathExcluded -RootPath 'C:\Tests' -FilePath 'C:\Tests\src\X.ps1' `
            -ExcludePatterns @('^Tests([\\/]|$)') | Should -BeFalse
    }

    It 'reads the shared exclusions when none are passed' {

        Mock Get-LintExcludePatterns { return ,@('^custom([\\/]|$)') }

        Test-LintPathExcluded -RootPath 'C:\repo' -FilePath 'C:\repo\custom\X.ps1' | Should -BeTrue
        Should -Invoke Get-LintExcludePatterns -Times 1 -Exactly
    }
}
