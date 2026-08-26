@{
    # PSScriptAnalyzer configuration for windows-settings
    Severity = @('Error', 'Warning')

    # Excluded rules for interactive CLI scripts and shell profile dotfiles
    ExcludeRules = @(
        # Setup and test scripts intentionally use colored terminal output with Write-Host
        'PSAvoidUsingWriteHost',

        # Oh My Posh and CLI completions (gh, kubectl, helm) natively require Invoke-Expression for init
        'PSAvoidUsingInvokeExpression',

        # Dotfile aliases and shortcuts (e.g. fix-abcxyz-branch-name) follow home-settings naming conventions
        'PSUseApprovedVerbs'
    )
}
