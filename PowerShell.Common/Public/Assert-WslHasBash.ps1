function Assert-WslHasBash {
    <#
    .SYNOPSIS
        Ensures the targeted WSL distro has bash installed and on PATH.

    .DESCRIPTION
        Assert-Wsl2Ready proves WSL2 itself is available and at least
        one distro is registered, but does not look inside the distro.
        Some distros - notably the `docker-desktop` distro that Docker
        Desktop installs and silently sets as the WSL default - ship a
        busybox/dash userland with no `bash` at all. Any caller that
        execs a `#!/usr/bin/env bash` script against such a distro fails
        mid-run with `env: can't execute 'bash': No such file or
        directory` or `/bin/sh: bash: not found`, leaving the operator
        to reverse-engineer that a Docker install moved the default.

        Assert-WslHasBash closes that gap. It runs a one-line probe
        inside the targeted distro and throws a `WslMissingBash:`-
        prefixed error when bash is absent, mirroring the
        `Wsl2NotReady:` contract from Assert-Wsl2Ready so callers can
        catch one prefix and surface a clear remediation hint.

    .PARAMETER DistroName
        Name of the WSL distro to probe (`wsl --list --quiet` lists the
        available names). When omitted, the system default distro is
        used - same target a bare `wsl --` invocation would hit. Pass
        the name explicitly when the caller will go on to use
        `wsl -d <DistroName> --` and wants the same verification scope.

    .EXAMPLE
        try {
            Assert-Wsl2Ready
            Assert-WslHasBash
            # ... wsl --  bash-using work ...
        }
        catch {
            if ($_.Exception.Message -match '^WslMissingBash: ') {
                Write-Host (
                    $_.Exception.Message -replace '^WslMissingBash: ',''
                ) -ForegroundColor Yellow
                exit 1
            }
            throw
        }
    #>
    [CmdletBinding()]
    param(
        [string] $DistroName
    )

    # Probe shape: `command -v bash` is a POSIX-portable PATH lookup
    # that works in busybox sh as well as bash. It prints the resolved
    # path (which we discard) and exits 0 on hit, non-zero on miss.
    # `/bin/sh -c` is reached via wsl's exec - even docker-desktop has
    # /bin/sh - so the probe itself does not depend on bash.
    $wslArgs = @()
    if ($DistroName) {
        $wslArgs += @('-d', $DistroName)
    }
    $wslArgs += @('--', '/bin/sh', '-c', 'command -v bash')

    # Stderr folded into stdout via 2>&1 so a transient wsl error (e.g.
    # distro stopped, not registered) surfaces in the thrown message
    # rather than the operator's console only. Native invocation;
    # $LASTEXITCODE is the source of truth - $? alone misreports on
    # native commands.
    $probeOutput = & wsl @wslArgs 2>&1
    $probeExit   = $LASTEXITCODE

    if ($probeExit -eq 0) { return }

    $targetLabel = if ($DistroName) { "distro '$DistroName'" } else { 'the default WSL distro' }
    # Detection hint: docker-desktop's name is well-known and the
    # docker-install root cause is so common that calling it out
    # up-front saves the operator a diagnostic round trip.
    $hint = if (-not $DistroName -or $DistroName -eq 'docker-desktop') {
        " If 'wsl --list --verbose' shows 'docker-desktop' as the default, " +
        "install a real Linux distro (e.g. 'wsl --install -d Ubuntu-24.04') and " +
        "set it as default via 'wsl --set-default Ubuntu-24.04'."
    } else {
        " Install bash inside '$DistroName' (e.g. 'wsl -d $DistroName -- apt-get install -y bash' " +
        "for Debian/Ubuntu) or point downstream callers at a different distro."
    }

    throw (
        "WslMissingBash: bash was not found on PATH inside $targetLabel " +
        "(exit ${probeExit}: $($probeOutput -join ' ')).${hint}"
    )
}
