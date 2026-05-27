<#
.SYNOPSIS
    Runs unit tests for the PowerShell.Common module.

.EXAMPLE
    .\Run-Tests.ps1
#>

& ([IO.Path]::Combine($PSScriptRoot, '.github', 'actions', 'run-unit-tests', 'Run-Tests.ps1')) `
    -TestsRoot $PSScriptRoot
