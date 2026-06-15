BeforeAll {
    # Dot-source the action script. The InvocationName guard inside
    # skips the side-effecting scan and only loads the helpers.
    $Script:ScriptPath = "$PSScriptRoot\..\.github\actions\lint-powershell-parses\Test-PowerShellParses.ps1"
    . $Script:ScriptPath

    # Per-test fixture builder. Drops a tree under $TestDrive with
    # operator-chosen contents and returns the root path.
    function New-ParseFixture {
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
}

Describe 'Find-ParseErrorHits' {

    Context 'detection' {

        It 'flags a file with an unbalanced brace' {
            $root = New-ParseFixture -Name 'unbalanced' -Files @{
                'src\Bad.ps1' = @"
function Foo {
    'never closed'
"@
            }
            # Assign first, then operate: the helper returns its array via
            # the repo's `,@()` shape-preserving idiom, which stays
            # protected through the pipeline. Inlining `@(Find-...)` would
            # re-nest that protected array; binding to a variable unwraps it.
            $hits = Find-ParseErrorHits -SourceRoot $root
            $hits.Count   | Should -BeGreaterThan 0
            $hits[0].Path | Should -BeLike '*src*Bad.ps1'
        }

        It 'flags a broken here-string' {
            $root = New-ParseFixture -Name 'heredoc' -Files @{
                'X.ps1' = @'
$value = @"
unterminated here-string
'@
            }
            (Find-ParseErrorHits -SourceRoot $root).Count | Should -BeGreaterThan 0
        }

        It 'attributes the error to the offending file when several files exist' {
            $root = New-ParseFixture -Name 'attribution' -Files @{
                'Good.ps1' = "function G { 'ok' }"
                'Bad.ps1'  = 'function B { '
            }
            $hits = Find-ParseErrorHits -SourceRoot $root
            $hits.Count                                          | Should -BeGreaterThan 0
            @($hits | Where-Object Path -Like '*Bad.ps1').Count  | Should -BeGreaterThan 0
            @($hits | Where-Object Path -Like '*Good.ps1').Count | Should -Be 0
        }
    }

    Context 'clean input' {

        It 'returns zero hits when every file parses' {
            $root = New-ParseFixture -Name 'clean' -Files @{
                'A.ps1'  = "function A { return ,@() }"
                'B.psm1' = "function B { 'ok' }`nExport-ModuleMember -Function B"
            }
            (Find-ParseErrorHits -SourceRoot $root).Count | Should -Be 0
        }

        It 'parses a valid .psd1 data file' {
            $root = New-ParseFixture -Name 'manifest' -Files @{
                'Module.psd1' = "@{ ModuleVersion = '1.0.0'; GUID = 'x' }"
            }
            (Find-ParseErrorHits -SourceRoot $root).Count | Should -Be 0
        }
    }

    Context 'extension coverage' {

        It 'flags a parse error in a .psm1 file' {
            $root = New-ParseFixture -Name 'psm1' -Files @{
                'Broken.psm1' = 'function M { '
            }
            (Find-ParseErrorHits -SourceRoot $root).Count | Should -BeGreaterThan 0
        }

        It 'ignores files with non-PowerShell extensions' {
            $root = New-ParseFixture -Name 'otherExt' -Files @{
                'notes.txt'  = 'function B { '
                'data.json'  = '{ "broken": '
            }
            (Find-ParseErrorHits -SourceRoot $root).Count | Should -Be 0
        }
    }

    Context 'exclusions' {

        It 'skips files under .ci-common/' {
            $root = New-ParseFixture -Name 'excCommon' -Files @{
                'src\Good.ps1'             = "function G { 'ok' }"
                '.ci-common\SomeAction\X.ps1' = 'function X { '
            }
            # The broken file lives under the sibling checkout - excluded.
            (Find-ParseErrorHits -SourceRoot $root).Count | Should -Be 0
        }

        It 'still flags broken files outside .ci-common when both exist' {
            $root = New-ParseFixture -Name 'mixed' -Files @{
                'src\Bad.ps1'              = 'function B { '
                '.ci-common\SomeAction\X.ps1' = 'function X { '
            }
            $hits = Find-ParseErrorHits -SourceRoot $root
            $hits.Count                                            | Should -BeGreaterThan 0
            @($hits | Where-Object Path -Like '*src*Bad.ps1').Count | Should -BeGreaterThan 0
            @($hits | Where-Object Path -Like '*ci-common*').Count  | Should -Be 0
        }
    }

    Context 'return-shape contract' {

        It 'returns an array (not $null) when there are zero hits' {
            $root = New-ParseFixture -Name 'empty' -Files @{
                'X.ps1' = "function X { 'noop' }"
            }
            $result = Find-ParseErrorHits -SourceRoot $root
            # Eats its own dogfood: the function must use ,@() so the
            # caller's .Count works on zero matches.
            ($null -eq $result)   | Should -BeFalse
            ($result -is [array]) | Should -BeTrue
            $result.Count         | Should -Be 0
        }
    }
}
