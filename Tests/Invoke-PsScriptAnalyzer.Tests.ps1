BeforeAll {
    # Dot-source the action script. The InvocationName guard inside skips
    # both the module install and the side-effecting scan, loading only the
    # helper functions.
    $Script:ScriptPath = "$PSScriptRoot\..\.github\actions\lint-powershell-psscriptanalyzer\Invoke-PsScriptAnalyzer.ps1"
    . $Script:ScriptPath

    # The pure scan delegates to Invoke-ScriptAnalyzer, so the module must be
    # importable here. The dot-source guard suppressed the script's own
    # on-demand install, so install it explicitly - mirrors how the unit-test
    # action ensures Pester before running.
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
    }
    Import-Module PSScriptAnalyzer

    # These tests exercise the wrapper MECHANICS (does it run the analyzer,
    # map diagnostics, and apply the path exclusion), not the production
    # rule choices. Pointing them at the real settings file would couple
    # each fixture to whichever rules production currently excludes - so a
    # later retune would break tests that have nothing to do with that rule.
    # Instead they run against a dedicated settings file that enables the
    # full default rule set with no exclusions, so the WriteHost fixture
    # below trips a known rule deterministically. The production settings
    # are validated end-to-end by the gate itself running green on the repo.
    $Script:SettingsPath = Join-Path $TestDrive 'TestSettings.psd1'
    Set-Content -Path $Script:SettingsPath -Encoding UTF8 -Value @'
@{
    IncludeDefaultRules = $true
    Severity            = @('Error', 'Warning', 'Information')
    ExcludeRules        = @()
}
'@

    # Per-test fixture builder. Drops a tree under $TestDrive with
    # operator-chosen contents and returns the root path. Mirrors the
    # builder in Test-PowerShellParses.Tests.ps1.
    function New-AnalyzerFixture {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [hashtable] $Files
        )
        $root = Join-Path $TestDrive $Name
        foreach ($rel in $Files.Keys) {
            $full = Join-Path $root $rel
            $dir  = Split-Path $full -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Set-Content -Path $full -Value $Files[$rel] -Encoding UTF8
        }
        return $root
    }

    # Smallest input that deterministically trips exactly one default rule
    # (PSAvoidUsingWriteHost). Get-Thing is the clean counterpart: Get verb,
    # singular noun, no Write-Host, so it trips nothing.
    $Script:WriteHostFn = "function Test-Thing { Write-Host 'hi' }"
    $Script:CleanFn     = "function Get-Thing { 'ok' }"
}

Describe 'Find-ScriptAnalyzerHits' {

    Context 'detection' {

        It 'flags a file that violates a default rule' {
            $root = New-AnalyzerFixture -Name 'writehost' -Files @{
                'src\Has.ps1' = $Script:WriteHostFn
            }
            # Assign first, then operate: the helper returns its array via the
            # repo's `,@()` shape-preserving idiom. Inlining `@(Find-...)`
            # would re-nest it; binding to a variable unwraps it.
            $hits = Find-ScriptAnalyzerHits -SourceRoot $root -SettingsPath $Script:SettingsPath
            $hits.Count                                              | Should -BeGreaterThan 0
            @($hits | Where-Object RuleName -EQ 'PSAvoidUsingWriteHost').Count | Should -BeGreaterThan 0
            $hits[0].Path                                           | Should -BeLike '*src*Has.ps1'
        }

        It 'populates Severity and RuleName on each hit' {
            $root = New-AnalyzerFixture -Name 'fields' -Files @{
                'Has.ps1' = $Script:WriteHostFn
            }
            $hit = (Find-ScriptAnalyzerHits -SourceRoot $root -SettingsPath $Script:SettingsPath)[0]
            $hit.RuleName | Should -Not -BeNullOrEmpty
            $hit.Severity | Should -Not -BeNullOrEmpty
        }

        It 'attributes the diagnostic to the offending file when several exist' {
            $root = New-AnalyzerFixture -Name 'attribution' -Files @{
                'Clean.ps1' = $Script:CleanFn
                'Has.ps1'   = $Script:WriteHostFn
            }
            $hits = Find-ScriptAnalyzerHits -SourceRoot $root -SettingsPath $Script:SettingsPath
            @($hits | Where-Object Path -Like '*Has.ps1').Count   | Should -BeGreaterThan 0
            @($hits | Where-Object Path -Like '*Clean.ps1').Count | Should -Be 0
        }
    }

    Context 'clean input' {

        It 'returns zero hits when no file violates a rule' {
            $root = New-AnalyzerFixture -Name 'clean' -Files @{
                'A.ps1' = $Script:CleanFn
            }
            (Find-ScriptAnalyzerHits -SourceRoot $root -SettingsPath $Script:SettingsPath).Count | Should -Be 0
        }
    }

    Context 'exclusions' {

        It 'skips files under .ci-common/' {
            $root = New-AnalyzerFixture -Name 'excCommon' -Files @{
                'src\Clean.ps1'               = $Script:CleanFn
                '.ci-common\SomeAction\X.ps1' = $Script:WriteHostFn
            }
            # The only violation lives under the sibling checkout - excluded.
            (Find-ScriptAnalyzerHits -SourceRoot $root -SettingsPath $Script:SettingsPath).Count | Should -Be 0
        }

        It 'still flags violations outside .ci-common when both exist' {
            $root = New-AnalyzerFixture -Name 'mixed' -Files @{
                'src\Has.ps1'                 = $Script:WriteHostFn
                '.ci-common\SomeAction\X.ps1' = $Script:WriteHostFn
            }
            $hits = Find-ScriptAnalyzerHits -SourceRoot $root -SettingsPath $Script:SettingsPath
            @($hits | Where-Object Path -Like '*src*Has.ps1').Count | Should -BeGreaterThan 0
            @($hits | Where-Object Path -Like '*ci-common*').Count  | Should -Be 0
        }
    }

    Context 'return-shape contract' {

        It 'returns an array (not $null) when there are zero hits' {
            $root = New-AnalyzerFixture -Name 'empty' -Files @{
                'notes.txt' = 'not a PowerShell file'
            }
            $result = Find-ScriptAnalyzerHits -SourceRoot $root -SettingsPath $Script:SettingsPath
            # Eats its own dogfood: the function must use ,@() so the caller's
            # .Count works on zero matches.
            ($null -eq $result)   | Should -BeFalse
            ($result -is [array]) | Should -BeTrue
            $result.Count         | Should -Be 0
        }
    }
}
