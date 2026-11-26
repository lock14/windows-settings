<#
.SYNOPSIS
    Unified Multi-Theme Color Scheme Manager for windows-settings.
.DESCRIPTION
    Manages the built-in TrueColor themes (classic developer palettes and US Holiday editions)
    and custom user themes across Zellij, Windows Terminal, Neovim (live Named Pipe RPC), Vim,
    PowerShell 7 + PSReadLine, Oh My Posh, Command Prompt (autorun.cmd), bat, delta,
    btop4win, tealdeer, fzf, eza, jq, and GNU dircolors (LS_COLORS).

    Internal domain logic is modularized under libexec/theme/*.ps1 and dot-sourced on demand:
      - Palette.ps1    : Schema, dynamic discovery, holiday calendar, and perceptual color math
      - Generators.ps1 : Shell/CMD env, delta, tealdeer, btop, Zellij KDL, tmTheme, and WT schemes
      - Sync.ps1       : Deterministic repository asset & bounded-block synchronizer/verifier
      - Preview.ps1    : ANSI cell width, 4-tier color capability, preview cards, and fzf picker
      - Reload.ps1     : SHA-256 asset materialization, bat cache rebuild, and live RPC/OSC reload
#>

$ErrorActionPreference = 'Stop'

$rawScriptPath = $MyInvocation.MyCommand.Path
try {
    $itemInfo = [System.IO.FileInfo]::new($rawScriptPath)
    if ($itemInfo.LinkTarget) {
        $resolvedTarget = if ([System.IO.Path]::IsPathRooted($itemInfo.LinkTarget)) {
            $itemInfo.LinkTarget
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $itemInfo.DirectoryName $itemInfo.LinkTarget))
        }
        if ([System.IO.File]::Exists($resolvedTarget)) { $rawScriptPath = $resolvedTarget }
    }
} catch { $null = $_ }

$ScriptDir = Split-Path -Parent $rawScriptPath
$RepoDir = Split-Path -Parent $ScriptDir
$ThemeLibDir = Join-Path (Join-Path $RepoDir 'libexec') 'theme'

. (Join-Path $ThemeLibDir 'Palette.ps1')

$action = $null
$targetName = $null
$baseName = 'solarized-dark'
$force = $false
$dryRun = $false
$noLive = $false
$plain = $false
$resolveHoliday = $false
$staticOnly = $false
$endOfOpts = $false

:ArgLoop for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    if (-not $endOfOpts -and $arg -eq '--') { $endOfOpts = $true; continue ArgLoop }
    if (-not $endOfOpts) {
        switch -Regex ($arg) {
            '^(-h|--help|-Help|-\?)$' { Write-Output (Build-ThemeUsageText -RootDir $RepoDir); exit 0 }
            '^(-l|--list|-List)$'     { $action = 'list'; continue ArgLoop }
            '^(--plain|-Plain)$'      { $plain = $true; if (-not $action) { $action = 'list' }; continue ArgLoop }
            '^(-c|--current|-Current)$' { $action = 'current'; continue ArgLoop }
            '^(--sync-assets|-SyncAssets)$'   { $action = 'sync-assets'; continue ArgLoop }
            '^(--check-assets|-CheckAssets)$' { $action = 'check-assets'; continue ArgLoop }
            '^(--static-only|-StaticOnly)$'   { $staticOnly = $true; continue ArgLoop }
            '^(-n|--dry-run|-DryRun)$' { $dryRun = $true; continue ArgLoop }
            '^(--no-live|-NoLive)$'    { $noLive = $true; continue ArgLoop }
            '^(-f|--force|-Force)$'    { $force = $true; continue ArgLoop }
            '^(--holiday|-Holiday)$'   { $action = 'set'; $resolveHoliday = $true; continue ArgLoop }
            '^(-s|--set|-Set|--set=.*)$' {
                $parsed = Read-ThemeOptionValue -ArgList $args -Index $i -DisplayOpt '--set' -Noun 'a theme name' -Optional $false
                if ($parsed.Error) { [Console]::Error.WriteLine($parsed.Error); exit 1 }
                $i = $parsed.NextIndex; $action = 'set'; $resolveHoliday = $false; $targetName = $parsed.Value; continue ArgLoop
            }
            '^(-p|--preview|-Preview|--preview=.*)$' {
                $parsed = Read-ThemeOptionValue -ArgList $args -Index $i -DisplayOpt '--preview' -Noun 'a theme name' -Optional $true
                if ($parsed.Error) { [Console]::Error.WriteLine($parsed.Error); exit 1 }
                $i = $parsed.NextIndex; $action = 'preview'; if ($null -ne $parsed.Value) { $targetName = $parsed.Value }; continue ArgLoop
            }
            '^(--env|-Env|--env=.*)$' {
                $parsed = Read-ThemeOptionValue -ArgList $args -Index $i -DisplayOpt '--env' -Noun 'a theme name' -Optional $true
                if ($parsed.Error) { [Console]::Error.WriteLine($parsed.Error); exit 1 }
                $i = $parsed.NextIndex; $action = 'env'; if ($null -ne $parsed.Value) { $targetName = $parsed.Value }; continue ArgLoop
            }
            '^(--path|-Path|--path=.*)$' {
                $parsed = Read-ThemeOptionValue -ArgList $args -Index $i -DisplayOpt '--path' -Noun 'a theme name' -Optional $true
                if ($parsed.Error) { [Console]::Error.WriteLine($parsed.Error); exit 1 }
                $i = $parsed.NextIndex; $action = 'path'; if ($null -ne $parsed.Value) { $targetName = $parsed.Value }; continue ArgLoop
            }
            '^(--create|-Create|--create=.*)$' {
                $parsed = Read-ThemeOptionValue -ArgList $args -Index $i -DisplayOpt '--create' -Noun 'a new theme name' -Optional $false
                if ($parsed.Error) { [Console]::Error.WriteLine($parsed.Error); exit 1 }
                $i = $parsed.NextIndex; $action = 'create'; $targetName = $parsed.Value; continue ArgLoop
            }
            '^(--from|-From|--from=.*)$' {
                $parsed = Read-ThemeOptionValue -ArgList $args -Index $i -DisplayOpt '--from' -Noun 'a base theme name' -Optional $false
                if ($parsed.Error) { [Console]::Error.WriteLine($parsed.Error); exit 1 }
                $i = $parsed.NextIndex; $baseName = $parsed.Value; continue ArgLoop
            }
            '^-.*$' { [Console]::Error.WriteLine("theme: unknown option '$arg' (try 'theme --help')"); exit 1 }
        }
    }
    if (-not $arg.Trim()) { [Console]::Error.WriteLine('theme: theme name must not be empty'); exit 1 }
    if ($null -ne $targetName -or $resolveHoliday) { [Console]::Error.WriteLine("theme: unexpected extra argument '$arg'"); exit 1 }
    $targetName = $arg
    if (-not $action) { $action = 'set' }
}

if ($action -eq 'path') {
    if ($null -eq $targetName) { Write-Output (Get-UserThemeDirList)[0]; exit 0 }
    try { $resolvedPathTheme = Resolve-SingleThemeFast -RepoDir $RepoDir -RawSlug $targetName }
    catch { [Console]::Error.WriteLine("theme: $($_.Exception.Message)"); exit 1 }
    if ($null -eq $resolvedPathTheme) {
        [Console]::Error.WriteLine("theme: unknown theme '$targetName' (run 'theme --list' to see available themes)")
        exit 1
    }
    Write-Output $resolvedPathTheme['PATH']; exit 0
}

if ($action -eq 'current') {
    try { Write-Output (Resolve-CurrentSlugFast -RepoDir $RepoDir); exit 0 }
    catch { [Console]::Error.WriteLine("theme: $($_.Exception.Message)"); exit 1 }
}

if ($action -in @('sync-assets', 'check-assets')) {
    . (Join-Path $ThemeLibDir 'Generators.ps1')
    . (Join-Path $ThemeLibDir 'Sync.ps1')
    try { $drift = @(Sync-ManagedRepoAsset -RepoDir $RepoDir -CheckOnly (($action -eq 'check-assets') -or $dryRun) -StaticOnly $staticOnly) }
    catch { [Console]::Error.WriteLine("theme: $($_.Exception.Message)"); exit 1 }
    if ($action -eq 'check-assets') {
        if ($drift.Count -gt 0) {
            foreach ($item in $drift) { [Console]::Error.WriteLine("theme: asset out of sync: $item") }
            [Console]::Error.WriteLine("theme: run './bin/theme.ps1 --sync-assets' to synchronize derived theme files")
            exit 1
        }
        exit 0
    }
    if ($dryRun) {
        if ($drift.Count -eq 0) { Write-Output '[DRY-RUN] All repository theme assets are already in sync' }
        else { foreach ($item in $drift) { Write-Output "[DRY-RUN] Would synchronize repository asset: $item" } }
    }
    exit 0
}

$script:ThemeExitCode = 0

if (-not $resolveHoliday -and ($action -in @('preview', 'env', 'set') -or ($dryRun -and $null -ne $targetName -and $action -notin @('list', 'create')))) {
    try {
        $rawTarget = if ($null -eq $targetName) { Resolve-CurrentSlugFast -RepoDir $RepoDir } else { $targetName }
        $singleTheme = Resolve-SingleThemeFast -RepoDir $RepoDir -RawSlug $rawTarget
    } catch { [Console]::Error.WriteLine("theme: $($_.Exception.Message)"); exit 1 }
    if ($null -eq $singleTheme) {
        [Console]::Error.WriteLine("theme: unknown theme '$rawTarget' (run 'theme --list' to see available themes)")
        exit 1
    }
    if ($action -eq 'preview') {
        . (Join-Path $ThemeLibDir 'Preview.ps1')
        Show-ThemePreview -Theme $singleTheme; exit $script:ThemeExitCode
    }
    . (Join-Path $ThemeLibDir 'Generators.ps1')
    . (Join-Path $ThemeLibDir 'Reload.ps1')
    if ($action -eq 'env') { Write-Output (Build-PowerShellThemeEnv -Theme $singleTheme -RepoDir $RepoDir); exit 0 }
    Invoke-ApplyTheme -Theme $singleTheme -RepoDir $RepoDir -DryRun $dryRun -NoLive $noLive
    exit $script:ThemeExitCode
}

try { $themes = Get-DiscoveredThemeMap -RepoDir $RepoDir }
catch { [Console]::Error.WriteLine("theme: $($_.Exception.Message)"); exit 1 }

if ($resolveHoliday) {
    try { $targetName = Resolve-NearestHolidaySlug -Themes $themes -RepoDir $RepoDir }
    catch { [Console]::Error.WriteLine("theme: $($_.Exception.Message)"); exit 1 }
    . (Join-Path $ThemeLibDir 'Generators.ps1')
    . (Join-Path $ThemeLibDir 'Reload.ps1')
    Invoke-ApplyTheme -Theme $themes[$targetName] -RepoDir $RepoDir -DryRun $dryRun -NoLive $noLive
    exit $script:ThemeExitCode
}

$currentSlug = Get-CurrentThemeSlug -Themes $themes

if ($action -eq 'list') {
    if ($plain) { foreach ($slug in (Get-OrderedThemeSlugList -Themes $themes)) { Write-Output $slug }; exit 0 }
    . (Join-Path $ThemeLibDir 'Preview.ps1')
    Show-ThemeList -Themes $themes -CurrentSlug $currentSlug -Plain $false; exit $script:ThemeExitCode
}

if ($action -eq 'create') {
    . (Join-Path $ThemeLibDir 'Generators.ps1')
    . (Join-Path $ThemeLibDir 'Reload.ps1')
    Initialize-CustomUserTheme -NewName $targetName -BaseSlug $baseName -Themes $themes -Force $force -DryRun $dryRun
    exit $script:ThemeExitCode
}

if ($dryRun -and $null -eq $targetName) {
    . (Join-Path $ThemeLibDir 'Generators.ps1')
    . (Join-Path $ThemeLibDir 'Reload.ps1')
    Invoke-ApplyTheme -Theme $themes[$currentSlug] -RepoDir $RepoDir -DryRun $true -NoLive $noLive
    exit $script:ThemeExitCode
}

if ((-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) -or $env:THEME_FORCE_FZF -eq '1') {
    . (Join-Path $ThemeLibDir 'Generators.ps1')
    . (Join-Path $ThemeLibDir 'Reload.ps1')
    . (Join-Path $ThemeLibDir 'Preview.ps1')
    Invoke-FzfThemePicker -Themes $themes -CurrentSlug $currentSlug -RepoDir $RepoDir -DryRun $dryRun -NoLive $noLive
    exit $script:ThemeExitCode
}

. (Join-Path $ThemeLibDir 'Preview.ps1')
Show-ThemeList -Themes $themes -CurrentSlug $currentSlug -Plain $false
exit $script:ThemeExitCode
