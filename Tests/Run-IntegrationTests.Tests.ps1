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

Describe 'Find-ModuleDirectory' {

    Context 'no subdirectory contains a matching .psd1' {
        BeforeAll {
            $testRoot = New-Item -ItemType Directory -Path "$TestDrive\no-module" -Force
            New-Item -ItemType Directory -Path "$TestDrive\no-module\Other" -Force | Out-Null
            $Script:Result = Find-ModuleDirectory -RootPath $testRoot.FullName
        }

        It 'returns null' {
            $Script:Result | Should -BeNullOrEmpty
        }
    }

    Context 'one subdirectory contains a matching .psd1' {
        BeforeAll {
            $testRoot = New-Item -ItemType Directory -Path "$TestDrive\with-module" -Force
            $modDir   = New-Item -ItemType Directory -Path "$TestDrive\with-module\MyModule" -Force
            New-Item -ItemType File -Path "$($modDir.FullName)\MyModule.psd1" -Force | Out-Null
            $Script:Result = Find-ModuleDirectory -RootPath $testRoot.FullName
        }

        It 'returns that directory' {
            $Script:Result | Should -Not -BeNullOrEmpty
            $Script:Result.Name | Should -Be 'MyModule'
        }
    }

    Context 'psd1 name does not match directory name' {
        BeforeAll {
            $testRoot = New-Item -ItemType Directory -Path "$TestDrive\mismatched" -Force
            $modDir   = New-Item -ItemType Directory -Path "$TestDrive\mismatched\SomeDir" -Force
            # psd1 has a different base name - should not match
            New-Item -ItemType File -Path "$($modDir.FullName)\Other.psd1" -Force | Out-Null
            $Script:Result = Find-ModuleDirectory -RootPath $testRoot.FullName
        }

        It 'returns null' {
            $Script:Result | Should -BeNullOrEmpty
        }
    }

    Context 'multiple subdirectories, only one matches' {
        BeforeAll {
            $testRoot = New-Item -ItemType Directory -Path "$TestDrive\multi" -Force
            New-Item -ItemType Directory -Path "$TestDrive\multi\Unrelated" -Force | Out-Null
            $modDir   = New-Item -ItemType Directory -Path "$TestDrive\multi\RealModule" -Force
            New-Item -ItemType File -Path "$($modDir.FullName)\RealModule.psd1" -Force | Out-Null
            $Script:Result = Find-ModuleDirectory -RootPath $testRoot.FullName
        }

        It 'returns the matching directory' {
            $Script:Result.Name | Should -Be 'RealModule'
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
