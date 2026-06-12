# Integration test: verifies Limit-TestLogRetention actually dot-sources and
# drives the shared Limit-RetainedItem logrotate helper (two connected units),
# not just its own guard logic. Runs host-side, no Docker required, so it is
# discovered and run by the normal unit suite.
BeforeAll {
    . "$PSScriptRoot\..\.github\actions\run-unit-tests\lib\Limit-TestLogRetention.ps1"
    $Script:RetainedItemHelper =
        (Resolve-Path "$PSScriptRoot\..\PowerShell.Common\Public\Limit-RetainedItem.ps1").Path
}

Describe 'Limit-TestLogRetention.IntegrationTests' {

    It 'keeps the N most-recent logs and prunes the rest via Limit-RetainedItem' {
        $dir = Join-Path $TestDrive 'logs'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $now = Get-Date
        0..4 | ForEach-Object {
            $path = Join-Path $dir "run-$_.log"
            Set-Content -LiteralPath $path -Value 'log content'
            (Get-Item -LiteralPath $path).LastWriteTime = $now.AddDays(-$_)
        }

        Limit-TestLogRetention -LogDirectory           $dir `
                               -Filter                 '*.log' `
                               -MaxItems               2 `
                               -RetainedItemHelperPath $Script:RetainedItemHelper

        $remaining = @(Get-ChildItem -Path $dir -File)
        $remaining.Count | Should -Be 2
        $remaining.Name  | Should -Contain 'run-0.log'
        $remaining.Name  | Should -Contain 'run-1.log'
    }
}
