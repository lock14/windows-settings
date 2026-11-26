# =============================================================
# setup/modules/10-Dotfiles.ps1 - CLI Tool Configs & Theme Specs
# =============================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
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

Write-SetupStage -Stage '10-Dotfiles' -Message 'Deploying CLI configurations and TrueColor theme specifications...'

$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
$wsConfigDir = Join-Path (Join-Path $userHome '.config') 'windows-settings'

# 1. Theme Palette Specifications (*.theme, strict LF)
$themesSrc = Join-Path (Join-Path $RepoRoot 'config') 'themes'
$themesDest = Join-Path $wsConfigDir 'themes'
Deploy-DirectoryFiles -Name 'palette theme specs' -SourceDir $themesSrc -Filter '*.theme' -DestinationDir $themesDest -ForceLf -DryRun:$DryRun

# 2. bat TrueColor Themes, Standalone Syntaxes & Config
if ($env:APPDATA) {
    $batConfigDir = Join-Path $env:APPDATA 'bat'
    $batThemesDest = Join-Path $batConfigDir 'themes'
    $batSyntaxesDest = Join-Path $batConfigDir 'syntaxes'
    $batConfigFile = Join-Path $batConfigDir 'config'
    $batRootSrc = Join-Path (Join-Path $RepoRoot 'config') 'bat'
    $targetBatTheme = '--theme="Solarized-Dark-TrueColor"'

    Deploy-ConfigFile -Name 'bat Solarized Dark theme' `
        -SourcePath (Join-Path $batRootSrc 'Solarized-Dark-TrueColor.tmTheme') `
        -DestinationPath (Join-Path $batThemesDest 'Solarized-Dark-TrueColor.tmTheme') `
        -DryRun:$DryRun

    Deploy-DirectoryFiles -Name 'bat TrueColor themes' `
        -SourceDir (Join-Path $batRootSrc 'themes') `
        -Filter '*.tmTheme' `
        -DestinationDir $batThemesDest `
        -ForceLf `
        -DryRun:$DryRun

    Deploy-DirectoryFiles -Name 'bat standalone syntaxes' `
        -SourceDir (Join-Path $batRootSrc 'syntaxes') `
        -Filter '*.sublime-syntax' `
        -DestinationDir $batSyntaxesDest `
        -ForceLf `
        -DryRun:$DryRun

    if ($DryRun) {
        Write-SetupDryRun "Would ensure --theme is configured in $batConfigFile and rebuild bat cache"
    } else {
        if (-not (Test-Path -LiteralPath $batConfigDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $batConfigDir | Out-Null
        }
        if (Test-Path -LiteralPath $batConfigFile -PathType Leaf) {
            $existingBatConfig = [System.IO.File]::ReadAllText($batConfigFile, [System.Text.Encoding]::UTF8)
            if ($existingBatConfig -notmatch '--theme=') {
                $nextBatCfg = $existingBatConfig.Replace("`r`n", "`n").TrimEnd("`n") + "`n$targetBatTheme`n"
                Write-FileAtomicUtf8NoBom -DestinationPath $batConfigFile -Content $nextBatCfg
            }
        } else {
            Write-FileAtomicUtf8NoBom -DestinationPath $batConfigFile -Content "$targetBatTheme`n"
        }
        $batCmd = Get-Command bat -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $batCmd) {
            & $batCmd.Source cache --build | Out-Null
        }
    }
}

# 3. Git Delta Config & Idempotent Global include.path
$deltaSrc = Join-Path (Join-Path (Join-Path $RepoRoot 'config') 'git') 'delta.gitconfig'
$deltaDest = Join-Path $wsConfigDir 'delta-theme.gitconfig'
if (-not (Test-Path -LiteralPath $deltaDest -PathType Leaf) -or $DryRun) {
    Deploy-ConfigFile -Name 'Git Delta theme config' -SourcePath $deltaSrc -DestinationPath $deltaDest -DryRun:$DryRun
}
$gitCmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $gitCmd) {
    $deltaInclude = '~/.config/windows-settings/delta-theme.gitconfig'
    $existingIncludes = @(& $gitCmd.Source config --global --get-all include.path 2>$null)
    if ($existingIncludes -notcontains $deltaInclude) {
        if ($DryRun) {
            Write-SetupDryRun "Would register git global include.path ($deltaInclude)"
        } else {
            & $gitCmd.Source config --global --add include.path $deltaInclude
            $existingPager = & $gitCmd.Source config --global --get core.pager 2>$null
            if (-not $existingPager -and (Get-Command delta -ErrorAction SilentlyContinue)) {
                & $gitCmd.Source config --global core.pager delta
                & $gitCmd.Source config --global interactive.diffFilter 'delta --color-only'
            }
        }
    }
}

# 4. Tealdeer (tldr)
if ($env:APPDATA) {
    $tealdeerSrc = Join-Path (Join-Path (Join-Path $RepoRoot 'config') 'tealdeer') 'config.toml'
    $tealdeerDest = Join-Path (Join-Path $env:APPDATA 'tealdeer') 'config.toml'
    if (-not (Test-Path -LiteralPath $tealdeerDest -PathType Leaf) -or $DryRun) {
        Deploy-ConfigFile -Name 'Tealdeer (tldr) config' -SourcePath $tealdeerSrc -DestinationPath $tealdeerDest -DryRun:$DryRun
    }
}

# 5. Clangd
if ($env:LOCALAPPDATA) {
    $clangdSrc = Join-Path (Join-Path (Join-Path $RepoRoot 'config') 'clangd') 'config.yaml'
    $clangdDest = Join-Path (Join-Path $env:LOCALAPPDATA 'clangd') 'config.yaml'
    Deploy-ConfigFile -Name 'Clangd config' -SourcePath $clangdSrc -DestinationPath $clangdDest -DryRun:$DryRun
}

# 6. btop4win Config & Themes
$btopRootSrc = Join-Path (Join-Path $RepoRoot 'config') 'btop'
$btopDestDir = Join-Path (Join-Path $userHome '.config') 'btop'
$btopConfDest = Join-Path $btopDestDir 'btop.conf'
if (-not (Test-Path -LiteralPath $btopConfDest -PathType Leaf) -or $DryRun) {
    Deploy-ConfigFile -Name 'btop config' -SourcePath (Join-Path $btopRootSrc 'btop.conf') -DestinationPath $btopConfDest -DryRun:$DryRun
}
Deploy-DirectoryFiles -Name 'btop TrueColor themes' `
    -SourceDir (Join-Path $btopRootSrc 'themes') `
    -Filter '*.theme' `
    -DestinationDir (Join-Path $btopDestDir 'themes') `
    -ForceLf `
    -DryRun:$DryRun
