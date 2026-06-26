function Invoke-Publish {
    # Installs RequiredModules declared in the manifest, then publishes the
    # module to PSGallery. The API key is read from $env:API_KEY rather than
    # accepted as a parameter to keep it out of process listings.
    #
    # Test-ModuleManifest (called internally by Publish-Module) validates
    # RequiredModules against locally installed modules - it does not query
    # PSGallery. Installing them first ensures validation passes in clean
    # environments such as CI runners.
    param(
        # Root to search for the module manifest. Defaults to the current
        # directory so callers that follow the one-module-per-repo convention
        # do not need to specify a path.
        [string] $SearchRoot = '.'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $psd1 = Get-ChildItem $SearchRoot -Filter '*.psd1' -Recurse | Select-Object -First 1
    if (-not $psd1) {
        throw "No .psd1 manifest found under '$SearchRoot'."
    }

    $modulePath = $psd1.DirectoryName
    $manifest = Import-PowerShellDataFile $psd1.FullName

    # PSGallery is the source of truth for publication state. If this exact
    # version is already on the gallery (a prior run published but a later step
    # failed, or this step is being retried), republishing would fail with a
    # duplicate-version error. Skipping instead makes publish idempotent so the
    # whole release pipeline can be safely re-run. Find-Module errors when the
    # version is absent; SilentlyContinue turns that into "not published".
    $alreadyPublished = Find-Module -Name $psd1.BaseName `
        -RequiredVersion $manifest.ModuleVersion `
        -Repository PSGallery -ErrorAction SilentlyContinue
    if ($alreadyPublished) {
        Write-Host "$($psd1.BaseName) $($manifest.ModuleVersion) is already on PSGallery - skipping publish."
        return
    }

    if ($manifest.ContainsKey('RequiredModules')) {
        foreach ($req in $manifest.RequiredModules) {
            $name = if ($req -is [hashtable]) { $req.ModuleName } else { $req }
            Write-Host "Installing dependency: $name ..."
            Install-Module $name -Repository PSGallery -Force -Scope CurrentUser -AllowClobber
        }
    }

    Publish-Module -Path $modulePath -NuGetApiKey $env:API_KEY -Repository PSGallery
}
