BeforeAll {
    . "$PSScriptRoot\..\.github\actions\check-version-is-new\Test-ManifestVersionIsNew.ps1"
}

Describe 'Test-ManifestVersionIsNew' {

    BeforeEach {
        Mock Import-PowerShellDataFile {
            [PSCustomObject]@{ ModuleVersion = '1.0.2' }
        }
    }

    Context 'when the version is not on PSGallery' {

        BeforeEach {
            # Find-Module returns nothing when the exact version is absent.
            Mock Find-Module { }
        }

        It 'returns true' {
            Test-ManifestVersionIsNew -Psd1 'Module\MyModule.psd1' | Should -BeTrue
        }

        It 'queries the gallery by the manifest base name and required version' {
            Test-ManifestVersionIsNew -Psd1 'Module\MyModule.psd1' | Out-Null
            Should -Invoke Find-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'MyModule' -and
                $RequiredVersion -eq '1.0.2' -and
                $Repository -eq 'PSGallery'
            }
        }

        It 'reads the version from the provided psd1 path' {
            Test-ManifestVersionIsNew -Psd1 'Module\MyModule.psd1' | Out-Null
            Should -Invoke Import-PowerShellDataFile -Times 1 `
                -ParameterFilter { $Path -eq 'Module\MyModule.psd1' }
        }

        It 'writes version_is_new=true to GITHUB_OUTPUT' {
            $env:GITHUB_OUTPUT = "$TestDrive\gh-output-new.txt"
            try {
                Test-ManifestVersionIsNew -Psd1 'Module\MyModule.psd1' | Out-Null
                Get-Content $env:GITHUB_OUTPUT | Should -Contain 'version_is_new=true'
            } finally {
                Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'when the version is already published to PSGallery' {

        BeforeEach {
            # A returned object means the exact version is already on the gallery.
            Mock Find-Module { [PSCustomObject]@{ Name = 'MyModule'; Version = '1.0.2' } }
        }

        It 'returns false' {
            Test-ManifestVersionIsNew -Psd1 'Module\MyModule.psd1' | Should -BeFalse
        }

        It 'writes version_is_new=false to GITHUB_OUTPUT' {
            $env:GITHUB_OUTPUT = "$TestDrive\gh-output-published.txt"
            try {
                Test-ManifestVersionIsNew -Psd1 'Module\MyModule.psd1' | Out-Null
                Get-Content $env:GITHUB_OUTPUT | Should -Contain 'version_is_new=false'
            } finally {
                Remove-Item Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue
            }
        }
    }
}
