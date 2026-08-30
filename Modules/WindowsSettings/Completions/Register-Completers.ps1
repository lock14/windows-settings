# =============================================================
# CLI Tab Completions & Dynamic Argument Providers
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'ArgumentCompleter signature requires 3 parameters')]
param()

# GitHub CLI (gh)
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName gh -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $null = $commandAst; $null = $cursorPosition
        gh completion -s powershell | Out-String | Invoke-Expression
    }
}

# WinGet
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $commands = @(
            'install', 'show', 'source', 'search', 'list', 'upgrade',
            'uninstall', 'hash', 'validate', 'settings', 'features', 'export', 'import', 'pin', 'configure'
        )
        $commands | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# Docker
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName docker -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $commands = @(
            'build', 'run', 'ps', 'exec', 'logs', 'stop', 'start', 'restart', 'rm', 'rmi',
            'pull', 'push', 'images', 'compose', 'volume', 'network', 'system'
        )
        $commands | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# Kubectl
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName kubectl -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $commands = @('get', 'describe', 'create', 'apply', 'delete', 'log', 'logs', 'exec', 'port-forward', 'top', 'cluster-info', 'config')
        $commands | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# Helm
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName helm -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $commands = @('install', 'upgrade', 'list', 'uninstall', 'status', 'repo', 'dependency', 'package', 'search', 'show', 'template', 'lint')
        $commands | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# Terraform
if (Get-Command terraform -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName terraform -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $commands = @('init', 'plan', 'apply', 'destroy', 'fmt', 'validate', 'state', 'output', 'workspace', 'show', 'version')
        $commands | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# .NET CLI
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# Mise CLI
if (Get-Command mise -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName mise -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $commands = @('install', 'use', 'ls', 'current', 'run', 'env', 'exec', 'activate', 'settings', 'plugins')
        $commands | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}
