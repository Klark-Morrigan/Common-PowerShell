# Prints a lint's verdict and returns the exit code its script ends with: 0
# when there are no hits, 1 otherwise.
#   Each hit becomes a GitHub Actions error annotation on its file and line, so
#   it shows in the pull request's diff view; a local run prints the same lines
#   plain. Every hit carries Path and LineNumber; DescribeHit turns one hit
#   into the annotation's message.
function Write-LintReport {

    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Hits,

        [Parameter(Mandatory)]
        [string] $PassMessage,

        [Parameter(Mandatory)]
        [scriptblock] $DescribeHit,

        [Parameter(Mandatory)]
        [string] $FindingLabel
    )

    if ($Hits.Count -eq 0) {

        Write-Host "Lint OK: $PassMessage"
        return 0
    }

    foreach ($hit in $Hits) {

        Write-Host "::error file=$($hit.Path),line=$($hit.LineNumber)::$(& $DescribeHit $hit)"
    }

    Write-Host "Lint FAILED: $($Hits.Count) $FindingLabel found."
    return 1
}
