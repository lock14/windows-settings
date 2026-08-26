<#
.SYNOPSIS
    Registers dynamic argument completions for installed CLI tools.
.DESCRIPTION
    Ported and expanded from home-settings/completions-setup.sh for PowerShell 7.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'ArgumentCompleter signature requires 3 parameters')]
param()

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "==> Registering CLI tab completions..." -ForegroundColor Cyan

# 1. GitHub CLI (gh)
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "  Registering completions for: gh" -ForegroundColor Green
    Invoke-Expression (gh completion -s powershell | Out-String)
}

# 2. winget (Windows Package Manager)
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "  Registering completions for: winget" -ForegroundColor Green
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [System.String[]]$commands = @(
            'install', 'show', 'source', 'search', 'list', 'upgrade',
            'uninstall', 'hash', 'validate', 'settings', 'features', 'export', 'import', 'pin'
        )
        $commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# 3. Docker CLI
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "  Registering completions for: docker" -ForegroundColor Green
    Register-ArgumentCompleter -Native -CommandName docker -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [System.String[]]$commands = @(
            'build', 'run', 'ps', 'exec', 'logs', 'stop', 'start', 'restart', 'rm', 'rmi',
            'pull', 'push', 'images', 'compose', 'volume', 'network', 'system'
        )
        $commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# 4. Kubernetes CLI (kubectl)
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Write-Host "  Registering completions for: kubectl" -ForegroundColor Green
    kubectl completion powershell | Out-String | Invoke-Expression
}

# 5. Helm CLI
if (Get-Command helm -ErrorAction SilentlyContinue) {
    Write-Host "  Registering completions for: helm" -ForegroundColor Green
    helm completion powershell | Out-String | Invoke-Expression
}

# 6. Terraform CLI
if (Get-Command terraform -ErrorAction SilentlyContinue) {
    Write-Host "  Registering completions for: terraform" -ForegroundColor Green
    Register-ArgumentCompleter -Native -CommandName terraform -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [System.String[]]$commands = @(
            'init', 'validate', 'plan', 'apply', 'destroy', 'fmt', 'show',
            'output', 'state', 'workspace', 'import', 'version'
        )
        $commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# 7. .NET CLI (dotnet)
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    Write-Host "  Registering completions for: dotnet" -ForegroundColor Green
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

Write-Host "==> CLI completions registered successfully." -ForegroundColor Green
