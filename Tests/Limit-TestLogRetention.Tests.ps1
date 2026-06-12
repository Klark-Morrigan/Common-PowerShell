BeforeAll {
    . "$PSScriptRoot\..\.github\actions\run-unit-tests\lib\Limit-TestLogRetention.ps1"
}

Describe 'Limit-TestLogRetention' {

    Context 'retention disabled (-MaxItems 0)' {

        It 'returns without warning or throwing' {
            Mock Write-Warning {}
            { Limit-TestLogRetention -LogDirectory           $TestDrive `
                                     -Filter                 '*.log' `
                                     -MaxItems               0 `
                                     -RetainedItemHelperPath 'C:\does\not\exist.ps1' } |
                Should -Not -Throw
            Should -Invoke Write-Warning -Exactly -Times 0
        }
    }

    Context 'log directory not provided' {

        It 'returns without warning' {
            Mock Write-Warning {}
            Limit-TestLogRetention -LogDirectory           '' `
                                   -Filter                 '*.log' `
                                   -MaxItems               5 `
                                   -RetainedItemHelperPath 'C:\does\not\exist.ps1'
            Should -Invoke Write-Warning -Exactly -Times 0
        }
    }

    Context 'retention helper is missing' {

        It 'warns and returns rather than throwing' {
            Mock Write-Warning {}
            { Limit-TestLogRetention -LogDirectory           $TestDrive `
                                     -Filter                 '*.log' `
                                     -MaxItems               5 `
                                     -RetainedItemHelperPath "$TestDrive\missing-helper.ps1" } |
                Should -Not -Throw
            Should -Invoke Write-Warning -Exactly -Times 1
        }
    }
}
