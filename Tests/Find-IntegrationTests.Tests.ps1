BeforeAll {
    $Script:ScriptPath = "$PSScriptRoot\..\.github\actions\scan-integration-tests\Find-IntegrationTests.ps1"
}

Describe 'Find-IntegrationTests' {

    Context 'no test files and no module dir' {
        BeforeAll {
            $testDir = New-Item -ItemType Directory -Path "$TestDrive\empty" -Force
            $Script:Result = & $Script:ScriptPath -TestDir $testDir.FullName
        }

        It 'returns HasTests = false' {
            $Script:Result.HasTests | Should -BeFalse
        }

        It 'returns empty TestFilePaths' {
            $Script:Result.TestFilePaths | Should -BeNullOrEmpty
        }

        It 'returns empty ModuleDir' {
            $Script:Result.ModuleDir | Should -BeNullOrEmpty
        }
    }

    Context 'test files exist' {
        BeforeAll {
            $testDir = New-Item -ItemType Directory -Path "$TestDrive\with-files" -Force
            New-Item -ItemType File -Path "$($testDir.FullName)\Foo.Tests.ps1" -Force | Out-Null
            New-Item -ItemType File -Path "$($testDir.FullName)\Bar.Tests.ps1" -Force | Out-Null
            $Script:Result = & $Script:ScriptPath -TestDir $testDir.FullName
        }

        It 'returns HasTests = true' {
            $Script:Result.HasTests | Should -BeTrue
        }

        It 'returns all discovered file paths' {
            $Script:Result.TestFilePaths | Should -HaveCount 2
        }

        It 'returns absolute paths' {
            $Script:Result.TestFilePaths | ForEach-Object {
                [System.IO.Path]::IsPathRooted($_) | Should -BeTrue
            }
        }

        It 'returns empty ModuleDir' {
            $Script:Result.ModuleDir | Should -BeNullOrEmpty
        }
    }

    Context 'module dir exists and CheckModuleDir is set' {
        BeforeAll {
            Push-Location $TestDrive
            $moduleName = 'MyModule'
            $moduleDir  = New-Item -ItemType Directory -Path "$TestDrive\$moduleName" -Force
            New-Item -ItemType File -Path "$($moduleDir.FullName)\$moduleName.psd1" -Force | Out-Null
            $testDir = New-Item -ItemType Directory -Path "$TestDrive\tests-empty" -Force
            $Script:Result = & $Script:ScriptPath -TestDir $testDir.FullName -CheckModuleDir
        }
        AfterAll { Pop-Location }

        It 'returns HasTests = true' {
            $Script:Result.HasTests | Should -BeTrue
        }

        It 'returns the module directory name' {
            $Script:Result.ModuleDir | Should -Be 'MyModule'
        }

        It 'returns empty TestFilePaths' {
            $Script:Result.TestFilePaths | Should -BeNullOrEmpty
        }
    }

    Context 'module dir exists but CheckModuleDir is not set' {
        BeforeAll {
            Push-Location $TestDrive
            $moduleName = 'MyModule'
            $moduleDir  = New-Item -ItemType Directory -Path "$TestDrive\$moduleName" -Force
            New-Item -ItemType File -Path "$($moduleDir.FullName)\$moduleName.psd1" -Force | Out-Null
            $testDir = New-Item -ItemType Directory -Path "$TestDrive\tests-empty2" -Force
            $Script:Result = & $Script:ScriptPath -TestDir $testDir.FullName
        }
        AfterAll { Pop-Location }

        It 'returns HasTests = false' {
            $Script:Result.HasTests | Should -BeFalse
        }

        It 'returns empty ModuleDir' {
            $Script:Result.ModuleDir | Should -BeNullOrEmpty
        }
    }

    Context 'GITHUB_OUTPUT is set' {
        BeforeAll {
            $testDir    = New-Item -ItemType Directory -Path "$TestDrive\gh-out" -Force
            New-Item -ItemType File -Path "$($testDir.FullName)\Foo.Tests.ps1" -Force | Out-Null
            $outputFile = "$TestDrive\github_output"
            $env:GITHUB_OUTPUT = $outputFile
            & $Script:ScriptPath -TestDir $testDir.FullName | Out-Null
            $Script:Lines = Get-Content $outputFile
        }
        AfterAll { Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue }

        It 'writes has-tests' {
            $Script:Lines | Should -Contain 'has-tests=true'
        }

        It 'writes test-file-paths' {
            $Script:Lines | Where-Object { $_ -like 'test-file-paths=*' } | Should -Not -BeNullOrEmpty
        }

        It 'writes module-dir' {
            $Script:Lines | Where-Object { $_ -like 'module-dir=*' } | Should -Not -BeNullOrEmpty
        }
    }
}
