BeforeAll {

    . "$PSScriptRoot\..\.github\actions\lib\Write-LintReport.ps1"

    # The message leaves the path out, so only the report itself can name it.
    $script:DescribeHit = { param($hit) "problem on line $($hit.LineNumber)" }
}

Describe 'Write-LintReport' {

    It 'prints the pass line and returns 0 when there are no hits' {

        $exitCode = Write-LintReport `
            -Hits @() `
            -PassMessage 'nothing found.' `
            -DescribeHit $script:DescribeHit `
            -FindingLabel 'finding(s)' `
            -InformationVariable printed `
            -InformationAction SilentlyContinue

        $exitCode |
            Should -Be 0

        @($printed |
            ForEach-Object { "$_" }) |
            Should -Be @('Lint OK: nothing found.')
    }

    # GitHub's log view keeps only an annotation's message, so the plain line
    # under it is what names the file and line there.
    It 'prints an annotation and its location per hit, then the failure count, and returns 1' {

        $hits = @(
            [pscustomobject]@{ Path = 'C:\repo\A.ps1'; LineNumber = 3 }
            [pscustomobject]@{ Path = 'C:\repo\B.ps1'; LineNumber = 7 }
        )

        $exitCode = Write-LintReport `
            -Hits $hits `
            -PassMessage 'nothing found.' `
            -DescribeHit $script:DescribeHit `
            -FindingLabel 'finding(s)' `
            -InformationVariable printed `
            -InformationAction SilentlyContinue

        $exitCode |
            Should -Be 1

        @($printed |
            ForEach-Object { "$_" }) |
            Should -Be @(
                '::error file=C:\repo\A.ps1,line=3::problem on line 3'
                '  C:\repo\A.ps1:3'
                '::error file=C:\repo\B.ps1,line=7::problem on line 7'
                '  C:\repo\B.ps1:7'
                'Lint FAILED: 2 finding(s) found.'
            )
    }
}
