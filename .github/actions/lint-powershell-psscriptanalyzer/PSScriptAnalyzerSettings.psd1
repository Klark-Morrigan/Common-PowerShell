# PSScriptAnalyzer settings - the single source of truth for which rules
# the lint-powershell-psscriptanalyzer gate enforces across the
# Infrastructure-* polyrepo family. Invoke-PsScriptAnalyzer.ps1 passes this
# file to Invoke-ScriptAnalyzer via -Settings, so local runs and CI cannot
# drift on the rule set.
#
# Severity is deliberately the strictest the analyzer offers: Error,
# Warning AND Information all fail the build. The bar starts strict so the
# codebase is held to the full default rule set; relax it here (per rule,
# with a rationale) rather than in the workflow, to keep one place to look.

@{
    # Run the analyzer's built-in rule set. No custom rule modules.
    IncludeDefaultRules = $true

    # Every severity counts as a failure. The script also filters its own
    # results to this set, so a rule emitting a lower severity than listed
    # here would simply not be reported - keep this aligned with the
    # -Severity the script requests.
    Severity = @('Error', 'Warning', 'Information')

    # Rules excluded fleet-wide. Each entry names a default rule whose
    # finding is a deliberate convention or a known false positive in this
    # codebase, with the rationale inline. Everything NOT listed here is
    # still enforced - security rules, null-comparison, global-var, etc.
    # all remain active. A site-specific exception is suppressed inline
    # with [SuppressMessageAttribute] instead of being added here, so the
    # rule keeps protecting the rest of the tree (see the Start-Sleep test
    # doubles for PSAvoidOverwritingBuiltInCmdlets).
    ExcludeRules = @(
        # The scripts in this repo are CLI/CI tooling, not library cmdlets.
        # Write-Host is the intended channel for two things the analyzer
        # cannot tell apart from stray debug output: GitHub Actions
        # ::error:: / ::warning:: annotations (which MUST go to the host
        # stream to be picked up), and the interactive status lines the
        # publish / install / test-runner scripts print. The lint gates
        # themselves depend on it. Write-Information would break both.
        'PSAvoidUsingWriteHost',

        # The rule's data-flow analysis does not follow two patterns that
        # are pervasive here, so every hit is a false positive: parameters
        # captured into a returned script block via .GetNewClosure() (the
        # whole Retry\ backoff/strategy family), and parameters consumed
        # only inside Pester mock/It script blocks in the test suite.
        'PSReviewUnusedParameter',

        # The rule is a verb heuristic: it flags every New-*/Set-* function
        # as if it mutates external state. This repo's flagged functions are
        # pure in-memory factories (New-*BackoffStrategy, New-*RetryStrategy
        # return a hashtable/closure) and test helpers - none touch the
        # system, so ShouldProcess plumbing would be semantically wrong.
        # Genuinely state-changing operations here use Invoke-* verbs, which
        # the rule does not cover anyway.
        'PSUseShouldProcessForStateChangingFunctions',

        # The flagged commands return collections, for which a plural noun
        # is the correct, idiomatic name (Get-UnitTestFiles, the Find-*Hits
        # lint helpers, Assert-RequiredProperties). Renaming to a singular
        # would misdescribe the contract.
        'PSUseSingularNouns',

        # The analyzer cannot infer the output type through this repo's
        # shape-preserving `,@()` return idiom or through hashtable/closure
        # returns, so it reports a mismatch even where the declared
        # [OutputType] is correct (e.g. ConvertTo-Array). All hits are
        # inference gaps, not real contract violations.
        'PSUseOutputTypeCorrectly'
    )
}
