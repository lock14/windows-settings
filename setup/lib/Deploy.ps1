# =============================================================
# setup/lib/Deploy.ps1 - Idempotent File, KDL & WASM Deployment
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Shared deployment helper naming contract')]
param()

function Get-TimestampedBackupPath([string]$TargetPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $baseBackup = "$TargetPath.bak_$timestamp"
    $candidate = $baseBackup
    $idx = 1
    while ([System.IO.File]::Exists($candidate) -or [System.IO.Directory]::Exists($candidate)) {
        $candidate = "${baseBackup}_$idx"
        $idx++
    }
    return $candidate
}

function Write-FileAtomicUtf8NoBom([string]$DestinationPath, [string]$Content) {
    $parentDir = Split-Path -Parent $DestinationPath
    if ($parentDir -and -not [System.IO.Directory]::Exists($parentDir)) {
        New-Item -ItemType Directory -Force -Path $parentDir | Out-Null
    }
    $tmpPath = Join-Path $parentDir (".ws-deploy-" + [guid]::NewGuid().ToString('N') + '.tmp')
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    try {
        [System.IO.File]::WriteAllText($tmpPath, $Content, $utf8NoBom)
        [System.IO.File]::Move($tmpPath, $DestinationPath, $true)
    } catch {
        if ([System.IO.File]::Exists($tmpPath)) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Deploy-ConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [string[]]$AltDestinations = @(),
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { return }
    $sourceBytes = [System.IO.File]::ReadAllBytes($SourcePath)

    $allDests = @($DestinationPath) + $AltDestinations
    foreach ($dest in $allDests) {
        if (-not $dest) { continue }
        $destDir = Split-Path -Parent $dest
        if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            }
        }

        if (Test-Path -LiteralPath $dest -PathType Leaf) {
            $existingBytes = [System.IO.File]::ReadAllBytes($dest)
            $isSame = ($existingBytes.Length -eq $sourceBytes.Length)
            if ($isSame) {
                for ($i = 0; $i -lt $sourceBytes.Length; $i++) {
                    if ($existingBytes[$i] -ne $sourceBytes[$i]) {
                        $isSame = $false
                        break
                    }
                }
            }

            if (-not $isSame) {
                $backup = Get-TimestampedBackupPath $dest
                if ($DryRun) {
                    Write-Host "  [DryRun] Would backup $dest to $backup" -ForegroundColor DarkCyan
                    Write-Host "  [DryRun] Would update $Name at $dest" -ForegroundColor DarkCyan
                } else {
                    Write-Host "Backing up existing config to $backup..." -ForegroundColor Yellow
                    Copy-Item -LiteralPath $dest -Destination $backup -Force
                    Copy-Item -LiteralPath $SourcePath -Destination $dest -Force
                    Write-Host "==> $Name updated at $dest" -ForegroundColor Green
                }
            } else {
                Write-Host "==> $Name at $dest is already up to date." -ForegroundColor Green
            }
        } else {
            if ($DryRun) {
                Write-Host "  [DryRun] Would deploy $Name to $dest" -ForegroundColor DarkCyan
            } else {
                Copy-Item -LiteralPath $SourcePath -Destination $dest -Force
                Write-Host "==> $Name deployed to $dest" -ForegroundColor Green
            }
        }
    }
}

function Deploy-DirectoryFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [string]$Filter,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDir,
        [switch]$ForceLf,
        [switch]$DryRun
    )

    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) { return }
    $files = @(Get-ChildItem -LiteralPath $SourceDir -Filter $Filter -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($files.Count -eq 0) { return }

    if ($DryRun) {
        Write-Host "  [DryRun] Would deploy $($files.Count) $Name to $DestinationDir" -ForegroundColor DarkCyan
        return
    }

    if (-not (Test-Path -LiteralPath $DestinationDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    }

    foreach ($file in $files) {
        $destFile = Join-Path $DestinationDir $file.Name
        if ($ForceLf) {
            $lfText = ([System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n")
            if (-not $lfText.EndsWith("`n")) { $lfText += "`n" }
            $existingText = if ([System.IO.File]::Exists($destFile)) {
                [System.IO.File]::ReadAllText($destFile, [System.Text.Encoding]::UTF8)
            } else {
                $null
            }
            if ($null -eq $existingText -or $existingText -cne $lfText) {
                Write-FileAtomicUtf8NoBom -DestinationPath $destFile -Content $lfText
            }
        } else {
            Copy-Item -LiteralPath $file.FullName -Destination $destFile -Force
        }
    }
    Write-Host "==> $($files.Count) $Name deployed to $DestinationDir" -ForegroundColor Green
}

function Get-ZellijPluginDir {
    if ($env:APPDATA) {
        return (Join-Path (Join-Path (Join-Path $env:APPDATA 'Zellij') 'data') 'plugins')
    }
    return (Join-Path (Join-Path (Join-Path (Join-Path $HOME '.local') 'share') 'zellij') 'plugins')
}

function Get-ZellijBarSourceStamp([string]$CrateDir) {
    if (-not (Test-Path -LiteralPath $CrateDir -PathType Container)) { return '' }
    $sb = [System.Text.StringBuilder]::new()
    $zellijCmd = Get-Command zellij -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($zellijCmd) {
        try {
            $zVer = (& $zellijCmd.Source --version 2>$null | Out-String).Trim()
            [void]$sb.AppendLine("zellij:$zVer")
        } catch {
            [void]$sb.AppendLine('zellij:unknown')
        }
    }
    $relFiles = [System.Collections.Generic.List[string]]::new()
    foreach ($fixed in @('Cargo.toml', 'Cargo.lock', (Join-Path '.cargo' 'config.toml'))) {
        $fp = Join-Path $CrateDir $fixed
        if (Test-Path -LiteralPath $fp -PathType Leaf) { $relFiles.Add($fixed) }
    }
    $srcDir = Join-Path $CrateDir 'src'
    if (Test-Path -LiteralPath $srcDir -PathType Container) {
        foreach ($rs in (Get-ChildItem -LiteralPath $srcDir -Filter '*.rs' -File | Sort-Object Name)) {
            $relFiles.Add((Join-Path 'src' $rs.Name))
        }
    }
    foreach ($rel in $relFiles) {
        $full = Join-Path $CrateDir $rel
        $raw = (Get-Content -LiteralPath $full -Raw).Replace("`r`n", "`n")
        $normRel = $rel.Replace([System.IO.Path]::DirectorySeparatorChar, [char]'/')
        [void]$sb.AppendLine("---$normRel---")
        [void]$sb.AppendLine($raw)
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
}

function Resolve-RustWasmToolchain {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $cargoBin = Join-Path (Join-Path $userHome '.cargo') 'bin'
    $cargoExe = Get-Command cargo.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cargoExe -and (Test-Path -LiteralPath (Join-Path $cargoBin 'cargo.exe'))) {
        $cargoExe = Get-Item -LiteralPath (Join-Path $cargoBin 'cargo.exe')
    }
    if (-not $cargoExe -and $env:LOCALAPPDATA) {
        $miseRust = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'installs') 'rust'
        if (Test-Path -LiteralPath $miseRust -PathType Container) {
            $foundCargo = Get-ChildItem -LiteralPath $miseRust -Filter 'cargo.exe' -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1
            if ($foundCargo) { $cargoExe = $foundCargo }
        }
    }
    if (-not $cargoExe) { return $null }
    $cargoPath = if ($cargoExe.PSObject.Properties['Source']) { $cargoExe.Source } else { $cargoExe.FullName }

    $rustupExe = Get-Command rustup.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $rustupExe -and (Test-Path -LiteralPath (Join-Path $cargoBin 'rustup.exe'))) {
        $rustupExe = Get-Item -LiteralPath (Join-Path $cargoBin 'rustup.exe')
    }
    $rustupPath = if ($rustupExe) {
        if ($rustupExe.PSObject.Properties['Source']) { $rustupExe.Source } else { $rustupExe.FullName }
    } else {
        ''
    }

    $hasMsvc = $false
    $pf86 = ${env:ProgramFiles(x86)}
    if ($pf86) {
        $vswhere = Join-Path (Join-Path (Join-Path $pf86 'Microsoft Visual Studio') 'Installer') 'vswhere.exe'
        if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
            try {
                $vcInst = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Out-String).Trim()
                if ($vcInst) { $hasMsvc = $true }
            } catch {
                $hasMsvc = $false
            }
        }
    }
    if ($hasMsvc) {
        return @{ Cargo = $cargoPath; Rustup = $rustupPath; Toolchain = ''; ExtraPath = '' }
    }

    $gccCmd = Get-Command gcc.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $gccDir = if ($gccCmd) { Split-Path -Parent $gccCmd.Source } else { '' }
    if (-not $gccDir -and $env:LOCALAPPDATA) {
        $wgPkgs = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'WinGet') 'Packages'
        if (Test-Path -LiteralPath $wgPkgs -PathType Container) {
            $foundGcc = Get-ChildItem -LiteralPath $wgPkgs -Filter 'gcc.exe' -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'WinLibs' } | Select-Object -First 1
            if ($foundGcc) { $gccDir = Split-Path -Parent $foundGcc.FullName }
        }
    }
    if ($gccDir -and $rustupPath) {
        return @{ Cargo = $cargoPath; Rustup = $rustupPath; Toolchain = 'stable-x86_64-pc-windows-gnu'; ExtraPath = $gccDir }
    }
    return $null
}

function Sync-ZellijBarPlugin([string]$RepoRoot, [switch]$DryRun) {
    $crateDir = Join-Path (Join-Path $RepoRoot 'plugin') 'ws-bar'
    $manifestPath = Join-Path $crateDir 'Cargo.toml'
    $wasmDest = Join-Path (Get-ZellijPluginDir) 'windows-settings-bar.wasm'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return (Test-Path -LiteralPath $wasmDest -PathType Leaf)
    }

    if ($DryRun -and $env:WS_TEST_MODE -eq '1') {
        Write-Host "  [DryRun] Would sync windows-settings-bar.wasm to $wasmDest" -ForegroundColor DarkCyan
        return $true
    }

    $stampDir = Join-Path (Join-Path $HOME '.cache') 'windows-settings'
    $stampFile = Join-Path $stampDir 'ws-bar.sha256'
    $desiredStamp = Get-ZellijBarSourceStamp $crateDir

    if ((Test-Path -LiteralPath $wasmDest -PathType Leaf) -and (Test-Path -LiteralPath $stampFile -PathType Leaf)) {
        $currentStamp = (Get-Content -LiteralPath $stampFile -Raw).Trim()
        if ($currentStamp -eq $desiredStamp) {
            Write-Host "==> Zellij top-bar plugin at $wasmDest is already up to date." -ForegroundColor Green
            return $true
        }
    }

    $tc = Resolve-RustWasmToolchain
    if ($null -eq $tc) {
        if (Test-Path -LiteralPath $wasmDest -PathType Leaf) {
            Write-Host "==> Retaining existing Zellij top-bar plugin at $wasmDest." -ForegroundColor Green
            return $true
        }
        Write-Host '==> Rust or C linker toolchain not yet available; using built-in Zellij compact-bar fallback.' -ForegroundColor DarkYellow
        return $false
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would build windows-settings-bar.wasm (wasm32-wasip1) and deploy to $wasmDest" -ForegroundColor DarkCyan
        return $true
    }

    $savedPath = $env:Path
    try {
        $cargoDir = Split-Path -Parent $tc.Cargo
        if ($tc.ExtraPath -and -not $env:Path.Contains($tc.ExtraPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $env:Path = "$($tc.ExtraPath);$env:Path"
        }
        if ($cargoDir -and -not $env:Path.Contains($cargoDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $env:Path = "$cargoDir;$env:Path"
        }

        if ($tc.Rustup) {
            if ($tc.Toolchain) {
                $installedTcs = (& $tc.Rustup toolchain list 2>$null | Out-String)
                if ($installedTcs -notmatch [regex]::Escape($tc.Toolchain)) {
                    Write-Host "==> Installing Rust host toolchain $($tc.Toolchain) + wasm32-wasip1 target..." -ForegroundColor Cyan
                    & $tc.Rustup toolchain install $tc.Toolchain --target wasm32-wasip1 --profile minimal --no-self-update *> $null
                } else {
                    $installedTargets = (& $tc.Rustup target list --installed --toolchain $tc.Toolchain 2>$null | Out-String)
                    if ($installedTargets -notmatch 'wasm32-wasip1') {
                        & $tc.Rustup target add wasm32-wasip1 --toolchain $tc.Toolchain *> $null
                    }
                }
            } else {
                $installedTargets = (& $tc.Rustup target list --installed 2>$null | Out-String)
                if ($installedTargets -notmatch 'wasm32-wasip1') {
                    & $tc.Rustup target add wasm32-wasip1 *> $null
                }
            }
        }

        Write-Host '==> Compiling Zellij WASM top-bar plugin (windows-settings-bar.wasm)...' -ForegroundColor Cyan
        $cargoArgs = [System.Collections.Generic.List[string]]::new()
        if ($tc.Toolchain) { $cargoArgs.Add("+$($tc.Toolchain)") }
        $cargoArgs.AddRange([string[]]@('build', '--release', '--manifest-path', $manifestPath, '--target', 'wasm32-wasip1', '--quiet'))
        & $tc.Cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'Failed to compile windows-settings-bar.wasm; falling back to built-in Zellij compact-bar.'
            return (Test-Path -LiteralPath $wasmDest -PathType Leaf)
        }

        $builtWasm = Join-Path (Join-Path (Join-Path (Join-Path $crateDir 'target') 'wasm32-wasip1') 'release') 'windows-settings-bar.wasm'
        if (-not (Test-Path -LiteralPath $builtWasm -PathType Leaf)) {
            Write-Warning 'Compiled windows-settings-bar.wasm artifact not found; falling back to built-in Zellij compact-bar.'
            return (Test-Path -LiteralPath $wasmDest -PathType Leaf)
        }

        $pluginDir = Split-Path -Parent $wasmDest
        if (-not (Test-Path -LiteralPath $pluginDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
        }
        Copy-Item -LiteralPath $builtWasm -Destination $wasmDest -Force
        Write-FileAtomicUtf8NoBom -DestinationPath $stampFile -Content "$desiredStamp`n"
        Write-Host "==> Zellij top-bar plugin deployed to $wasmDest" -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "Skipping WASM bar build ($_): falling back to built-in Zellij compact-bar."
        return (Test-Path -LiteralPath $wasmDest -PathType Leaf)
    } finally {
        $env:Path = $savedPath
    }
}

function Sync-ZellijPluginPermission([string]$PermissionsPath = '', [switch]$Remove, [switch]$DryRun) {
    $permFile = if ($PermissionsPath) {
        $PermissionsPath
    } elseif ($env:LOCALAPPDATA) {
        Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Zellij') 'cache') 'permissions.kdl'
    } else {
        Join-Path (Join-Path (Join-Path $HOME '.cache') 'zellij') 'permissions.kdl'
    }

    $desiredPerms = @(
        'ChangeApplicationState',
        'ReadApplicationState',
        'ReadCliPipes',
        'ReadSessionEnvironmentVariables',
        'Reconfigure',
        'RunActionsAsUser',
        'RunCommands'
    )
    $desiredBlock = (@(
        'windows-settings-bar {'
        '    ChangeApplicationState'
        '    ReadApplicationState'
        '    ReadCliPipes'
        '    ReadSessionEnvironmentVariables'
        '    Reconfigure'
        '    RunActionsAsUser'
        '    RunCommands'
        '}'
    ) -join "`n")
    $blockPattern = '(?m)^\s*"?windows-settings-bar"?\s*\{[^}]*\}\s*\n?'

    if ($Remove) {
        if (-not (Test-Path -LiteralPath $permFile -PathType Leaf)) { return }
        $raw = (Get-Content -LiteralPath $permFile -Raw).Replace("`r`n", "`n")
        if ($raw -notmatch $blockPattern) { return }
        $updated = [regex]::Replace($raw, $blockPattern, '').Trim()
        if ($DryRun) {
            Write-Host "  [DryRun] Would remove windows-settings-bar permissions from $permFile" -ForegroundColor DarkCyan
            return
        }
        $backup = Get-TimestampedBackupPath $permFile
        Copy-Item -LiteralPath $permFile -Destination $backup -Force
        if (-not $updated) {
            Remove-Item -LiteralPath $permFile -Force -ErrorAction SilentlyContinue
        } else {
            Write-FileAtomicUtf8NoBom -DestinationPath $permFile -Content "$updated`n"
        }
        Write-Host "  Removed windows-settings-bar permissions from $permFile" -ForegroundColor Green
        return
    }

    $exists = Test-Path -LiteralPath $permFile -PathType Leaf
    $raw = if ($exists) { (Get-Content -LiteralPath $permFile -Raw).Replace("`r`n", "`n") } else { '' }
    if ($exists -and $raw -match '(?m)^\s*"?windows-settings-bar"?\s*\{(?<body>[^}]*)\}') {
        $body = $Matches['body']
        $allPresent = $true
        foreach ($perm in $desiredPerms) {
            if ($body -notmatch "\b$([regex]::Escape($perm))\b") {
                $allPresent = $false
                break
            }
        }
        if ($allPresent) {
            Write-Host "==> Zellij plugin permissions at $permFile are already up to date." -ForegroundColor Green
            return
        }
    }

    $stripped = [regex]::Replace($raw, $blockPattern, '').Trim()
    $finalLf = if ($stripped) { "$stripped`n$desiredBlock`n" } else { "$desiredBlock`n" }

    if ($DryRun) {
        if ($exists) {
            $backup = Get-TimestampedBackupPath $permFile
            Write-Host "  [DryRun] Would backup $permFile to $backup" -ForegroundColor DarkCyan
        }
        Write-Host "  [DryRun] Would pre-seed windows-settings-bar permissions in $permFile" -ForegroundColor DarkCyan
        return
    }

    if ($exists) {
        $backup = Get-TimestampedBackupPath $permFile
        Copy-Item -LiteralPath $permFile -Destination $backup -Force
    }
    Write-FileAtomicUtf8NoBom -DestinationPath $permFile -Content $finalLf
    Write-Host "==> Zellij plugin permissions pre-seeded at $permFile" -ForegroundColor Green
}

function ConvertTo-NormalizedZellijConfig([string]$Content) {
    if (-not $Content) { return '' }
    $norm = $Content.Replace("`r`n", "`n")
    $norm = [regex]::Replace($norm, '(?s)// BEGIN WINDOWS-SETTINGS TRAY COLORS.*?// END WINDOWS-SETTINGS TRAY COLORS', '// __WS_TRAY__')
    $norm = [regex]::Replace($norm, '(?s)// BEGIN WINDOWS-SETTINGS TERMINAL THEME.*?// END WINDOWS-SETTINGS TERMINAL THEME', '// __WS_TERM__')
    return $norm.Trim()
}

function Deploy-ZellijConfig([string]$SourcePath, [string]$DestinationPath, [bool]$UseWasmBar = $false, [switch]$DryRun) {
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { return }
    $srcLf = (Get-Content -LiteralPath $SourcePath -Raw).Replace("`r`n", "`n")
    $barBlock = if ($UseWasmBar) {
        @(
            '    // BEGIN WINDOWS-SETTINGS BAR PLUGIN'
            '    compact-bar location="file:windows-settings-bar"'
            '    // END WINDOWS-SETTINGS BAR PLUGIN'
        ) -join "`n"
    } else {
        @(
            '    // BEGIN WINDOWS-SETTINGS BAR PLUGIN'
            '    compact-bar location="zellij:bars" {'
            '        role "compact-bar"'
            '    }'
            '    // END WINDOWS-SETTINGS BAR PLUGIN'
        ) -join "`n"
    }
    $srcLf = [regex]::Replace(
        $srcLf,
        '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS BAR PLUGIN.*?// END WINDOWS-SETTINGS BAR PLUGIN',
        $barBlock
    )
    $linkPluginBlock = if ($UseWasmBar) {
        @(
            'load_plugins {'
            '    // BEGIN WINDOWS-SETTINGS LINK PLUGIN'
            '    // Alt+Click regex link routing is managed directly by windows-settings-bar'
            '    // END WINDOWS-SETTINGS LINK PLUGIN'
            '}'
        ) -join "`n"
    } else {
        @(
            'load_plugins {'
            '    // BEGIN WINDOWS-SETTINGS LINK PLUGIN'
            '    "zellij:bars" {'
            '        role "link"'
            '    }'
            '    // END WINDOWS-SETTINGS LINK PLUGIN'
            '}'
        ) -join "`n"
    }
    $srcLf = [regex]::Replace(
        $srcLf,
        '(?s)load_plugins\s*\{\s*// BEGIN WINDOWS-SETTINGS LINK PLUGIN.*?// END WINDOWS-SETTINGS LINK PLUGIN\s*\}',
        $linkPluginBlock
    )
    if ($UseWasmBar) {
        $wasmMenuRoles = @(
            '        // BEGIN WINDOWS-SETTINGS BAR MENU ROLES'
            '        item "Focus AI agent" { MessagePlugin { name "ws-ide-role"; payload "focus:ai"; }; }'
            '        item "Focus Editor" { MessagePlugin { name "ws-ide-role"; payload "focus:editor"; }; }'
            '        item "Focus Shell" { MessagePlugin { name "ws-ide-role"; payload "focus:shell"; }; }'
            '        // END WINDOWS-SETTINGS BAR MENU ROLES'
        ) -join "`n"
        $wasmTabRoles = @(
            '        // BEGIN WINDOWS-SETTINGS TAB MENU ROLES'
            '        item "Focus AI agent" { MessagePlugin { name "ws-ide-role"; payload "focus:ai"; }; }'
            '        item "Focus Editor" { MessagePlugin { name "ws-ide-role"; payload "focus:editor"; }; }'
            '        item "Focus Shell" { MessagePlugin { name "ws-ide-role"; payload "focus:shell"; }; }'
            '        // END WINDOWS-SETTINGS TAB MENU ROLES'
        ) -join "`n"
        $wasmRoleBinds = @(
            '        // BEGIN WINDOWS-SETTINGS ROLE BINDS'
            '        bind "Alt a" { MessagePlugin { name "ws-ide-role"; payload "focus:ai"; }; }'
            '        bind "Alt e" { MessagePlugin { name "ws-ide-role"; payload "focus:editor"; }; }'
            '        bind "Alt t" { MessagePlugin { name "ws-ide-role"; payload "focus:shell"; }; }'
            '        bind "Alt E" "Alt Shift e" { MessagePlugin { name "ws-ide-role"; payload "toggle:editor"; }; }'
            '        bind "Alt T" "Alt Shift t" { MessagePlugin { name "ws-ide-role"; payload "toggle:shell"; }; }'
            '        // END WINDOWS-SETTINGS ROLE BINDS'
        ) -join "`n"
        $srcLf = [regex]::Replace($srcLf, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS BAR MENU ROLES.*?// END WINDOWS-SETTINGS BAR MENU ROLES', $wasmMenuRoles)
        $srcLf = [regex]::Replace($srcLf, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS TAB MENU ROLES.*?// END WINDOWS-SETTINGS TAB MENU ROLES', $wasmTabRoles)
        $srcLf = [regex]::Replace($srcLf, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS ROLE BINDS.*?// END WINDOWS-SETTINGS ROLE BINDS', $wasmRoleBinds)
    } else {
        $fallbackMenuRoles = @(
            '        // BEGIN WINDOWS-SETTINGS BAR MENU ROLES'
            '        item "Focus AI agent" { MoveFocus "Up"; MoveFocus "Left"; }'
            '        item "Focus Editor" { MoveFocus "Up"; MoveFocus "Right"; }'
            '        item "Focus Shell" { MoveFocus "Down"; }'
            '        // END WINDOWS-SETTINGS BAR MENU ROLES'
        ) -join "`n"
        $fallbackTabRoles = @(
            '        // BEGIN WINDOWS-SETTINGS TAB MENU ROLES'
            '        item "Focus AI agent" { MoveFocus "Up"; MoveFocus "Left"; }'
            '        item "Focus Editor" { MoveFocus "Up"; MoveFocus "Right"; }'
            '        item "Focus Shell" { MoveFocus "Down"; }'
            '        // END WINDOWS-SETTINGS TAB MENU ROLES'
        ) -join "`n"
        $fallbackRoleBinds = @(
            '        // BEGIN WINDOWS-SETTINGS ROLE BINDS'
            '        bind "Alt a" { MoveFocus "Up"; MoveFocus "Left"; }'
            '        bind "Alt e" { MoveFocus "Up"; MoveFocus "Right"; }'
            '        bind "Alt t" { MoveFocus "Down"; }'
            '        bind "Alt E" "Alt Shift e" {'
            '            Run "cmd.exe" "/d" "/c" "ide.cmd" "_internal" "toggle" "editor" {'
            '                background true'
            '            }'
            '        }'
            '        bind "Alt T" "Alt Shift t" {'
            '            Run "cmd.exe" "/d" "/c" "ide.cmd" "_internal" "toggle" "shell" {'
            '                background true'
            '            }'
            '        }'
            '        // END WINDOWS-SETTINGS ROLE BINDS'
        ) -join "`n"
        $srcLf = [regex]::Replace($srcLf, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS BAR MENU ROLES.*?// END WINDOWS-SETTINGS BAR MENU ROLES', $fallbackMenuRoles)
        $srcLf = [regex]::Replace($srcLf, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS TAB MENU ROLES.*?// END WINDOWS-SETTINGS TAB MENU ROLES', $fallbackTabRoles)
        $srcLf = [regex]::Replace($srcLf, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS ROLE BINDS.*?// END WINDOWS-SETTINGS ROLE BINDS', $fallbackRoleBinds)
    }

    if (-not $srcLf.EndsWith("`n")) { $srcLf += "`n" }
    $destDir = Split-Path -Parent $DestinationPath
    if ($destDir -and -not (Test-Path -LiteralPath $destDir -PathType Container)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
    }
    if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
        $existingRaw = Get-Content -LiteralPath $DestinationPath -Raw
        $isSame = ((ConvertTo-NormalizedZellijConfig $existingRaw) -eq (ConvertTo-NormalizedZellijConfig $srcLf))
        if (-not $isSame) {
            $backup = Get-TimestampedBackupPath $DestinationPath
            if ($DryRun) {
                Write-Host "  [DryRun] Would backup $DestinationPath to $backup" -ForegroundColor DarkCyan
                Write-Host "  [DryRun] Would update Zellij configuration at $DestinationPath" -ForegroundColor DarkCyan
            } else {
                Write-Host "Backing up existing Zellij config to $backup..." -ForegroundColor Yellow
                Copy-Item -LiteralPath $DestinationPath -Destination $backup -Force
                Write-FileAtomicUtf8NoBom -DestinationPath $DestinationPath -Content $srcLf
                Write-Host "==> Zellij configuration updated at $DestinationPath" -ForegroundColor Green
            }
        } else {
            Write-Host "==> Zellij configuration at $DestinationPath is already up to date." -ForegroundColor Green
        }
    } else {
        if ($DryRun) {
            Write-Host "  [DryRun] Would deploy Zellij configuration to $DestinationPath" -ForegroundColor DarkCyan
        } else {
            Write-FileAtomicUtf8NoBom -DestinationPath $DestinationPath -Content $srcLf
            Write-Host "==> Zellij configuration deployed to $DestinationPath" -ForegroundColor Green
        }
    }
}
