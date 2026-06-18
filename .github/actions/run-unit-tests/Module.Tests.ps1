# Shared module registration test, injected by Run-Tests.ps1 for every repo
# in the Infrastructure-* family. The module root is passed via the
# MODULE_TESTS_ROOT environment variable set by Run-Tests.ps1 before Pester
# is invoked.
BeforeAll {
    $root = $env:MODULE_TESTS_ROOT
    if (-not $root) {
        throw 'MODULE_TESTS_ROOT env var is not set. This file must be run via Run-Tests.ps1.'
    }

    $script:manifest    = Import-PowerShellDataFile (
        Get-ChildItem -Path $root -Filter '*.psd1' | Select-Object -First 1 -ExpandProperty FullName)
    $script:psm1Content = Get-Content (
        Get-ChildItem -Path $root -Filter '*.psm1' | Select-Object -First 1 -ExpandProperty FullName) -Raw

    # Convention: filename == function name (e.g. ConvertTo-Array.ps1).
    # Recursive so repos can group related functions into subfolders
    # (e.g. Public\Retry\) without breaking the registration check.
    # Flat Public\ layouts still match - recursion is a superset.
    $script:publicFns = Get-ChildItem `
        -Path    ([IO.Path]::Combine($root, 'Public')) `
        -Filter  '*.ps1' `
        -Recurse |
        Select-Object -ExpandProperty BaseName

    # Extract the ACTUAL names passed to Export-ModuleMember -Function via
    # the AST. A substring match against the whole psm1 (the previous
    # approach) is satisfied by the dot-source line `. ...\<Fn>.ps1`, so it
    # silently passes when a name is dropped from Export-ModuleMember. That
    # matters because the effective export surface is the INTERSECTION of
    # psm1 Export-ModuleMember and psd1 FunctionsToExport: a name missing
    # from Export-ModuleMember is not callable after Import-Module even
    # though it is still in FunctionsToExport. Parsing the argument list is
    # what actually reflects what gets exported.
    $psm1Ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $script:psm1Content, [ref]$null, [ref]$null)
    $exportCalls = $psm1Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Export-ModuleMember'
    }, $true)
    $script:exportedNames = foreach ($call in $exportCalls) {
        $elements = $call.CommandElements
        for ($i = 0; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]
            $isFunctionParam =
                $el -is [System.Management.Automation.Language.CommandParameterAst] -and
                $el.ParameterName -eq 'Function'
            if (-not $isFunctionParam) { continue }

            # `-Function:value` carries its value on .Argument; the more
            # common `-Function @(...)` / `-Function 'a','b'` puts it in the
            # next element. Either way, harvest every string literal beneath.
            $arg = if ($null -ne $el.Argument) { $el.Argument } else { $elements[$i + 1] }
            if ($arg) {
                $arg.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.StringConstantExpressionAst]
                }, $true) | ForEach-Object { $_.Value }
            }
        }
    }
    # No Export-ModuleMember call at all means PowerShell auto-exports every
    # function, so nothing can be "missing". Represent that as match-all.
    if (-not $exportCalls) { $script:exportedNames = @('*') }
}

Describe 'Module registration' {

    It 'all Public functions are listed in FunctionsToExport' {
        $missing = $script:publicFns |
            Where-Object { $_ -notin $script:manifest.FunctionsToExport }
        $missing | Should -BeNullOrEmpty
    }

    It 'all Public functions are dot-sourced in the psm1' {
        $missing = $script:publicFns |
            Where-Object { $script:psm1Content -notmatch [regex]::Escape("$_.ps1") }
        $missing | Should -BeNullOrEmpty
    }

    It 'all Public functions are in Export-ModuleMember' {
        # -like so a wildcard export (`Export-ModuleMember -Function *`)
        # counts as exporting everything, while explicit names match
        # exactly. Compares against the parsed argument list, not the raw
        # file text, so a dropped entry is caught here on push rather than
        # only at release by the real-import integration test.
        $missing = $script:publicFns | Where-Object {
            $fn = $_
            -not ($script:exportedNames | Where-Object { $fn -like $_ })
        }
        $missing | Should -BeNullOrEmpty
    }
}
