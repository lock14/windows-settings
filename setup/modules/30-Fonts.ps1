# =============================================================
# setup/modules/30-Fonts.ps1 - MesloLGS Nerd Font Mono Setup
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

Write-SetupStage -Stage '30-Fonts' -Message 'Setting up MesloLGS Nerd Font Mono (Nerd Fonts v3)...'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
$userFontsDir = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'Windows') 'Fonts'
$systemFontsDir = Join-Path $env:SystemRoot 'Fonts'
$targetFontsDir = if ($isAdmin) { $systemFontsDir } else { $userFontsDir }
$registryKey = if ($isAdmin) { 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' } else { 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' }

if (-not $DryRun -and -not (Test-Path -LiteralPath $userFontsDir -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $userFontsDir | Out-Null
}
if (-not $DryRun -and -not (Test-Path -LiteralPath $registryKey)) {
    New-Item -Path $registryKey -Force | Out-Null
}

$fontVersion = 'v3.5.1'
$fontZipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/$fontVersion/Meslo.zip"
$monoFonts = @(
    @{ File = 'MesloLGSNerdFontMono-Regular.ttf';    RegName = 'MesloLGS Nerd Font Mono Regular (TrueType)' },
    @{ File = 'MesloLGSNerdFontMono-Bold.ttf';       RegName = 'MesloLGS Nerd Font Mono Bold (TrueType)' },
    @{ File = 'MesloLGSNerdFontMono-Italic.ttf';     RegName = 'MesloLGS Nerd Font Mono Italic (TrueType)' },
    @{ File = 'MesloLGSNerdFontMono-BoldItalic.ttf'; RegName = 'MesloLGS Nerd Font Mono Bold Italic (TrueType)' }
)

$missingFonts = [System.Collections.Generic.List[hashtable]]::new()
foreach ($mf in $monoFonts) {
    $destPath = Join-Path $targetFontsDir $mf.File
    $userPath = Join-Path $userFontsDir $mf.File
    if ((-not (Test-Path -LiteralPath $destPath) -or ((Get-Item -LiteralPath $destPath).Length -lt 2500000)) -and
        (-not (Test-Path -LiteralPath $userPath) -or ((Get-Item -LiteralPath $userPath).Length -lt 2500000))) {
        $missingFonts.Add($mf)
    }
}

if ($missingFonts.Count -gt 0) {
    $cacheDir = Join-Path (Join-Path (Join-Path $userHome '.cache') 'windows-settings') 'fonts'
    $cachedZip = Join-Path $cacheDir "Meslo-$fontVersion.zip"

    if ($DryRun) {
        Write-SetupDryRun "Would download and extract MesloLGS Nerd Font Mono ($fontVersion) to $targetFontsDir"
    } else {
        if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
        }
        if (-not (Test-Path -LiteralPath $cachedZip -PathType Leaf) -or ((Get-Item -LiteralPath $cachedZip).Length -lt 10000000)) {
            Write-Host "Downloading MesloLGS Nerd Font ($fontVersion)..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $fontZipUrl -OutFile $cachedZip -UseBasicParsing
        }
        Write-SetupStep "Extracting MesloLGS Nerd Font Mono fonts into $userFontsDir..."
        $tempExtract = Join-Path $cacheDir "extract-$PID"
        if (-not (Test-Path -LiteralPath $tempExtract -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $tempExtract | Out-Null
        }
        try {
            Expand-Archive -LiteralPath $cachedZip -DestinationPath $tempExtract -Force
            foreach ($mf in $monoFonts) {
                $src = Join-Path $tempExtract $mf.File
                $usrDst = Join-Path $userFontsDir $mf.File
                if (Test-Path -LiteralPath $src -PathType Leaf) {
                    Copy-Item -LiteralPath $src -Destination $usrDst -Force
                }
            }
        } finally {
            Remove-Item -Recurse -Force -LiteralPath $tempExtract -ErrorAction SilentlyContinue
        }
    }
} elseif (-not $DryRun) {
    Write-Host 'MesloLGS Nerd Font Mono fonts already downloaded.' -ForegroundColor Green
}

$fontInstaller = Join-Path (Join-Path $RepoRoot 'bin') 'install-nerd-fonts.ps1'
if ($isAdmin -and (Test-Path -LiteralPath $fontInstaller -PathType Leaf)) {
    if ($DryRun) {
        Write-SetupDryRun "Would invoke $fontInstaller for system-wide registration in $systemFontsDir"
    } else {
        & $fontInstaller
    }
    return
}

foreach ($mf in $monoFonts) {
    $destPath = Join-Path $targetFontsDir $mf.File
    $regVal = if ($isAdmin) { $mf.File } else { $destPath }
    if ($DryRun) {
        Write-SetupDryRun "Would register font $($mf.RegName) in $registryKey"
    } elseif (Test-Path -LiteralPath $destPath -PathType Leaf) {
        Set-ItemProperty -Path $registryKey -Name $mf.RegName -Value $regVal -ErrorAction SilentlyContinue
    }
}

if (-not $isAdmin) {
    if ($DryRun) {
        Write-SetupDryRun "Would grant AppContainer read permissions on $userFontsDir"
    } else {
        Write-SetupStep 'Granting AppContainer permissions on user fonts folder...'
        & icacls "$userFontsDir" /grant '*S-1-15-2-1:(OI)(CI)(RX)' '*S-1-15-2-2:(OI)(CI)(RX)' 'BUILTIN\Users:(OI)(CI)(RX)' /T /C /Q | Out-Null
    }
}

$scopeLabel = if ($isAdmin) { "system-wide in $systemFontsDir" } else { "user scope in $userFontsDir" }
Write-SetupSuccess "MesloLGS Nerd Font Mono fonts configured ($scopeLabel)."
