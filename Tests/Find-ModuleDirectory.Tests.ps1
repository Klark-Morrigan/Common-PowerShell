BeforeAll {
    . "$PSScriptRoot\..\.github\actions\lib\Find-ModuleDirectory.ps1"
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
