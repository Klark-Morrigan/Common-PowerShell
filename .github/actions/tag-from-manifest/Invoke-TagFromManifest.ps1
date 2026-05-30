function Invoke-TagFromManifest {
    # Reads the ModuleVersion from the given .psd1 manifest and, when that
    # version is new, creates three tags on the current HEAD and pushes
    # them:
    #   - X.Y.Z       the immutable module tag (gates PSGallery publish)
    #   - vX.Y.Z      the immutable GitHub Actions consumer tag
    #   - vX          the floating major tag that action consumers pin via @vX
    #
    # The module and action tags advance together on PRs that bump the
    # manifest, so a mixed PR (PS + workflow edits) ships both at the same
    # commit SHA without operator action. Workflow-only PRs (manifest
    # unchanged) hit the skip-if-exists path below and rely on a manual run
    # of Publish-VersionTags.ps1 to advance the action tags instead - that
    # keeps PSGallery free of releases that contain no PS code change.
    #
    # The caller must check out with fetch-depth: 0 so existing tags are
    # visible to the clobber checks.
    param(
        [Parameter(Mandatory)]
        [string] $Psd1
    )

    $version = (Import-PowerShellDataFile $Psd1).ModuleVersion

    # git tag -l returns the tag name if it exists, empty string otherwise.
    if (git tag -l $version) {
        Write-Host "Module tag '$version' already exists - nothing to do."
        # Signal to the calling workflow that no new tag was created so the
        # publish job can be skipped. Without this, publish runs on every psd1
        # touch (e.g. comment edits) and fails trying to re-publish an existing
        # version to PSGallery.
        "tag_created=false" >> $env:GITHUB_OUTPUT
        return
    }

    # GitHub Actions convention tags, derived from the same manifest version.
    $actionImmutable = "v$version"
    $actionMajor     = "v$($version.Split('.')[0])"

    # Refuse if the immutable action tag already exists. This happens only
    # if a prior manual Publish-VersionTags.ps1 run picked the same number
    # the manifest is now being bumped to; re-pointing it would silently
    # change what @vX.Y.Z consumers see. Operator must bump to a higher
    # version not already used by a manual action release.
    if (git tag -l $actionImmutable) {
        throw "Action tag '$actionImmutable' already exists at a different commit. " +
              "Bump the manifest to a version not already used by a manual action release."
    }

    # Resolve HEAD to an explicit SHA so all three tags pin the same commit
    # even if the workspace somehow advances between calls.
    $sha = (git rev-parse HEAD).Trim()

    git tag $version $sha
    git tag $actionImmutable $sha
    # -f only on the floating major: it is the one tag this convention
    # intentionally re-points on every release.
    git tag -f $actionMajor $sha

    git push origin $version
    git push origin $actionImmutable
    git push origin $actionMajor --force

    Write-Host (
        "Pushed module tag '$version' and action tags " +
        "'$actionImmutable' + '$actionMajor' at $sha."
    )
    "tag_created=true" >> $env:GITHUB_OUTPUT
}
