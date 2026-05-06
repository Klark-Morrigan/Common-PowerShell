BeforeAll {
    $Script:ScriptPath = "$PSScriptRoot\..\.github\actions\run-unit-tests\Run-Tests.ps1"
    . $Script:ScriptPath
}

Describe 'Get-UnitTestFiles' {

    Context 'no integration directories exist' {
        BeforeAll {
            $testsDir = New-Item -ItemType Directory -Path "$TestDrive\plain" -Force
            New-Item -ItemType File -Path "$TestDrive\plain\Foo.Tests.ps1"  -Force | Out-Null
            New-Item -ItemType File -Path "$TestDrive\plain\Bar.Tests.ps1"  -Force | Out-Null
            $Script:Result = @(Get-UnitTestFiles -TestsDir $testsDir.FullName)
        }

        It 'returns all test files' {
            $Script:Result | Should -HaveCount 2
        }
    }

    Context 'files under Integration.DockerHost are excluded' {
        BeforeAll {
            $testsDir  = New-Item -ItemType Directory -Path "$TestDrive\docker-host" -Force
            New-Item -ItemType File -Path "$TestDrive\docker-host\Unit.Tests.ps1" -Force | Out-Null
            $dockerHost = New-Item -ItemType Directory `
                -Path "$TestDrive\docker-host\Integration.DockerHost" -Force
            New-Item -ItemType File -Path "$($dockerHost.FullName)\Excluded.Tests.ps1" -Force | Out-Null
            $Script:Result = @(Get-UnitTestFiles -TestsDir $testsDir.FullName)
        }

        It 'includes the unit test file' {
            $Script:Result.Name | Should -Contain 'Unit.Tests.ps1'
        }

        It 'excludes the file under Integration.DockerHost' {
            $Script:Result.Name | Should -Not -Contain 'Excluded.Tests.ps1'
        }
    }

    Context 'files under Integration.DockerTarget are excluded' {
        BeforeAll {
            $testsDir     = New-Item -ItemType Directory -Path "$TestDrive\docker-target" -Force
            New-Item -ItemType File -Path "$TestDrive\docker-target\Unit.Tests.ps1" -Force | Out-Null
            $dockerTarget = New-Item -ItemType Directory `
                -Path "$TestDrive\docker-target\Integration.DockerTarget" -Force
            New-Item -ItemType File -Path "$($dockerTarget.FullName)\Excluded.Tests.ps1" -Force | Out-Null
            $Script:Result = @(Get-UnitTestFiles -TestsDir $testsDir.FullName)
        }

        It 'includes the unit test file' {
            $Script:Result.Name | Should -Contain 'Unit.Tests.ps1'
        }

        It 'excludes the file under Integration.DockerTarget' {
            $Script:Result.Name | Should -Not -Contain 'Excluded.Tests.ps1'
        }
    }

    Context 'both integration directories are present' {
        BeforeAll {
            $testsDir     = New-Item -ItemType Directory -Path "$TestDrive\both" -Force
            New-Item -ItemType File -Path "$TestDrive\both\Unit.Tests.ps1" -Force | Out-Null
            $dh = New-Item -ItemType Directory -Path "$TestDrive\both\Integration.DockerHost"   -Force
            $dt = New-Item -ItemType Directory -Path "$TestDrive\both\Integration.DockerTarget" -Force
            New-Item -ItemType File -Path "$($dh.FullName)\HostExcluded.Tests.ps1"   -Force | Out-Null
            New-Item -ItemType File -Path "$($dt.FullName)\TargetExcluded.Tests.ps1" -Force | Out-Null
            $Script:Result = @(Get-UnitTestFiles -TestsDir $testsDir.FullName)
        }

        It 'returns only the unit test file' {
            $Script:Result | Should -HaveCount 1
            $Script:Result[0].Name | Should -Be 'Unit.Tests.ps1'
        }
    }

    Context 'files in other subdirectories are included' {
        BeforeAll {
            $testsDir = New-Item -ItemType Directory -Path "$TestDrive\subdir" -Force
            $sub      = New-Item -ItemType Directory -Path "$TestDrive\subdir\Custom" -Force
            New-Item -ItemType File -Path "$($sub.FullName)\Custom.Tests.ps1" -Force | Out-Null
            $Script:Result = @(Get-UnitTestFiles -TestsDir $testsDir.FullName)
        }

        It 'includes the file' {
            $Script:Result | Should -HaveCount 1
            $Script:Result[0].Name | Should -Be 'Custom.Tests.ps1'
        }
    }

    Context 'tests directory is empty' {
        BeforeAll {
            $testsDir     = New-Item -ItemType Directory -Path "$TestDrive\empty" -Force
            $Script:Result = @(Get-UnitTestFiles -TestsDir $testsDir.FullName)
        }

        It 'returns an empty result' {
            $Script:Result | Should -HaveCount 0
        }
    }
}
