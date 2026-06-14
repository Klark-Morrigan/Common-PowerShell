function Limit-RetainedItem {
<#
.SYNOPSIS
    Prunes filesystem items in a directory by age, count, or both.

.DESCRIPTION
    Out-of-the-box Windows has no logrotate equivalent and PowerShell
    has no built-in rolling-file primitive for retaining recent
    artifacts. This helper is the lightweight at-write-time sweep
    callers use to keep diagnostics / log / cache folders from
    growing without bound.

    Two retention dimensions, applied in order:
      1. -MaxAgeDays  - drop anything older than the cutoff. 0 disables.
      2. -MaxItems    - keep at most N most-recent items after the
                        age pass. 0 disables.

    Items are picked by LastWriteTime (not by name) so timestamped
    filenames are not load-bearing. Works on files and directories;
    -FileOnly lets callers scope to one or the other (useful for
    sweeping timestamped per-run diag folders).

    Safe to call against a missing directory (returns silently);
    safe to call against an empty directory (no-op). Glob filter
    applied via Get-ChildItem -Filter so only items matching the
    pattern get evaluated - never accidentally prunes neighbour
    artifacts.

.PARAMETER Directory
    Directory to sweep. Missing directories are tolerated as a
    no-op so callers do not need a Test-Path guard.

.PARAMETER Filter
    Wildcard filter applied to item names. Default '*' = every
    entry in the directory.

.PARAMETER MaxItems
    Keep at most this many most-recent items. 0 disables the
    count-based pass.

.PARAMETER MaxAgeDays
    Drop items older than N days. 0 disables the age-based pass.

.PARAMETER FileOnly
    When set, only files are considered. When clear, files and
    directories are both eligible (useful for sweeping timestamped
    per-run diag folders).

.EXAMPLE
    Limit-RetainedItem -Directory C:\logs -Filter '*.log' `
                       -MaxItems 20 -MaxAgeDays 30 -FileOnly

    Keep the 20 most-recent *.log files, drop anything older than
    30 days first.

.EXAMPLE
    Limit-RetainedItem -Directory C:\diag\<vm> `
                       -Filter '????-??-??_*' -MaxItems 30

    Sweep per-run timestamped subfolders (files AND directories),
    keep the 30 most recent.
#>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Directory,

        [string] $Filter = '*',

        [int] $MaxItems = 0,

        [int] $MaxAgeDays = 0,

        [switch] $FileOnly
    )

    if (-not (Test-Path -LiteralPath $Directory)) { return }

    $gciParams = @{
        Path        = $Directory
        Filter      = $Filter
        ErrorAction = 'SilentlyContinue'
    }
    if ($FileOnly) { $gciParams['File'] = $true }

    # Age-based pass: drop anything older than the cutoff.
    if ($MaxAgeDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
        Get-ChildItem @gciParams |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, "Remove (older than $MaxAgeDays days)")) {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force `
                                -ErrorAction SilentlyContinue
                }
            }
    }

    # Count-based pass: keep the N most recent, drop the rest.
    if ($MaxItems -gt 0) {
        Get-ChildItem @gciParams |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $MaxItems |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, "Remove (over -MaxItems=$MaxItems)")) {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force `
                                -ErrorAction SilentlyContinue
                }
            }
    }
}
