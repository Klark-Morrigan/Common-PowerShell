# Returns the path patterns no lint scans, matched against each path relative
# to the source root.
#   ci-powershell.yml stages Common-PowerShell's own actions in
#   .powershell-common/ inside a consumer's checkout. Linting them there would
#   blame an upstream finding on the consumer's pull request.
function Get-LintExcludePatterns {

    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return ,@(
        '^\.powershell-common([\\/]|$)'
    )
}
