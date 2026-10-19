BeforeAll {
    $Script:ScriptPath = "$PSScriptRoot\..\.github\actions\run-integration-tests\Run-IntegrationTests.ps1"
    . $Script:ScriptPath
}

Describe 'ConvertTo-TestFileInfos' {

    Context 'single path' {
        It 'returns one FileInfo with the correct name' {
            $result = ConvertTo-TestFileInfos -CsvPaths 'C:\repo\Tests\Foo.Tests.ps1'
            $result.Count      | Should -Be 1
            $result[0].Name    | Should -Be 'Foo.Tests.ps1'
        }
    }

    Context 'multiple paths' {
        It 'returns one FileInfo per entry' {
            $result = ConvertTo-TestFileInfos -CsvPaths 'C:\repo\A.Tests.ps1,C:\repo\B.Tests.ps1'
            $result.Count | Should -Be 2
        }

        It 'preserves the correct file names' {
            $result = ConvertTo-TestFileInfos -CsvPaths 'C:\repo\A.Tests.ps1,C:\repo\B.Tests.ps1'
            $result[0].Name | Should -Be 'A.Tests.ps1'
            $result[1].Name | Should -Be 'B.Tests.ps1'
        }
    }

    Context 'empty string' {
        It 'returns an empty array' {
            $result = ConvertTo-TestFileInfos -CsvPaths ''
            $result.Count | Should -Be 0
        }
    }

    Context 'consecutive commas produce empty entries' {
        It 'drops the empty entries' {
            $result = ConvertTo-TestFileInfos -CsvPaths 'C:\repo\A.Tests.ps1,,C:\repo\B.Tests.ps1'
            $result.Count | Should -Be 2
        }
    }
}

Describe 'Get-ContainerRelativePath' {

    Context 'file nested under root' {
        It 'prefixes with /repo/ and normalises backslashes' {
            $root   = 'C:\repo'
            $file   = [System.IO.FileInfo]'C:\repo\Tests\Foo.Tests.ps1'
            $result = Get-ContainerRelativePath -ResolvedRoot $root -File $file
            $result | Should -Be '/repo/Tests/Foo.Tests.ps1'
        }
    }

    Context 'file directly under root' {
        It 'returns a single-level path' {
            $root   = 'C:\repo'
            $file   = [System.IO.FileInfo]'C:\repo\Foo.Tests.ps1'
            $result = Get-ContainerRelativePath -ResolvedRoot $root -File $file
            $result | Should -Be '/repo/Foo.Tests.ps1'
        }
    }

    Context 'deeply nested file' {
        It 'preserves all path segments' {
            $root   = 'C:\repo'
            $file   = [System.IO.FileInfo]'C:\repo\Tests\Integration.DockerHost\Sub\Foo.Tests.ps1'
            $result = Get-ContainerRelativePath -ResolvedRoot $root -File $file
            $result | Should -Be '/repo/Tests/Integration.DockerHost/Sub/Foo.Tests.ps1'
        }
    }
}
