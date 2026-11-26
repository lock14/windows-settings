# =============================================================
# setup/lib/Env.ps1 - User PATH, Mise PATH & Shell Cache Sync
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Shared environment and compiled cache sync contract')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'All helpers implement explicit -DryRun preview switches')]
param()

function Add-SessionPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [switch]$Prepend
    )
    if (-not $Directory -or -not [System.IO.Directory]::Exists($Directory)) { return }
    $norm = $Directory.Trim().TrimEnd('\')
    $parts = @($env:Path.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries))
    foreach ($p in $parts) {
        if ([string]::Equals($p.Trim().TrimEnd('\'), $norm, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }
    $env:Path = if ($Prepend) { "$norm;$env:Path" } else { "$env:Path;$norm" }
}

function Add-UserPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [switch]$Prepend,
        [switch]$DryRun
    )
    if (-not $Directory) { return }
    $norm = $Directory.Trim().TrimEnd('\')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = if ($userPath) { @($userPath -split ';' | Where-Object { $_ -and $_.Trim() }) } else { @() }
    $alreadyPresent = $false
    foreach ($p in $parts) {
        if ([string]::Equals($p.Trim().TrimEnd('\'), $norm, [System.StringComparison]::OrdinalIgnoreCase)) {
            $alreadyPresent = $true
            break
        }
    }
    if ($alreadyPresent) {
        Write-Host "  $norm is already in User PATH." -ForegroundColor Green
        Add-SessionPathEntry -Directory $norm -Prepend:$Prepend
        return
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would add $norm to User PATH" -ForegroundColor DarkCyan
        return
    }

    $updatedParts = if ($Prepend) { @($norm) + $parts } else { $parts + @($norm) }
    [Environment]::SetEnvironmentVariable('Path', ($updatedParts -join ';'), 'User')
    Add-SessionPathEntry -Directory $norm -Prepend:$Prepend
    Write-Host "==> Added $norm to User PATH" -ForegroundColor Green
}

function Remove-UserPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [switch]$DryRun
    )
    if (-not $Directory) { return }
    $norm = $Directory.Trim().TrimEnd('\')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = if ($userPath) { @($userPath -split ';' | Where-Object { $_ -and $_.Trim() }) } else { @() }
    $matching = @($parts | Where-Object { [string]::Equals($_.Trim().TrimEnd('\'), $norm, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($matching.Count -eq 0) {
        Write-Host "  $norm is not present in User PATH." -ForegroundColor Green
        return
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would remove $norm from User PATH" -ForegroundColor DarkCyan
        return
    }

    $filtered = @($parts | Where-Object { -not [string]::Equals($_.Trim().TrimEnd('\'), $norm, [System.StringComparison]::OrdinalIgnoreCase) })
    [Environment]::SetEnvironmentVariable('Path', ($filtered -join ';'), 'User')
    Write-Host "  Removed $norm from User PATH" -ForegroundColor Green
}

function Write-CacheFileCrlf([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not [System.IO.Directory]::Exists($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $crlf = ($Content.Replace("`r`n", "`n").TrimEnd("`n") -replace "`n", "`r`n") + "`r`n"
    $tmpPath = Join-Path $parent (".ws-cache-" + [guid]::NewGuid().ToString('N') + '.tmp')
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    try {
        [System.IO.File]::WriteAllText($tmpPath, $crlf, $utf8NoBom)
        [System.IO.File]::Move($tmpPath, $Path, $true)
    } catch {
        if ([System.IO.File]::Exists($tmpPath)) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Sync-MisePathsCache([switch]$DryRun) {
    $miseCmd = Get-Command mise -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $psCacheFile = Join-Path (Join-Path (Join-Path $userHome '.cache') 'powershell') 'mise_paths.ps1'
    $cmdCacheFile = if ($env:LOCALAPPDATA) { Join-Path (Join-Path $env:LOCALAPPDATA 'cmd') 'mise_paths.cmd' } else { '' }

    if ($DryRun) {
        Write-Host "  [DryRun] Would compile direct Mise tool PATH caches to $psCacheFile and $cmdCacheFile" -ForegroundColor DarkCyan
        return
    }

    if ($null -eq $miseCmd) { return }

    try {
        $rawPaths = @(& $miseCmd.Source bin-paths 2>$null)
        $cleanDirs = [System.Collections.Generic.List[string]]::new()
        foreach ($rp in $rawPaths) {
            if (-not $rp -or -not "$rp".Trim()) { continue }
            $norm = "$rp".Trim().Replace('/', '\').TrimEnd('\')
            if ([System.IO.Directory]::Exists($norm) -and -not $cleanDirs.Contains($norm)) {
                $cleanDirs.Add($norm)
            }
        }
        if ($cleanDirs.Count -eq 0) { return }

        $installsRoot = if ($env:LOCALAPPDATA) {
            Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'installs'
        } else {
            Split-Path -Parent (Split-Path -Parent $cleanDirs[0])
        }
        $joined = ($cleanDirs -join ';')
        $hashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($joined.ToLowerInvariant()))
        $stamp = [System.BitConverter]::ToString($hashBytes, 0, 4).Replace('-', '')
        $escInstalls = $installsRoot.Replace("'", "''")
        $escJoined = $joined.Replace("'", "''")

        $psLines = @(
            "`$script:_wsMiseInstallsDir = '$escInstalls'",
            "`$script:_wsMiseStamp = '$stamp'",
            "`$script:_wsMisePathBlock = '$escJoined'",
            'if ([System.IO.Directory]::Exists($script:_wsMiseInstallsDir)) {',
            '    if (-not $env:Path.Contains($script:_wsMisePathBlock, [System.StringComparison]::OrdinalIgnoreCase)) {',
            '        $cleanSegs = foreach ($seg in $env:Path.Split('';'', [System.StringSplitOptions]::RemoveEmptyEntries)) {',
            '            if ($seg.IndexOf(''\mise\installs\'', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and',
            '                $seg.IndexOf(''/mise/installs/'', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {',
            '                $seg',
            '            }',
            '        }',
            '        $restPath = $cleanSegs -join '';''',
            '        $env:Path = if ($restPath) { "$script:_wsMisePathBlock;$restPath" } else { $script:_wsMisePathBlock }',
            '    }',
            '    $env:_WS_MISE_STAMP = $script:_wsMiseStamp',
            '}'
        )
        Write-CacheFileCrlf -Path $psCacheFile -Content ($psLines -join "`r`n")
        . $psCacheFile

        if ($cmdCacheFile) {
            $cmdLines = @(
                "@if not exist `"$installsRoot`" exit /b 0",
                "@if /i `"%_WS_MISE_STAMP%`"==`"$stamp`" exit /b 0",
                "@set `"_WS_MISE_STAMP=$stamp`"",
                "@set `"PATH=$joined;%PATH%`"",
                '@exit /b 0'
            )
            Write-CacheFileCrlf -Path $cmdCacheFile -Content ($cmdLines -join "`r`n")
        }
        Write-Host "==> Mise direct tool PATH caches compiled ($($cleanDirs.Count) directories)" -ForegroundColor Green
    } catch {
        Write-Verbose "Mise PATH cache generation skipped: $_"
    }
}

function Sync-ShellCompiledCaches {
    param(
        [switch]$SkipPosh,
        [switch]$SkipCompletions,
        [switch]$DryRun
    )
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $psCacheDir = Join-Path (Join-Path $userHome '.cache') 'powershell'
    $ompInit = Join-Path $psCacheDir 'omp_init.ps1'
    $zoxideInit = Join-Path $psCacheDir 'zoxide_init.ps1'
    $ghComp = Join-Path $psCacheDir 'gh_completion.ps1'
    $compCacheFile = Join-Path $psCacheDir 'completions_cache.ps1'
    $compSubDir = Join-Path $psCacheDir 'completions'

    if (-not $SkipPosh) {
        $ompTheme = Join-Path (Join-Path $userHome '.poshthemes') 'p10k_single_line.omp.json'
        $ompCmd = Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $ompCmd) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would compile Oh My Posh prompt hook to $ompInit" -ForegroundColor DarkCyan
            } elseif (Test-Path -LiteralPath $ompTheme -PathType Leaf) {
                $ompOut = (& $ompCmd.Source init pwsh --config $ompTheme --print 2>$null) -join "`r`n"
                if ($LASTEXITCODE -eq 0 -and $ompOut.Trim()) {
                    Write-CacheFileCrlf -Path $ompInit -Content $ompOut
                    Write-Host "==> Oh My Posh prompt cache compiled at $ompInit" -ForegroundColor Green
                }
            }
        }

        $zoxideCmd = Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $zoxideCmd) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would compile zoxide init cache to $zoxideInit" -ForegroundColor DarkCyan
            } else {
                $zoOut = (& $zoxideCmd.Source init powershell 2>$null) -join "`r`n"
                if ($LASTEXITCODE -eq 0 -and $zoOut.Trim()) {
                    Write-CacheFileCrlf -Path $zoxideInit -Content $zoOut
                    Write-Host "==> Zoxide shell cache compiled at $zoxideInit" -ForegroundColor Green
                }
            }
        }
    }

    if (-not $SkipCompletions) {
        if ($DryRun) {
            Write-Host "  [DryRun] Would compile gh_completion.ps1 and completions_cache.ps1 in $psCacheDir" -ForegroundColor DarkCyan
            return
        }

        $prevMiseAuto = $env:MISE_NOT_FOUND_AUTO_INSTALL
        $prevBatTheme = $env:BAT_THEME
        $env:MISE_NOT_FOUND_AUTO_INSTALL = 'false'
        try {
            $ghCmd = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $ghCmd) {
                $ghOut = (& $ghCmd.Source completion -s powershell 2>$null) -join "`r`n"
                if ($LASTEXITCODE -eq 0 -and $ghOut.Trim()) {
                    Write-CacheFileCrlf -Path $ghComp -Content $ghOut
                }
            }

            $toolSpecs = @(
                @{ Exe = 'bat';         Cmd = 'bat';         Args = @('--completion', 'ps1') },
                @{ Exe = 'delta';       Cmd = 'delta';       Args = @('--generate-completion', 'powershell'); ClearBatTheme = $true },
                @{ Exe = 'elan';        Cmd = 'elan';        Args = @('completions', 'powershell') },
                @{ Exe = 'fd';          Cmd = 'fd';          Args = @('--gen-completions', 'powershell') },
                @{ Exe = 'glow';        Cmd = 'glow';        Args = @('completion', 'powershell') },
                @{ Exe = 'mise';        Cmd = 'mise';        Args = @('completion', 'powershell') },
                @{ Exe = 'rg';          Cmd = 'rg';          Args = @('--generate', 'complete-powershell') },
                @{ Exe = 'rustup';      Cmd = 'rustup';      Args = @('completions', 'powershell') },
                @{ Exe = 'tree-sitter'; Cmd = 'tree-sitter'; Args = @('complete', '--shell', 'power-shell') },
                @{ Exe = 'yq';          Cmd = 'yq';          Args = @('shell-completion', 'powershell') },
                @{ Exe = 'zellij';      Cmd = 'zellij';      Args = @('setup', '--generate-completion', 'power-shell'); FallbackArgs = @('setup', '--generate-completion', 'powershell') }
            )

            $loaderLines = [System.Collections.Generic.List[string]]::new()
            $loaderLines.Add('# Pre-compiled lazy CLI tab-completion stubs (keeps warm module import <10ms)')
            $loaderLines.Add('$script:_wsCompSubDir = Join-Path $PSScriptRoot ''completions''')

            $generatedCount = 0
            foreach ($spec in $toolSpecs) {
                $app = Get-Command $spec.Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $app -and $spec.Exe -eq 'elan') {
                    $elanHome = if ($env:ELAN_HOME) { $env:ELAN_HOME } else { Join-Path $userHome '.local\share\elan' }
                    $elanCand = Join-Path (Join-Path $elanHome 'bin') 'elan.exe'
                    if ([System.IO.File]::Exists($elanCand)) {
                        $app = @{ Source = $elanCand }
                    }
                }
                if ($null -eq $app) { continue }

                if ($spec.ClearBatTheme) { $env:BAT_THEME = '' }
                $rawComp = ''
                try {
                    $rawComp = (& $app.Source @($spec.Args) 2>$null) -join "`r`n"
                    if (($LASTEXITCODE -ne 0 -or -not $rawComp.Trim()) -and $spec.FallbackArgs) {
                        $rawComp = (& $app.Source @($spec.FallbackArgs) 2>$null) -join "`r`n"
                    }
                } catch {
                    $rawComp = ''
                } finally {
                    if ($spec.ClearBatTheme) { $env:BAT_THEME = $prevBatTheme }
                }

                if ($LASTEXITCODE -eq 0 -and $rawComp -and $rawComp.Trim()) {
                    $perToolPath = Join-Path $compSubDir "$($spec.Cmd).ps1"
                    Write-CacheFileCrlf -Path $perToolPath -Content $rawComp
                    $cmdLit = $spec.Cmd.Replace("'", "''")
                    $loaderLines.Add("Register-ArgumentCompleter -Native -CommandName '$cmdLit' -ScriptBlock {")
                    $loaderLines.Add('    param($wordToComplete, $commandAst, $cursorPosition)')
                    $loaderLines.Add("    `$f = Join-Path `$script:_wsCompSubDir '$cmdLit.ps1'")
                    $loaderLines.Add('    if ([System.IO.File]::Exists($f)) {')
                    $loaderLines.Add('        . $f')
                    $loaderLines.Add('        return @(TabExpansion2 -inputScript $commandAst.Extent.Text -cursorColumn ($cursorPosition - $commandAst.Extent.StartOffset)).CompletionMatches')
                    $loaderLines.Add('    }')
                    $loaderLines.Add('}')
                    $generatedCount++
                }
            }

            if ($generatedCount -gt 0) {
                Write-CacheFileCrlf -Path $compCacheFile -Content ($loaderLines -join "`r`n")
                Write-Host "==> CLI completions cache compiled ($generatedCount tools) at $compCacheFile" -ForegroundColor Green
            }
        } finally {
            $env:MISE_NOT_FOUND_AUTO_INSTALL = $prevMiseAuto
            $env:BAT_THEME = $prevBatTheme
        }
    }
}
