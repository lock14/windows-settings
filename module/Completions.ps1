# =============================================================
# CLI Tab Completions & Dynamic Argument Providers
# High-Speed In-Memory Registrations (<20ms total)
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'ArgumentCompleter signature requires 3 parameters')]
param()

# GitHub CLI (gh) - Cached on disk with binary-mtime invalidation on upgrades
$ghCache = Join-Path $HOME '.cache\powershell\gh_completion.ps1'
$ghBinTicks = if ($null -ne ${function:Get-WsBinaryTimestamp}) { Get-WsBinaryTimestamp 'gh.exe' } else { [long]0 }
$ghCacheValid = [System.IO.File]::Exists($ghCache) -and
    ([System.IO.FileInfo]::new($ghCache)).Length -gt 0 -and
    ($ghBinTicks -le 0 -or [System.IO.File]::GetLastWriteTimeUtc($ghCache).Ticks -ge $ghBinTicks)
if ($ghCacheValid) {
    . $ghCache
} elseif ($ghBinTicks -gt 0 -or (Get-Command gh -ErrorAction SilentlyContinue)) {
    $cacheDir = Join-Path $HOME '.cache\powershell'
    if (-not [System.IO.Directory]::Exists($cacheDir)) {
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    }
    gh completion -s powershell | Out-File -FilePath $ghCache -Encoding utf8 -Force
    if ([System.IO.File]::Exists($ghCache) -and ([System.IO.FileInfo]::new($ghCache)).Length -gt 0) {
        . $ghCache
    }
}

# Theme Engine (17 built-in palettes + custom user themes + flags)
Register-ArgumentCompleter -CommandName theme -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $candidates = [System.Collections.Generic.List[string]]@(
        'solarized-dark', 'solarized-light', 'catppuccin-mocha', 'catppuccin-latte',
        'gruvbox-dark', 'tokyonight-night', 'kanagawa-wave', 'nord', 'onedark',
        'new-years', 'valentines', 'st-patricks', 'easter',
        'independence-day', 'halloween', 'thanksgiving', 'christmas',
        '--list', '--current', '--set', '--preview', '--holiday', '--sync-assets',
        '--create', '--from', '--path', '--env', '--no-live', '--dry-run', '--plain', '--help'
    )
    foreach ($userDir in @(
        (Join-Path $HOME '.config\themes'),
        (Join-Path $HOME '.config\windows-settings\themes')
    )) {
        if ([System.IO.Directory]::Exists($userDir)) {
            foreach ($f in [System.IO.Directory]::GetFiles($userDir, '*.theme')) {
                $slug = [System.IO.Path]::GetFileNameWithoutExtension($f).ToLowerInvariant()
                if (-not $candidates.Contains($slug)) { $candidates.Add($slug) }
            }
        }
    }
    $candidates | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# IDE Workspace Launcher (flags + active/saved session names)
Register-ArgumentCompleter -CommandName ide -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $candidates = [System.Collections.Generic.List[string]]@(
        '--3pane', '--2pane', '--detach', '--desktop', '--new-window', '--backend',
        '--sessions', '--next-attention', '--toggle', '--focus-role',
        '--ai', '--open', '--preview', '--open-or-edit',
        '--cd', '--send', '--agent-state', '--ack-ai', '--open-pr',
        '--monitor', '--keys', '--refresh', '--quit', '--force', '--kill',
        '--list', '--plain', '--dry-run', '--help'
    )
    $ideStateDir = Join-Path $HOME '.cache\windows-settings\ide'
    if ([System.IO.Directory]::Exists($ideStateDir)) {
        foreach ($f in [System.IO.Directory]::GetFiles($ideStateDir, '*.json')) {
            $sName = [System.IO.Path]::GetFileNameWithoutExtension($f)
            if (-not $candidates.Contains($sName)) { $candidates.Add($sName) }
        }
    }
    $candidates | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Unified Workstation Updater (update / update-system)
Register-ArgumentCompleter -CommandName update, update-system -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $flags = @(
        '--system-only', '--skip-winget', '--skip-mise', '--skip-modules',
        '--skip-nvim', '--dry-run', '--help'
    )
    $flags | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
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
    $commands = @('install', 'upgrade', 'prune', 'use', 'ls', 'current', 'run', 'env', 'exec', 'activate', 'bin-paths', 'settings', 'plugins')
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
