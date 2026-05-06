# Shared helpers dot-sourced by action scripts. Not a module - loaded with
# . (dot-source) so functions land in the caller's scope.

# Returns the first direct subdirectory of RootPath that contains a .psd1
# whose base name matches the directory name (i.e. a PowerShell module root).
function Find-ModuleDirectory {
    param([string] $RootPath)
    Get-ChildItem -Path $RootPath -Directory |
        Where-Object { Test-Path ([IO.Path]::Combine($_.FullName, "$($_.Name).psd1")) } |
        Select-Object -First 1
}
