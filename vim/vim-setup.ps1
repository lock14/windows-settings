<#
.SYNOPSIS
    Installs Vim and deploys _vimrc configuration.
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

# Deploy _vimrc configuration
$vimrcSource = Join-Path $ScriptDir '_vimrc'
if (Test-Path $vimrcSource) {
    $dest1 = Join-Path $HOME '_vimrc'
    $dest2 = Join-Path $HOME '.vimrc'
    Write-Host "==> Deploying Vim configuration to $dest1..." -ForegroundColor Cyan
    Copy-Item -Path $vimrcSource -Destination $dest1 -Force
    Copy-Item -Path $vimrcSource -Destination $dest2 -Force
    Write-Host "Vim configuration deployed successfully." -ForegroundColor Green
}

Write-Host "==> Vim setup complete!" -ForegroundColor Green
