BeforeAll {

    . "$PSScriptRoot\..\.github\actions\lib\Write-LintReport.ps1"

    $script:DescribeHit = { param($hit) "found $($hit.Path)" }
}

Describe 'Write-LintReport' {

    It 'prints the pass line and returns 0 when there are no hits' {

        $exitCode = Write-LintReport -Hits @() -PassMessage 'nothing found.' -DescribeHit $script:DescribeHit `
            -FindingLabel 'finding(s)' -InformationVariable printed -InformationAction SilentlyContinue

        $exitCode                             | Should -Be 0
        @($printed | ForEach-Object { "$_" }) | Should -Be @('Lint OK: nothing found.')
    }

    It 'prints an annotation per hit and the failure count, and returns 1' {

        $hits = @(
            [pscustomobject]@{ Path = 'C:\repo\A.ps1'; LineNumber = 3 }
            [pscustomobject]@{ Path = 'C:\repo\B.ps1'; LineNumber = 7 }
        )

        $exitCode = Write-LintReport -Hits $hits -PassMessage 'nothing found.' -DescribeHit $script:DescribeHit `
            -FindingLabel 'finding(s)' -InformationVariable printed -InformationAction SilentlyContinue

        $exitCode                             | Should -Be 1
        @($printed | ForEach-Object { "$_" }) | Should -Be @(
            '::error file=C:\repo\A.ps1,line=3::found C:\repo\A.ps1'
            '::error file=C:\repo\B.ps1,line=7::found C:\repo\B.ps1'
            'Lint FAILED: 2 finding(s) found.'
        )
    }
}
