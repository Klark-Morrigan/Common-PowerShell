BeforeAll {

    . "$PSScriptRoot\..\.github\actions\lib\Get-LintExcludePatterns.ps1"
    . "$PSScriptRoot\..\.github\actions\lib\Test-LintPathExcluded.ps1"
    . "$PSScriptRoot\..\.github\actions\lib\Get-LintFiles.ps1"

    # Per-test fixture builder. Drops a tree under $TestDrive with
    # operator-chosen contents and returns the root path.
    function New-LintFilesFixture {

        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [string[]] $RelativePaths
        )

        $root = Join-Path $TestDrive $Name

        foreach ($rel in $RelativePaths) {

            $full = Join-Path $root $rel
            New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
            Set-Content -Path $full -Value "'content'"
        }

        return $root
    }
}

Describe 'Get-LintFiles' {

    BeforeEach {

        Mock Get-LintExcludePatterns { return ,@('shared-pattern') }
        Mock Test-LintPathExcluded { return $FilePath -like '*\excluded\*' }
    }

    It 'returns the files with a listed extension that the path check keeps' {

        $root = New-LintFilesFixture -Name 'mixed' -RelativePaths @(
            'src\A.ps1', 'src\B.psm1', 'notes.txt', 'excluded\C.ps1'
        )

        $files = Get-LintFiles -SourceRoot $root -Extensions '.ps1', '.psm1'

        $files.Name | Sort-Object | Should -Be @('A.ps1', 'B.psm1')
    }

    It 'checks each file against the patterns it is given' {

        $root = New-LintFilesFixture -Name 'passedPatterns' -RelativePaths @('A.ps1')

        Get-LintFiles -SourceRoot $root -Extensions '.ps1' -ExcludePatterns 'given-pattern' | Out-Null

        Should -Invoke Test-LintPathExcluded -Times 1 -Exactly -ParameterFilter {
            $ExcludePatterns -contains 'given-pattern'
        }
    }

    It 'checks each file against the shared exclusions when none are passed' {

        $root = New-LintFilesFixture -Name 'sharedPatterns' -RelativePaths @('A.ps1')

        Get-LintFiles -SourceRoot $root -Extensions '.ps1' | Out-Null

        Should -Invoke Test-LintPathExcluded -Times 1 -Exactly -ParameterFilter {
            $ExcludePatterns -contains 'shared-pattern'
        }
    }

    It 'returns a single file as a one-element array' {

        $root = New-LintFilesFixture -Name 'oneFile' -RelativePaths @('Only.ps1')
        $files = Get-LintFiles -SourceRoot $root -Extensions '.ps1'

        ($files -is [array]) | Should -BeTrue
        $files.Count         | Should -Be 1
    }

    It 'returns an empty array when no file matches' {

        $root = New-LintFilesFixture -Name 'noFiles' -RelativePaths @('notes.txt')
        $files = Get-LintFiles -SourceRoot $root -Extensions '.ps1'

        ($files -is [array]) | Should -BeTrue
        $files.Count         | Should -Be 0
    }
}
