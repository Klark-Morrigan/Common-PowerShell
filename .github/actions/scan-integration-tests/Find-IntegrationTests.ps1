<#
.SYNOPSIS
    Discovers integration test files and optionally the module directory.

.DESCRIPTION
    Called by the scan-integration-tests composite action in CI. When
    GITHUB_OUTPUT is set (i.e. running inside GitHub Actions) the results are
    also written as step outputs so subsequent steps can gate on has-tests and
    avoid re-scanning the filesystem.

    Returns a PSCustomObject so the script can be invoked and asserted against
    in unit tests without needing a live GitHub Actions environment.

.PARAMETER TestDir
    Path to the directory to scan for *.Tests.ps1 files.

.PARAMETER CheckModuleDir
    When specified, also detects a module directory: a direct subdirectory of
    the current location whose name matches its .psd1 file. Needed for
    Docker-host runs that inject the shared Module.Tests.ps1.

.OUTPUTS
    PSCustomObject with:
      HasTests      [bool]     - true if any tests or module dir were found.
      TestFilePaths [string[]] - absolute paths of discovered *.Tests.ps1 files.
      ModuleDir     [string]   - name of the detected module directory, or ''.

.EXAMPLE
    .\Find-IntegrationTests.ps1 -TestDir 'Tests/Integration.DockerHost' -CheckModuleDir
#>

param(
    [Parameter(Mandatory)]
    [string] $TestDir,

    [switch] $CheckModuleDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem $TestDir -Filter '*.Tests.ps1' `
               -Recurse -ErrorAction SilentlyContinue)

$moduleDir = $null
if ($CheckModuleDir) {
    $moduleDir = Get-ChildItem -Path . -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "$($_.Name).psd1") } |
        Select-Object -First 1
}

$hasTests      = $files.Count -gt 0 -or $null -ne $moduleDir
$filePaths     = @($files | ForEach-Object { $_.FullName })
$moduleDirName = if ($moduleDir) { $moduleDir.Name } else { '' }

# Write step outputs when running inside GitHub Actions.
if ($env:GITHUB_OUTPUT) {
    "has-tests=$($hasTests.ToString().ToLower())"  >> $env:GITHUB_OUTPUT
    "test-file-paths=$($filePaths -join ',')"      >> $env:GITHUB_OUTPUT
    "module-dir=$moduleDirName"                    >> $env:GITHUB_OUTPUT
}

[PSCustomObject]@{
    HasTests      = $hasTests
    TestFilePaths = $filePaths
    ModuleDir     = $moduleDirName
}
