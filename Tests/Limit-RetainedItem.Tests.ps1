BeforeAll {
    . "$PSScriptRoot\..\Common.PowerShell\Public\Limit-RetainedItem.ps1"

    function New-LogFile {
        param(
            [string]   $Directory,
            [string]   $Name,
            [datetime] $LastWriteTime
        )
        $path = Join-Path $Directory $Name
        Set-Content -LiteralPath $path -Value 'log content'
        (Get-Item -LiteralPath $path).LastWriteTime = $LastWriteTime
        $path
    }
}

Describe 'Limit-RetainedItem' {

    BeforeEach {
        $Script:Dir = Join-Path $TestDrive ("retention-$([guid]::NewGuid())")
        New-Item -ItemType Directory -Path $Script:Dir -Force | Out-Null
    }

    Context 'missing directory' {

        It 'returns silently without throwing' {
            $missing = Join-Path $TestDrive 'never-existed'
            { Limit-RetainedItem -Directory $missing -MaxItems 5 } |
                Should -Not -Throw
        }
    }

    Context 'count-based retention (-MaxItems)' {

        It 'keeps the N most recent items and drops the rest' {
            $now = Get-Date
            0..4 | ForEach-Object {
                New-LogFile -Directory $Script:Dir `
                            -Name      "log-$_.log" `
                            -LastWriteTime ($now.AddDays(-$_)) | Out-Null
            }

            Limit-RetainedItem -Directory $Script:Dir `
                               -Filter    '*.log' `
                               -MaxItems  2 `
                               -FileOnly

            $remaining = @(Get-ChildItem -Path $Script:Dir -File)
            $remaining.Count | Should -Be 2
            $remaining.Name | Should -Contain 'log-0.log'
            $remaining.Name | Should -Contain 'log-1.log'
        }

        It 'does nothing when item count is below MaxItems' {
            New-LogFile -Directory $Script:Dir -Name 'a.log' -LastWriteTime (Get-Date) | Out-Null
            New-LogFile -Directory $Script:Dir -Name 'b.log' -LastWriteTime (Get-Date) | Out-Null

            Limit-RetainedItem -Directory $Script:Dir `
                               -Filter    '*.log' `
                               -MaxItems  10 `
                               -FileOnly

            @(Get-ChildItem -Path $Script:Dir -File).Count | Should -Be 2
        }
    }

    Context 'age-based retention (-MaxAgeDays)' {

        It 'drops items older than the cutoff' {
            $now = Get-Date
            New-LogFile -Directory $Script:Dir -Name 'fresh.log' `
                        -LastWriteTime $now.AddDays(-3) | Out-Null
            New-LogFile -Directory $Script:Dir -Name 'stale.log' `
                        -LastWriteTime $now.AddDays(-31) | Out-Null

            Limit-RetainedItem -Directory  $Script:Dir `
                               -Filter     '*.log' `
                               -MaxAgeDays 30 `
                               -FileOnly

            $remaining = @(Get-ChildItem -Path $Script:Dir -File)
            $remaining.Name | Should -Contain 'fresh.log'
            $remaining.Name | Should -Not -Contain 'stale.log'
        }
    }

    Context 'both dimensions combined' {

        It 'applies age first, then keeps the N most-recent survivors' {
            $now = Get-Date
            New-LogFile -Directory $Script:Dir -Name 'recent-1.log' -LastWriteTime $now.AddDays(-1)  | Out-Null
            New-LogFile -Directory $Script:Dir -Name 'recent-2.log' -LastWriteTime $now.AddDays(-2)  | Out-Null
            New-LogFile -Directory $Script:Dir -Name 'recent-3.log' -LastWriteTime $now.AddDays(-3)  | Out-Null
            New-LogFile -Directory $Script:Dir -Name 'old-1.log'    -LastWriteTime $now.AddDays(-40) | Out-Null
            New-LogFile -Directory $Script:Dir -Name 'old-2.log'    -LastWriteTime $now.AddDays(-50) | Out-Null

            Limit-RetainedItem -Directory  $Script:Dir `
                               -Filter     '*.log' `
                               -MaxItems   2 `
                               -MaxAgeDays 30 `
                               -FileOnly

            $remaining = @(Get-ChildItem -Path $Script:Dir -File)
            $remaining.Count   | Should -Be 2
            $remaining.Name    | Should -Contain 'recent-1.log'
            $remaining.Name    | Should -Contain 'recent-2.log'
        }
    }

    Context 'filter scope' {

        It 'leaves items outside the wildcard pattern alone' {
            $now = Get-Date
            New-LogFile -Directory $Script:Dir -Name 'one.log' `
                        -LastWriteTime $now.AddDays(-100) | Out-Null
            New-LogFile -Directory $Script:Dir -Name 'README.txt' `
                        -LastWriteTime $now.AddDays(-100) | Out-Null

            Limit-RetainedItem -Directory  $Script:Dir `
                               -Filter     '*.log' `
                               -MaxAgeDays 30 `
                               -FileOnly

            Test-Path -LiteralPath (Join-Path $Script:Dir 'README.txt') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $Script:Dir 'one.log')    | Should -BeFalse
        }
    }
}
