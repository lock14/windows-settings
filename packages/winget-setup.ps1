<#
.SYNOPSIS
    Automates developer tool installation on Windows using winget.
.DESCRIPTION
    Equivalent to ubuntu_18+_setup.sh and fedora_30+_setup.sh in home-settings.
#>
[CmdletBinding()]
param(
    [switch]$IncludeGUI,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is required but was not found. Please install the Windows App Installer."
    exit 1
}

# Core CLI Developer Packages
$cliPackages = @(
    'Git.Git',
    'GitHub.cli',
    'JanDeDobbeleer.OhMyPosh',
    'BurntSushi.ripgrep.MSVC',
    'sharkdp.fd',
    'junegunn.fzf',
    'jqlang.jq',
    'GoLang.Go',
    'Hashicorp.Terraform',
    'Neovim.Neovim'
)

# GUI Developer Packages (Optional)
$guiPackages = @(
    'Microsoft.VisualStudioCode',
    'Microsoft.WindowsTerminal',
    'Docker.DockerDesktop'
)

$targetPackages = $cliPackages
if ($IncludeGUI) {
    $targetPackages += $guiPackages
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "       Workstation Tool Package Provisioning        " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

foreach ($pkg in $targetPackages) {
    Write-Host "`n==> Checking package: $pkg" -ForegroundColor Yellow
    if ($DryRun) {
        Write-Host "  [DryRun] Would install $pkg via winget" -ForegroundColor DarkGray
        continue
    }

    try {
        winget install --id $pkg -e --source winget --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Warning "Failed to install $pkg : $_"
    }
}

Write-Host "`n==> Workstation provisioning complete!" -ForegroundColor Green
