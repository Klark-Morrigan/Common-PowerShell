# Returns every file under SourceRoot with one of Extensions that no exclude
# pattern covers.
#   Always an array, through the comma-operator wrap: a repo with exactly one
#   file would otherwise hand back a lone FileInfo, which has no .Count under
#   strict mode.
#   Depends on Get-LintExcludePatterns and Test-LintPathExcluded being
#   dot-sourced into the same scope.
function Get-LintFiles {

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $SourceRoot,

        [Parameter(Mandatory)]
        [string[]] $Extensions,

        [string[]] $ExcludePatterns = (Get-LintExcludePatterns)
    )

    $root = (Resolve-Path -LiteralPath $SourceRoot).Path

    $files = Get-ChildItem -Path $root -Recurse -File |
        Where-Object { $Extensions -contains $_.Extension } |
        Where-Object {
            -not (Test-LintPathExcluded -RootPath $root -FilePath $_.FullName -ExcludePatterns $ExcludePatterns)
        }

    return ,@($files)
}
