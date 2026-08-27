<#
.SYNOPSIS
    Installs Vim, deploys _vimrc configuration, and provisions plugins.
.DESCRIPTION
    Ported from home-settings/vim-setup.sh for Windows.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Checking Vim installation..." -ForegroundColor Cyan

# Install Vim via winget if missing
if (-not (Get-Command vim -ErrorAction SilentlyContinue) -and -not (Test-Path "$env:LOCALAPPDATA\Programs\Vim\vim.exe")) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing Vim via winget..." -ForegroundColor Yellow
        winget install --id vim.vim -e --source winget --accept-package-agreements --accept-source-agreements
    } else {
        Write-Warning "winget not found. Please install Vim manually."
    }
}

# Ensure Vim directory is in User PATH
$vimDir = "$env:LOCALAPPDATA\Programs\Vim"
if (Test-Path $vimDir) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathParts = if ($userPath) { $userPath -split ';' } else { @() }
    if ($pathParts -notcontains $vimDir) {
        Write-Host "Adding Vim ($vimDir) to User PATH..." -ForegroundColor Cyan
        $newPath = ($pathParts + $vimDir) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $env:Path = "$env:Path;$vimDir"
    }
}

# Setup Vim Runtime Directory & Pathogen ($HOME\.vim)
$vimDir = Join-Path $HOME '.vim'
$autoload = Join-Path $vimDir 'autoload'
$bundle = Join-Path $vimDir 'bundle'
if (-not (Test-Path $autoload)) {
    New-Item -ItemType Directory -Force -Path $autoload | Out-Null
}
if (-not (Test-Path $bundle)) {
    New-Item -ItemType Directory -Force -Path $bundle | Out-Null
}

# Clean up legacy redundant vimfiles directory if present to prevent duplicate snippet mappings
$legacyVimfiles = Join-Path $HOME 'vimfiles'
if (Test-Path $legacyVimfiles) {
    Remove-Item -Recurse -Force -Path $legacyVimfiles -ErrorAction SilentlyContinue
}

# Install Pathogen
$pathogenFile = Join-Path $autoload 'pathogen.vim'
if (-not (Test-Path $pathogenFile)) {
    Write-Host "Installing Pathogen to $pathogenFile..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/tpope/vim-pathogen/master/autoload/pathogen.vim' -OutFile $pathogenFile -UseBasicParsing
}

# Install Vim Bundles (auto-pairs for brace matching, solarized, ultisnips, supertab)
$plugins = @(
    @{ Name = 'auto-pairs'; Url = 'https://github.com/jiangmiao/auto-pairs.git' },
    @{ Name = 'vim-colors-solarized'; Url = 'https://github.com/altercation/vim-colors-solarized.git' },
    @{ Name = 'ultisnips'; Url = 'https://github.com/SirVer/ultisnips.git' },
    @{ Name = 'supertab'; Url = 'https://github.com/ervandew/supertab.git' }
)

foreach ($p in $plugins) {
    $dest = Join-Path $bundle $p.Name
    if (-not (Test-Path "$dest\.git")) {
        Write-Host "Cloning $($p.Name) into $dest..." -ForegroundColor Cyan
        git clone --depth=1 $p.Url $dest
    }
}

# Deploy _vimrc configuration
$vimrcSource = Join-Path $ScriptDir '_vimrc'
if (Test-Path $vimrcSource) {
    $sourceContent = Get-Content $vimrcSource -Raw
    $destFiles = @(
        (Join-Path $HOME '_vimrc'),
        (Join-Path $HOME '.vimrc')
    )

    foreach ($dest in $destFiles) {
        if (Test-Path $dest) {
            $existingContent = Get-Content $dest -Raw
            if ($existingContent -ne $sourceContent) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $backupFile = "$dest.bak_$timestamp"
                Write-Host "Backing up existing Vim config to $backupFile..." -ForegroundColor Yellow
                Copy-Item -Path $dest -Destination $backupFile -Force

                Write-Host "==> Deploying Vim configuration to $dest..." -ForegroundColor Cyan
                Copy-Item -Path $vimrcSource -Destination $dest -Force
                Write-Host "Vim configuration deployed successfully to $dest." -ForegroundColor Green
            } else {
                Write-Host "==> Vim configuration at $dest is already up to date." -ForegroundColor Green
            }
        } else {
            Write-Host "==> Deploying Vim configuration to $dest..." -ForegroundColor Cyan
            Copy-Item -Path $vimrcSource -Destination $dest -Force
            Write-Host "Vim configuration deployed successfully to $dest." -ForegroundColor Green
        }
    }
}

# Deploy UltiSnips Snippets
$snippetsSource = Join-Path $ScriptDir 'UltiSnips'
if (Test-Path $snippetsSource) {
    $snippetsDest = Join-Path $vimDir 'UltiSnips'
    if (-not (Test-Path $snippetsDest)) {
        New-Item -ItemType Directory -Force -Path $snippetsDest | Out-Null
    }
    $snippetFiles = Get-ChildItem -Path $snippetsSource -Filter "*.snippets"
    foreach ($sf in $snippetFiles) {
        $destFile = Join-Path $snippetsDest $sf.Name
        $srcContent = Get-Content $sf.FullName -Raw
        if (Test-Path $destFile) {
            $dstContent = Get-Content $destFile -Raw
            if ($srcContent -ne $dstContent) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                Copy-Item -Path $destFile -Destination "$destFile.bak_$timestamp" -Force
                Copy-Item -Path $sf.FullName -Destination $destFile -Force
                Write-Host "Updated snippet: $destFile" -ForegroundColor Green
            }
        } else {
            Copy-Item -Path $sf.FullName -Destination $destFile -Force
            Write-Host "Installed snippet: $destFile" -ForegroundColor Green
        }
    }
}

Write-Host "==> Vim setup complete!" -ForegroundColor Green
