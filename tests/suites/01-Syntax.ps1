# =============================================================
# Suite 1: PowerShell AST Syntax Validation
# =============================================================
Write-Host "`n[1/8] Checking PowerShell Scripts & Module Syntax..." -ForegroundColor Yellow

$psFiles = Get-ChildItem -Path $RootDir -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|tests[\\/]temp|plugin[\\/]ws-bar[\\/]target)[\\/]' }

foreach ($file in $psFiles) {
    $parseErrors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    $relName = $file.FullName.Substring($RootDir.Length).TrimStart('\', '/').Replace('\', '/')
    if ($parseErrors.Count -eq 0) {
        Add-TestPass "Syntax valid: $relName"
    } else {
        $msg = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        Add-TestFail "Syntax invalid: $relName" $msg
    }
}
