# Runs the discovered unit tests for one repo.
#   Records the Pester failed count in $script:UnitTestFailedCount rather than
#   returning it: in log mode the caller redirects every output stream of this
#   function (*>) into a file, which would otherwise swallow a return value.
#
#   SharedModuleTestPath (the shared Module.Tests.ps1) is injected by the caller
#   rather than derived here: this file lives under lib\, so its own
#   $PSScriptRoot would point at the wrong directory. Depends on Get-UnitTestFiles
#   and Find-ModuleDirectory being dot-sourced into the same scope.
function Invoke-UnitTestRun {
    param(
        [string] $TestsRoot,
        [string] $SharedModuleTestPath
    )

    # Ensure Pester 5 is available. Pester 3 ships with Windows PowerShell 5.1
    # and is incompatible with our tests (different API); require >= 5.0.
    $pester = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version.Major -ge 5 } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $pester) {
        Write-Host 'Pester 5 not found - installing ...' -ForegroundColor Cyan
        Install-Module -Name Pester -MinimumVersion 5.0 `
            -Scope CurrentUser -Force -SkipPublisherCheck
    }

    Import-Module Pester -MinimumVersion 5.0

    # Discover test files - exclude Integration.DockerHost\ and
    # Integration.DockerTarget\ (both require Docker).
    $testsDir  = [IO.Path]::Combine($TestsRoot, 'Tests')
    $testFiles = Get-UnitTestFiles -TestsDir $testsDir

    # Inject the shared module registration test. Detects the module directory
    # by convention: a direct subdirectory of TestsRoot whose name matches a
    # .psd1 inside it (e.g. Common.PowerShell\Common.PowerShell.psd1). Sets
    # MODULE_TESTS_ROOT so the shared test can locate the module without
    # knowing the repo name.
    $moduleDir = Find-ModuleDirectory -RootPath $TestsRoot

    if ($moduleDir -and (Test-Path $SharedModuleTestPath)) {
        $env:MODULE_TESTS_ROOT = $moduleDir.FullName
        $testFiles = @($testFiles) + (Get-Item $SharedModuleTestPath)
    }

    # Guard against running with no test files - Pester throws rather than
    # returning a result object, which breaks the FailedCount check below.
    if (-not $testFiles) {
        Write-Host 'No unit test files found - nothing to run.' -ForegroundColor Yellow
        return
    }

    $config = New-PesterConfiguration
    # Pass individual file paths so Pester does not re-discover the Tests\ folder
    # (which would include Integration.DockerHost\ and Integration.DockerTarget\
    # even though they were filtered above).
    $config.Run.Path              = @($testFiles.FullName)
    $config.Output.Verbosity      = 'Detailed'
    $config.TestResult.Enabled    = $true
    $config.TestResult.OutputPath = [IO.Path]::Combine($TestsRoot, 'TestResults.xml')
    # PassThru is required for Invoke-Pester to return a result object;
    # without it the return value is $null and FailedCount cannot be read.
    $config.Run.PassThru          = $true

    $result = Invoke-Pester -Configuration $config

    $script:UnitTestFailedCount = $result.FailedCount
    if ($result.FailedCount -gt 0) {
        Write-Host "$($result.FailedCount) test(s) failed." -ForegroundColor Red
    }
}
