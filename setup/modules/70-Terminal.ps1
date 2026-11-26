# =============================================================
# setup/modules/70-Terminal.ps1 - Zellij, WT Fragment & Theme
# =============================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [string]$Theme = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
if (-not (Get-Command Write-SetupStage -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Log.ps1')
}
if (-not (Get-Command Deploy-ConfigFile -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Deploy.ps1')
}

Write-SetupStage -Stage '70-Terminal' -Message 'Configuring Zellij workspace, Windows Terminal fragment, and active theme...'
$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }

# 1. Zellij WASM Top Bar, Permissions, Config, Layouts & Theme Seed
$zellijSrcDir = Join-Path (Join-Path $RepoRoot 'config') 'zellij'
$zellijDestDir = if ($env:APPDATA) {
    Join-Path (Join-Path $env:APPDATA 'Zellij') 'config'
} else {
    Join-Path (Join-Path $userHome '.config') 'zellij'
}

$useWasmBar = Sync-ZellijBarPlugin -RepoRoot $RepoRoot -DryRun:$DryRun
if ($useWasmBar) {
    Sync-ZellijPluginPermission -DryRun:$DryRun
}

if (Test-Path -LiteralPath $zellijSrcDir -PathType Container) {
    Deploy-ZellijConfig -SourcePath (Join-Path $zellijSrcDir 'config.kdl') `
        -DestinationPath (Join-Path $zellijDestDir 'config.kdl') `
        -UseWasmBar $useWasmBar `
        -DryRun:$DryRun

    Deploy-ConfigFile -Name 'Zellij 3-pane IDE layout' `
        -SourcePath (Join-Path (Join-Path $zellijSrcDir 'layouts') 'ide-3pane.kdl') `
        -DestinationPath (Join-Path (Join-Path $zellijDestDir 'layouts') 'ide-3pane.kdl') `
        -DryRun:$DryRun

    Deploy-ConfigFile -Name 'Zellij 2-pane IDE layout' `
        -SourcePath (Join-Path (Join-Path $zellijSrcDir 'layouts') 'ide-2pane.kdl') `
        -DestinationPath (Join-Path (Join-Path $zellijDestDir 'layouts') 'ide-2pane.kdl') `
        -DryRun:$DryRun

    $zellijThemeSeedDst = Join-Path (Join-Path $zellijDestDir 'themes') 'windows-settings.kdl'
    if (-not (Test-Path -LiteralPath $zellijThemeSeedDst -PathType Leaf) -or $DryRun) {
        Deploy-ConfigFile -Name 'Zellij theme seed' `
            -SourcePath (Join-Path (Join-Path $zellijSrcDir 'themes') 'windows-settings.kdl') `
            -DestinationPath $zellijThemeSeedDst `
            -DryRun:$DryRun
    }
}

# 2. Windows Terminal Zero-Touch JSON Fragment
if ($env:LOCALAPPDATA) {
    $fragmentSource = Join-Path (Join-Path (Join-Path $RepoRoot 'config') 'terminal') 'windows-settings.json'
    $primaryDest = Join-Path (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'Windows Terminal') 'Fragments\WindowsSettings') 'windows-settings.json'
    $altDests = @(
        (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Packages') 'Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings') 'windows-settings.json'),
        (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Packages') 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings') 'windows-settings.json')
    )
    Deploy-ConfigFile -Name 'Windows Terminal JSON Fragment' `
        -SourcePath $fragmentSource `
        -DestinationPath $primaryDest `
        -AltDestinations $altDests `
        -DryRun:$DryRun
}

# 3. Apply Active Color Theme via bin/theme.ps1
$themeScript = Join-Path (Join-Path $RepoRoot 'bin') 'theme.ps1'
if (Test-Path -LiteralPath $themeScript -PathType Leaf) {
    $savedThemeFile = Join-Path (Join-Path (Join-Path $userHome '.config') 'windows-settings') 'theme'
    $targetTheme = if ($Theme -and $Theme.Trim()) {
        $Theme.Trim().ToLowerInvariant()
    } elseif (Test-Path -LiteralPath $savedThemeFile -PathType Leaf) {
        ([System.IO.File]::ReadAllText($savedThemeFile, [System.Text.Encoding]::UTF8)).Trim().ToLowerInvariant()
    } else {
        'solarized-dark'
    }
    if (-not $targetTheme) { $targetTheme = 'solarized-dark' }

    if ($DryRun) {
        if ($targetTheme -eq 'holiday') {
            & $themeScript --dry-run --holiday --no-live | Out-Host
        } else {
            & $themeScript --dry-run --set $targetTheme --no-live | Out-Host
        }
    } else {
        $themeArgs = if ($targetTheme -eq 'holiday') { @('--holiday') } else { @('--set', $targetTheme) }
        if ([Console]::IsOutputRedirected -or $env:WS_TEST_MODE -eq '1') {
            $themeArgs += '--no-live'
        }
        & $themeScript @themeArgs | Out-Host
    }
}
