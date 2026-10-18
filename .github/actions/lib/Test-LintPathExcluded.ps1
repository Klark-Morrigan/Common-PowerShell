# Returns whether a file sits under one of the exclude patterns, judged by its
# path relative to the source root.
#   Depends on Get-LintExcludePatterns being dot-sourced into the same scope.
function Test-LintPathExcluded {

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $RootPath,

        [Parameter(Mandatory)]
        [string] $FilePath,

        [string[]] $ExcludePatterns = (Get-LintExcludePatterns)
    )

    $relativePath = $FilePath.Substring($RootPath.Length).TrimStart('\', '/')

    foreach ($pattern in $ExcludePatterns) {

        if ($relativePath -match $pattern) {
            return $true
        }
    }

    return $false
}
