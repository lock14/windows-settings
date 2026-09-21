<#
.SYNOPSIS
    Installs MesloLGS Nerd Font (Nerd Fonts v3) system-wide into C:\Windows\Fonts.
.DESCRIPTION
    Copies downloaded MesloLGS Nerd Font Mono and proportional fonts from the user
    font cache into the system fonts directory (%SystemRoot%\Fonts) and registers
    them in HKLM so Windows Terminal and other AppContainer applications can resolve
    them without permissions issues. Requires Administrator privileges.
.EXAMPLE
    install-nerd-fonts.ps1
#>
[CmdletBinding()]
param()

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Administrator privileges are required to install fonts system-wide into C:\Windows\Fonts. Please run PowerShell as Administrator and re-run this script."
    exit 1
}

$userFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
$systemFontsDir = Join-Path $env:SystemRoot "Fonts"
$regKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

$fontPatterns = @("MesloLGSNerdFont*.ttf")
$installedCount = 0

foreach ($pattern in $fontPatterns) {
    $fonts = Get-ChildItem -Path $userFontsDir -Filter $pattern -ErrorAction SilentlyContinue
    foreach ($font in $fonts) {
        $destPath = Join-Path $systemFontsDir $font.Name
        Copy-Item -Path $font.FullName -Destination $destPath -Force
        $fontName = $font.BaseName + " (TrueType)"
        Set-ItemProperty -Path $regKey -Name $fontName -Value $font.Name -ErrorAction SilentlyContinue
        $installedCount++
        Write-Host "  Installed $($font.Name) system-wide" -ForegroundColor Green
    }
}

if ($installedCount -gt 0) {
    $sig = @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern bool SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $win32 = Add-Type -MemberDefinition $sig -Name "FontBroadcast" -Namespace "NerdFontInstaller" -PassThru -ErrorAction SilentlyContinue
    if ($win32) {
        $result = [UIntPtr]::Zero
        [void]$win32::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 0x0002, 1000, [ref]$result)
    }
    Write-Host "==> Successfully installed $installedCount MesloLGS Nerd Font files system-wide in $systemFontsDir." -ForegroundColor Green
} else {
    Write-Warning "No font files found matching '$($fontPatterns -join ', ')' in $userFontsDir. Run setup.ps1 first to download the fonts."
}
