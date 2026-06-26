function Test-ManifestVersionIsNew {
    # Determines whether the module version in the given .psd1 manifest still
    # needs to be released, and writes version_is_new to GITHUB_OUTPUT so the
    # calling workflow can gate the release job on it.
    #
    # "New" means "not yet published to PSGallery". PSGallery is the source of
    # truth for publication state, NOT the git tag. Keying off the gallery makes
    # the release pipeline self-healing: if a prior run pushed the tag but failed
    # to publish, the version is still absent from the gallery, so this reports
    # it as new and the retry re-enters publish. Keying off `git tag -l` instead
    # latched the pipeline shut, because the tag is pushed before publish and the
    # two are not atomic - a failed publish left a tag that made every retry
    # report the version as already released.
    #
    # The module name queried on the gallery is the manifest's base file name
    # (e.g. Common.PowerShell.psd1 -> Common.PowerShell), which is the published
    # module name by convention.
    param(
        [Parameter(Mandatory)]
        [string] $Psd1
    )

    $version = (Import-PowerShellDataFile $Psd1).ModuleVersion
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Psd1)

    # Find-Module errors when the exact version (or the module) is absent;
    # SilentlyContinue lets us treat "not found" as "new" without a try/catch.
    # Any returned object means the version is already on the gallery.
    $published = Find-Module -Name $name -RequiredVersion $version `
        -Repository PSGallery -ErrorAction SilentlyContinue
    $isNew = -not $published

    # Guard the redirect so unit tests can call the function without a
    # GITHUB_OUTPUT file present; in CI the runner always sets it.
    if ($env:GITHUB_OUTPUT) {
        "version_is_new=$($isNew.ToString().ToLower())" >> $env:GITHUB_OUTPUT
    }

    Write-Host $(if ($isNew) {
        "Version $version of $name is not on PSGallery - proceeding."
    } else {
        "Version $version of $name already published - skipping."
    })

    return $isNew
}
