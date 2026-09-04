# =============================================================
# CLI Tab Completions & Dynamic Argument Providers
# High-Speed In-Memory Registrations (<20ms total)
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'ArgumentCompleter signature requires 3 parameters')]
param()

# GitHub CLI (gh) - Cached on disk
$ghCache = "$HOME\.cache\powershell\gh_completion.ps1"
if ((Test-Path $ghCache) -and (Get-Item $ghCache).Length -gt 0) {
    . $ghCache
} elseif (Get-Command gh -ErrorAction SilentlyContinue) {
    if (-not (Test-Path "$HOME\.cache\powershell")) {
        New-Item -ItemType Directory -Force -Path "$HOME\.cache\powershell" | Out-Null
    }
    gh completion -s powershell | Out-File -FilePath $ghCache -Encoding utf8 -Force
    if ((Test-Path $ghCache) -and (Get-Item $ghCache).Length -gt 0) {
        . $ghCache
    }
}

# WinGet
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @(
        'install', 'show', 'source', 'search', 'list', 'upgrade',
        'uninstall', 'hash', 'validate', 'settings', 'features', 'export', 'import', 'pin', 'configure'
    )
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Docker
Register-ArgumentCompleter -Native -CommandName docker -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @(
        'build', 'run', 'ps', 'exec', 'logs', 'stop', 'start', 'restart', 'rm', 'rmi',
        'pull', 'push', 'images', 'compose', 'volume', 'network', 'system'
    )
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Kubectl
Register-ArgumentCompleter -Native -CommandName kubectl -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @('get', 'describe', 'create', 'apply', 'delete', 'log', 'logs', 'exec', 'port-forward', 'top', 'cluster-info', 'config')
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Helm
Register-ArgumentCompleter -Native -CommandName helm -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @('install', 'upgrade', 'list', 'uninstall', 'status', 'repo', 'dependency', 'package', 'search', 'show', 'template', 'lint')
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Terraform
Register-ArgumentCompleter -Native -CommandName terraform -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @('init', 'plan', 'apply', 'destroy', 'fmt', 'validate', 'state', 'output', 'workspace', 'show', 'version')
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# .NET CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $wordToComplete
    dotnet complete --position $cursorPosition "$commandAst" |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Mise CLI
Register-ArgumentCompleter -Native -CommandName mise -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @('install', 'use', 'ls', 'current', 'run', 'env', 'exec', 'activate', 'settings', 'plugins')
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
