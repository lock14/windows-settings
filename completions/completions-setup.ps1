<#
.SYNOPSIS
    Registers dynamic argument completions for installed CLI tools.
.DESCRIPTION
    High-performance completions loader with disk caching to eliminate startup overhead.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'ArgumentCompleter signature requires 3 parameters')]
param(
    [switch]$DryRun
)

$cacheDir = Join-Path $HOME '.cache\powershell'
if (-not $DryRun -and -not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
}

# 1. GitHub CLI (gh) - Cached
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghCache = Join-Path $cacheDir 'gh_completion.ps1'
    if ($DryRun) {
        Write-Host "  [DryRun] Would cache and register GitHub CLI completions ($ghCache)" -ForegroundColor DarkCyan
    } else {
        if (-not (Test-Path $ghCache)) {
            gh completion -s powershell | Out-File -FilePath $ghCache -Encoding utf8 -Force
        }
        if (Test-Path $ghCache) {
            . $ghCache
        }
    }
}

# 2. winget (Windows Package Manager) - Pure In-Memory Completer (<1ms)
if (Get-Command winget -ErrorAction SilentlyContinue) {
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

# 3. Docker CLI - Pure In-Memory Completer (<1ms)
if (Get-Command docker -ErrorAction SilentlyContinue) {
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

# 4. Kubernetes CLI (kubectl) - Cached
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    $k8sCache = Join-Path $cacheDir 'kubectl_completion.ps1'
    if ($DryRun) {
        Write-Host "  [DryRun] Would cache and register kubectl completions ($k8sCache)" -ForegroundColor DarkCyan
    } else {
        if (-not (Test-Path $k8sCache)) {
            kubectl completion powershell | Out-File -FilePath $k8sCache -Encoding utf8 -Force
        }
        if (Test-Path $k8sCache) {
            . $k8sCache
        }
    }
}

# 5. Helm CLI - Cached
if (Get-Command helm -ErrorAction SilentlyContinue) {
    $helmCache = Join-Path $cacheDir 'helm_completion.ps1'
    if ($DryRun) {
        Write-Host "  [DryRun] Would cache and register helm completions ($helmCache)" -ForegroundColor DarkCyan
    } else {
        if (-not (Test-Path $helmCache)) {
            helm completion powershell | Out-File -FilePath $helmCache -Encoding utf8 -Force
        }
        if (Test-Path $helmCache) {
            . $helmCache
        }
    }
}

# 6. Terraform CLI - Pure In-Memory Completer (<1ms)
if (Get-Command terraform -ErrorAction SilentlyContinue) {
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
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
