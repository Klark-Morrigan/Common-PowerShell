# Changelog

All notable changes to `Common.PowerShell` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org).

Add entries under `[Unreleased]` as changes merge; at release the
`[Unreleased]` heading is promoted to the new version + date and a fresh
`[Unreleased]` is opened above it. Changes prior to 8.1.0 live in the git
history and the tag list.

## [Unreleased]

## [9.0.0] - 2026-06-17

### Changed
- Major version bump; no functional changes (version realignment).

## [8.1.0] - 2026-06-14

### Added
- `Invoke-WithExitCodeRetry` - exit-code counterpart to `Invoke-WithRetry`
  for native commands (`netsh`, `git`, `docker`, `wsl`, ...) that signal
  failure through `$LASTEXITCODE` instead of a thrown exception. Reuses the
  existing backoff strategies; scope retries with an optional
  `-RetryableExitCode` set, or throw and use `Invoke-WithRetry` for
  predicate-based classification.

[Unreleased]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/9.0.0...HEAD
[9.0.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/8.1.0...9.0.0
[8.1.0]: https://github.com/Klark-Morrigan/Common-PowerShell/compare/8.0.0...8.1.0
