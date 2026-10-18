BeforeAll {

    . "$PSScriptRoot\..\.github\actions\lib\Get-LintExcludePatterns.ps1"

    function Test-MatchesAnyPattern {

        param([string] $RelativePath)

        return @(Get-LintExcludePatterns | Where-Object { $RelativePath -match $_ }).Count -gt 0
    }
}

Describe 'Get-LintExcludePatterns' {

    It 'returns the patterns as an array' {

        $patterns = Get-LintExcludePatterns

        ($patterns -is [array]) | Should -BeTrue
    }

    It 'covers the staged Common-PowerShell checkout' {
        Test-MatchesAnyPattern -RelativePath '.powershell-common\.github\actions\X.ps1' | Should -BeTrue
    }

    It 'leaves the repo''s own files alone' {
        Test-MatchesAnyPattern -RelativePath 'src\X.ps1' | Should -BeFalse
    }

    It 'leaves a folder whose name only starts like the checkout alone' {
        Test-MatchesAnyPattern -RelativePath '.powershell-common-notes\X.ps1' | Should -BeFalse
    }
}
