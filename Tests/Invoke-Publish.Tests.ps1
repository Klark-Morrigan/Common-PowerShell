BeforeAll {
    . "$PSScriptRoot\..\.github\actions\publish\Invoke-Publish.ps1"
}

Describe 'Invoke-Publish' {

    Context 'no .psd1 found under SearchRoot' {
        It 'throws' {
            New-Item -ItemType Directory -Path "$TestDrive\empty" -Force | Out-Null
            { Invoke-Publish -SearchRoot "$TestDrive\empty" } | Should -Throw
        }
    }

    Context 'manifest has no RequiredModules' {
        BeforeAll {
            $modDir = New-Item -ItemType Directory -Path "$TestDrive\no-deps\MyModule" -Force
            "@{ ModuleVersion = '1.0.0' }" | Set-Content "$($modDir.FullName)\MyModule.psd1"
            $env:API_KEY = 'test-key'
        }
        AfterAll  { Remove-Item Env:\API_KEY -ErrorAction SilentlyContinue }
        BeforeEach {
            Mock Install-Module {}
            Mock Publish-Module {}
            Invoke-Publish -SearchRoot "$TestDrive\no-deps"
        }

        It 'does not call Install-Module' {
            Should -Not -Invoke Install-Module
        }

        It 'calls Publish-Module once' {
            Should -Invoke Publish-Module -Times 1 -Exactly
        }
    }

    Context 'RequiredModules declared as strings' {
        BeforeAll {
            $modDir = New-Item -ItemType Directory -Path "$TestDrive\string-deps\MyModule" -Force
            "@{ ModuleVersion = '1.0.0'; RequiredModules = @('ModA', 'ModB') }" |
                Set-Content "$($modDir.FullName)\MyModule.psd1"
            $env:API_KEY = 'test-key'
        }
        AfterAll  { Remove-Item Env:\API_KEY -ErrorAction SilentlyContinue }
        BeforeEach {
            Mock Install-Module {}
            Mock Publish-Module {}
            Invoke-Publish -SearchRoot "$TestDrive\string-deps"
        }

        It 'calls Install-Module once per dependency' {
            Should -Invoke Install-Module -Times 2 -Exactly
        }

        It 'installs ModA by name' {
            Should -Invoke Install-Module -ParameterFilter { $Name -eq 'ModA' }
        }

        It 'installs ModB by name' {
            Should -Invoke Install-Module -ParameterFilter { $Name -eq 'ModB' }
        }

        It 'calls Publish-Module once' {
            Should -Invoke Publish-Module -Times 1 -Exactly
        }
    }

    Context 'RequiredModules declared as hashtables' {
        BeforeAll {
            $modDir = New-Item -ItemType Directory -Path "$TestDrive\hash-deps\MyModule" -Force
            "@{ ModuleVersion = '1.0.0'; RequiredModules = @(@{ ModuleName = 'ModC'; ModuleVersion = '2.0' }) }" |
                Set-Content "$($modDir.FullName)\MyModule.psd1"
            $env:API_KEY = 'test-key'
        }
        AfterAll  { Remove-Item Env:\API_KEY -ErrorAction SilentlyContinue }
        BeforeEach {
            Mock Install-Module {}
            Mock Publish-Module {}
            Invoke-Publish -SearchRoot "$TestDrive\hash-deps"
        }

        It 'installs the module named in ModuleName' {
            Should -Invoke Install-Module -ParameterFilter { $Name -eq 'ModC' }
        }
    }

    Context 'RequiredModules mix of strings and hashtables' {
        BeforeAll {
            $modDir = New-Item -ItemType Directory -Path "$TestDrive\mixed-deps\MyModule" -Force
            "@{ ModuleVersion = '1.0.0'; RequiredModules = @('StringMod', @{ ModuleName = 'HashMod' }) }" |
                Set-Content "$($modDir.FullName)\MyModule.psd1"
            $env:API_KEY = 'test-key'
        }
        AfterAll  { Remove-Item Env:\API_KEY -ErrorAction SilentlyContinue }
        BeforeEach {
            Mock Install-Module {}
            Mock Publish-Module {}
            Invoke-Publish -SearchRoot "$TestDrive\mixed-deps"
        }

        It 'installs the string dependency' {
            Should -Invoke Install-Module -ParameterFilter { $Name -eq 'StringMod' }
        }

        It 'installs the hashtable dependency' {
            Should -Invoke Install-Module -ParameterFilter { $Name -eq 'HashMod' }
        }
    }
}
