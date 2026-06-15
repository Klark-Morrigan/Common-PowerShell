function Assert-ChangelogVersion {
    # Asserts the .psd1 ModuleVersion equals the latest version section in
    # CHANGELOG.md (the topmost '## [X.Y.Z]' heading, skipping '[Unreleased]').
    # Throws on divergence so a release cannot ship with a manifest and
    # changelog that disagree - and so the same check can gate PRs, keeping
    # the package's authoritative version pinned to its release notes.
    #
    # Stays PowerShell because reading the manifest version is inherently
    # PowerShell/PSGallery-specific; the changelog parsing that the generic
    # create-github-release action does is deliberately not duplicated here.
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Psd1,

        [string] $Changelog = 'CHANGELOG.md'
    )

    # Import-PowerShellDataFile returns a Hashtable; guard the key with
    # ContainsKey so a manifest lacking ModuleVersion yields the friendly
    # error below rather than a StrictMode 'property cannot be found' throw.
    $manifest = Import-PowerShellDataFile $Psd1
    if (-not $manifest.ContainsKey('ModuleVersion') -or -not $manifest.ModuleVersion) {
        throw "Assert-ChangelogVersion: no ModuleVersion found in manifest '$Psd1'."
    }
    $manifestVersion = $manifest.ModuleVersion

    # First heading of the shape '## [X.Y.Z...]'. The digit anchor skips
    # '## [Unreleased]'; the first match is the most recent release.
    $changelogVersion = $null
    foreach ($line in Get-Content -LiteralPath $Changelog) {
        if ($line -match '^##\s+\[(\d+\.\d+\.\d+[^\]]*)\]') {
            $changelogVersion = $Matches[1]
            break
        }
    }

    if (-not $changelogVersion) {
        throw "Assert-ChangelogVersion: no '## [X.Y.Z]' version section found in '$Changelog'."
    }

    if ("$manifestVersion" -ne $changelogVersion) {
        throw (
            "Assert-ChangelogVersion: manifest ModuleVersion '$manifestVersion' does not " +
            "match the latest changelog version '$changelogVersion' in '$Changelog'. " +
            "Promote the [Unreleased] section to '$manifestVersion' (or align the manifest) " +
            "before releasing.")
    }

    Write-Host "Manifest and changelog agree on version $manifestVersion."
}
