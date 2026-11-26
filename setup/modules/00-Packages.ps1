# =============================================================
# setup/modules/00-Packages.ps1 - WinGet CLI, DSC & GUI Packages
# =============================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [switch]$UseDSC,
    [AllowEmptyCollection()]
    [string[]]$Gui = @(),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command Write-SetupStage -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib') 'Log.ps1')
}

Write-SetupStage -Stage '00-Packages' -Message 'Provisioning workstation packages via WinGet...'

$guiPackageMap = [ordered]@{
    vscode   = 'Microsoft.VisualStudioCode'
    terminal = 'Microsoft.WindowsTerminal'
    docker   = 'Docker.DockerDesktop'
}

$resolvedGuiPackages = [System.Collections.Generic.List[string]]::new()
foreach ($g in $Gui) {
    $key = "$g".Trim().ToLowerInvariant()
    if ($guiPackageMap.Contains($key) -and -not $resolvedGuiPackages.Contains($guiPackageMap[$key])) {
        $resolvedGuiPackages.Add($guiPackageMap[$key])
    }
}

$dscFile = Join-Path $RepoRoot 'configuration.dsc.yaml'
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

if ($UseDSC -and (Test-Path -LiteralPath $dscFile -PathType Leaf)) {
    Write-SetupStep "Executing declarative WinGet DSC configuration ($dscFile)..."
    if ($DryRun) {
        Write-SetupDryRun "Would execute: winget configure $dscFile --accept-configuration-agreements"
    } elseif (-not $hasWinget) {
        Write-SetupWarn 'winget is required to run DSC configuration. Please install Windows App Installer.'
    } else {
        & winget configure $dscFile --accept-configuration-agreements
    }
    foreach ($guiPkg in $resolvedGuiPackages) {
        Write-SetupStep "Checking optional GUI package: $guiPkg"
        if ($DryRun) {
            Write-SetupDryRun "Would install $guiPkg via winget"
        } elseif ($hasWinget) {
            & winget install --id $guiPkg -e --source winget --accept-package-agreements --accept-source-agreements
        }
    }
} else {
    if (-not $hasWinget -and -not $DryRun) {
        Write-SetupWarn 'winget is required for package installation. Please install Windows App Installer.'
        return
    }

    $cliPackages = @(
        'uutils.coreutils', 'uutils.diffutils', 'Git.Git', 'GitHub.cli',
        'ajeetdsouza.zoxide', 'JanDeDobbeleer.OhMyPosh', 'BurntSushi.ripgrep.MSVC',
        'sharkdp.fd', 'sharkdp.bat', 'eza-community.eza', 'dandavison.delta',
        'junegunn.fzf', 'jqlang.jq', 'MikeFarah.yq', 'bootandy.dust',
        'chmln.sd', 'dbrgn.tealdeer', 'aristocratos.btop4win', 'Zellij.Zellij',
        'jdx.mise', 'vim.vim', 'BrechtSanders.WinLibs.POSIX.UCRT'
    )
    $targetPackages = @($cliPackages) + @($resolvedGuiPackages)

    foreach ($pkg in $targetPackages) {
        Write-Host "`n==> Checking package: $pkg" -ForegroundColor Yellow
        if ($DryRun) {
            Write-SetupDryRun "Would install $pkg via winget"
        } else {
            & winget install --id $pkg -e --source winget --accept-package-agreements --accept-source-agreements
        }
    }

    if ($env:LOCALAPPDATA) {
        $linksDir = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'WinGet') 'Links'
        $pkgDir = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'WinGet') 'Packages'
        if (Test-Path -LiteralPath $pkgDir -PathType Container) {
            if (-not (Test-Path -LiteralPath $linksDir -PathType Container) -and -not $DryRun) {
                New-Item -ItemType Directory -Force -Path $linksDir | Out-Null
            }
            $exes = Get-ChildItem -LiteralPath $pkgDir -Filter '*.exe' -Recurse -File -ErrorAction SilentlyContinue
            foreach ($exe in $exes) {
                $targetLink = Join-Path $linksDir $exe.Name
                if (-not (Test-Path -LiteralPath $targetLink)) {
                    if ($DryRun) {
                        Write-SetupDryRun "Would link $($exe.Name) into $linksDir"
                    } else {
                        try {
                            New-Item -ItemType HardLink -Path $targetLink -Target $exe.FullName -Force -ErrorAction SilentlyContinue | Out-Null
                        } catch {
                            Copy-Item -LiteralPath $exe.FullName -Destination $targetLink -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }
    }
}
