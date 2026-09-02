<#
.SYNOPSIS
    Downloads and installs MesloLGS NF fonts for the current user.
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$baseUrl = "https://github.com/romkatv/powerlevel10k-media/raw/master"
$fonts = @(
    "MesloLGS NF Regular.ttf",
    "MesloLGS NF Bold.ttf",
    "MesloLGS NF Italic.ttf",
    "MesloLGS NF Bold Italic.ttf"
)

$userFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
if (-not $DryRun -and -not (Test-Path $userFontsDir)) {
    New-Item -ItemType Directory -Force -Path $userFontsDir | Out-Null
}

$registryKey = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
if (-not $DryRun -and -not (Test-Path $registryKey)) {
    New-Item -Path $registryKey -Force | Out-Null
}

Write-Host "==> Installing MesloLGS NF fonts into $userFontsDir..." -ForegroundColor Cyan

foreach ($font in $fonts) {
    $destPath = Join-Path $userFontsDir $font
    $encodedFont = [System.Uri]::EscapeDataString($font)
    $fontUrl = "$baseUrl/$encodedFont"
    $fontName = [System.IO.Path]::GetFileNameWithoutExtension($font) + " (TrueType)"

    if ($DryRun) {
        if (-not (Test-Path $destPath)) {
            Write-Host "  [DryRun] Would download $font to $destPath" -ForegroundColor DarkCyan
        } else {
            Write-Host "  [DryRun] $font already downloaded." -ForegroundColor DarkCyan
        }
        Write-Host "  [DryRun] Would register font $fontName in $registryKey" -ForegroundColor DarkCyan
        continue
    }

    if (-not (Test-Path $destPath)) {
        Write-Host "Downloading $font..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $fontUrl -OutFile $destPath -UseBasicParsing
    } else {
        Write-Host "$font already downloaded." -ForegroundColor Green
    }

    # Register in user registry
    Set-ItemProperty -Path $registryKey -Name $fontName -Value $destPath -ErrorAction SilentlyContinue
}

Write-Host "==> MesloLGS NF fonts installed successfully." -ForegroundColor Green
