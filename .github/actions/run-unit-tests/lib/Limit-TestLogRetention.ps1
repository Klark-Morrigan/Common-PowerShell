# Prunes old log files in the -LogPath directory using the shared logrotate
# helper from Common.PowerShell (Limit-RetainedItem).
#
#   RetainedItemHelperPath is injected by the caller rather than derived here:
#   this file lives under lib\, so its own $PSScriptRoot would point at the
#   wrong directory. The helper is dot-sourced lazily and Test-Path-guarded so a
#   missing module copy can never break the common (no -LogPath) CI path, which
#   never calls this function.
function Limit-TestLogRetention {
    param(
        [string] $LogDirectory,
        [string] $Filter,
        [int]    $MaxItems,
        [string] $RetainedItemHelperPath
    )

    if ($MaxItems -le 0 -or [string]::IsNullOrWhiteSpace($LogDirectory)) { return }

    if (-not (Test-Path -LiteralPath $RetainedItemHelperPath)) {
        Write-Warning "Log retention skipped - helper not found at $RetainedItemHelperPath."
        return
    }

    . $RetainedItemHelperPath
    Limit-RetainedItem -Directory $LogDirectory -Filter $Filter `
                       -MaxItems $MaxItems -FileOnly
}
