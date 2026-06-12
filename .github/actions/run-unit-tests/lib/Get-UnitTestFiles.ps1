# Returns all *.Tests.ps1 files under TestsDir, excluding the
# Integration.DockerHost and Integration.DockerTarget subdirectories
# (those require Docker and are run by separate workflows).
function Get-UnitTestFiles {
    param([string] $TestsDir)

    $excludedPrefixes = @('Integration.DockerHost', 'Integration.DockerTarget') |
        ForEach-Object {
            $dir = [IO.Path]::Combine($TestsDir, $_)
            if (Test-Path $dir) {
                (Get-Item $dir).FullName.TrimEnd('\') + '\'
            }
        } |
        Where-Object { $_ }

    Get-ChildItem -Path $TestsDir -Filter '*.Tests.ps1' -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $path = $_.FullName
            -not ($excludedPrefixes | Where-Object { $path.StartsWith($_) })
        }
}
