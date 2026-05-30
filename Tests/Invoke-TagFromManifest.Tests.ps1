BeforeAll {
    . "$PSScriptRoot\..\.github\actions\tag-from-manifest\Invoke-TagFromManifest.ps1"

    # Stub for git - uses $args (not ValueFromRemainingArguments) to avoid
    # PowerShell binding common parameters like -ErrorAction to positional
    # arguments, which would make flags like 'tag' and '-l' ambiguous.
    function git { }
}

Describe 'Invoke-TagFromManifest' {

    BeforeEach {
        Mock Import-PowerShellDataFile {
            [PSCustomObject]@{ ModuleVersion = '1.0.2' }
        }
        # Catch-all mock so EVERY git invocation is counted by
        # Should -Invoke. Without this, calls not matching any of the
        # parameter-filtered mocks below would fall through to the real
        # 'function git {}' stub from BeforeAll - which is not a mock, so
        # those calls would be invisible to assertions.
        Mock git { }
        # rev-parse always resolves to a fixed fake SHA so the three-tag
        # assertions below can pin to one value.
        Mock git -ParameterFilter { $args[0] -eq 'rev-parse' } { 'abc123' }
    }

    Context 'when the module tag already exists' {

        BeforeEach {
            # git tag -l 1.0.2 returns the tag name when it exists.
            Mock git -ParameterFilter {
                $args[0] -eq 'tag' -and $args[1] -eq '-l' -and $args[2] -eq '1.0.2'
            } { '1.0.2' }
        }

        It 'does not create any tags' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            # Any 'git tag ...' call other than the -l existence check would
            # be tag creation; assert none happened.
            Should -Invoke git -Times 0 -ParameterFilter {
                $args[0] -eq 'tag' -and $args[1] -ne '-l'
            }
        }

        It 'does not push anything' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq 'push' }
        }
    }

    Context 'when neither the module tag nor the action tag exist' {

        BeforeEach {
            # Catch-all for both 'tag -l 1.0.2' and 'tag -l v1.0.2' - empty
            # string means the tag is absent. More specific mocks in other
            # contexts override this.
            Mock git -ParameterFilter {
                $args[0] -eq 'tag' -and $args[1] -eq '-l'
            } { }
        }

        It 'creates the immutable module tag at HEAD' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'tag' -and
                $args[1] -eq '1.0.2' -and
                $args[2] -eq 'abc123'
            }
        }

        It 'creates the immutable action tag at HEAD' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'tag' -and
                $args[1] -eq 'v1.0.2' -and
                $args[2] -eq 'abc123'
            }
        }

        It 'force-moves the major action tag to HEAD' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'tag' -and
                $args[1] -eq '-f' -and
                $args[2] -eq 'v1' -and
                $args[3] -eq 'abc123'
            }
        }

        It 'pushes the immutable module tag' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'push' -and
                $args[1] -eq 'origin' -and
                $args[2] -eq '1.0.2' -and
                $args.Count -eq 3
            }
        }

        It 'pushes the immutable action tag' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'push' -and
                $args[1] -eq 'origin' -and
                $args[2] -eq 'v1.0.2' -and
                $args.Count -eq 3
            }
        }

        It 'force-pushes the major action tag' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 1 -Exactly -ParameterFilter {
                $args[0] -eq 'push' -and
                $args[1] -eq 'origin' -and
                $args[2] -eq 'v1' -and
                $args[3] -eq '--force'
            }
        }

        It 'reads the version from the provided psd1 path' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke Import-PowerShellDataFile -Times 1 `
                -ParameterFilter { $Path -eq 'Module\Module.psd1' }
        }
    }

    Context 'when the module tag is new but the action tag already exists' {

        BeforeEach {
            Mock git -ParameterFilter {
                $args[0] -eq 'tag' -and $args[1] -eq '-l' -and $args[2] -eq '1.0.2'
            } { }
            # Prior manual Publish-VersionTags.ps1 run claimed this number.
            Mock git -ParameterFilter {
                $args[0] -eq 'tag' -and $args[1] -eq '-l' -and $args[2] -eq 'v1.0.2'
            } { 'v1.0.2' }
        }

        It 'throws a collision error naming the conflicting tag' {
            { Invoke-TagFromManifest -Psd1 'Module\Module.psd1' } |
                Should -Throw "*v1.0.2*already exists*"
        }

        It 'does not push anything' {
            { Invoke-TagFromManifest -Psd1 'Module\Module.psd1' } |
                Should -Throw
            Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq 'push' }
        }
    }
}
