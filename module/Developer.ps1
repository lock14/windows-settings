# =============================================================
# Developer Tool Shortcuts, RPC-Aware Editor & IDE Workspace
# =============================================================

function go-testall  { go test ./... @args }
function go-buildall { go build ./... @args }

function go-lint {
    $hasLocalConfig = [bool](@('.golangci.yml', '.golangci.yaml', '.golangci.toml') | Where-Object { Test-Path $_ } | Select-Object -First 1)
    if ($hasLocalConfig) {
        golangci-lint run @args
    } else {
        $cacheDir = if ($env:XDG_CACHE_HOME) { "$env:XDG_CACHE_HOME" } else { "$HOME\.cache" }
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
        $cfg = Join-Path $cacheDir 'golangci.yml'
        if (-not (Test-Path $cfg) -or (Get-Item $cfg).Length -eq 0) {
            try {
                Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/abcxyz/pkg/main/.golangci.yml' -OutFile $cfg -UseBasicParsing -ErrorAction Stop
            } catch {
                if ((Test-Path $cfg) -and (Get-Item $cfg).Length -eq 0) {
                    Remove-Item -Force $cfg -ErrorAction SilentlyContinue
                }
                Write-Warning "Could not download default golangci.yml: $_"
            }
        }
        if ((Test-Path $cfg) -and (Get-Item $cfg).Length -gt 0) {
            golangci-lint run -c $cfg @args
        } else {
            golangci-lint run @args
        }
    }
}

function yaml-lint {
    $hasLocalConfig = [bool](@('.yamllint', '.yamllint.yml', '.yamllint.yaml') | Where-Object { Test-Path $_ } | Select-Object -First 1)
    $homeConfig = @("$HOME\.yamllint.yml", "$HOME\.yamllint") | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($hasLocalConfig) {
        yamllint @args
    } elseif ($homeConfig) {
        yamllint -c $homeConfig @args
    } else {
        yamllint @args
    }
}

# Editor & CLI Aliases
Set-Alias -Name tf -Value terraform -ErrorAction SilentlyContinue
if (Test-Path 'Alias:v') {
    Remove-Item -Path 'Alias:v' -Force -ErrorAction SilentlyContinue
}
$hasNvimFast = if (Get-Command Test-WsExeOnPath -CommandType Function -ErrorAction SilentlyContinue) {
    Test-WsExeOnPath 'nvim.exe'
} else {
    [bool](Get-Command nvim -ErrorAction SilentlyContinue)
}
if ($hasNvimFast) {
    Set-Alias -Name vi -Value nvim -ErrorAction SilentlyContinue
    Set-Alias -Name vim -Value nvim -ErrorAction SilentlyContinue
} else {
    $vimApp = Get-Command vim.exe, vim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $vimTarget = if ($vimApp) { $vimApp.Source } else { 'nvim' }
    Set-Alias -Name vim -Value $vimTarget -ErrorAction SilentlyContinue
    Set-Alias -Name vi -Value vim -ErrorAction SilentlyContinue
}

# RPC-Aware Smart Editor Opener (`v [+line|+cmd] [-c cmd] [--] <file>...`)
function v {
    $nvimApp = Get-Command nvim.exe, nvim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($nvimApp -and $args.Count -ge 1 -and ($env:NVIM_IDE_SOCKET -or $env:IDE_SESSION -or $env:ZELLIJ_SESSION_NAME)) {
        $afterDoubleDash = $false
        $canRouteRpc = $true
        $globalLine = 0
        $exCmds = [System.Collections.Generic.List[string]]::new()
        $fileTargets = [System.Collections.Generic.List[hashtable]]::new()
        $cwdPath = (Get-Location).ProviderPath

        for ($i = 0; $i -lt $args.Count; $i++) {
            $s = "$($args[$i])"
            if (-not $afterDoubleDash) {
                if ($s -eq '--') {
                    $afterDoubleDash = $true
                    continue
                }
                if ($s -eq '-c') {
                    if ($i + 1 -ge $args.Count) {
                        $canRouteRpc = $false
                        break
                    }
                    $exCmds.Add("$($args[++$i])")
                    continue
                }
                if ($s -match '^\+([0-9]+)$') {
                    $globalLine = [int]$Matches[1]
                    continue
                }
                if ($s -eq '+') {
                    $exCmds.Add('$')
                    continue
                }
                if ($s.StartsWith('+')) {
                    $exCmds.Add($s.Substring(1))
                    continue
                }
                if ($s.StartsWith('-')) {
                    $canRouteRpc = $false
                    break
                }
            }

            $fPath = $s
            $fLine = 0
            if ($s -match '^([A-Za-z]:[^:]+|[^:]+):([0-9]+)(?::[0-9]+)?$' -and $s -notmatch '^[A-Za-z]:[\\/]?$') {
                $candFile = $Matches[1]
                if (-not (Test-Path -LiteralPath $s) -and ((Test-Path -LiteralPath $candFile) -or -not [System.IO.Path]::IsPathRooted($s))) {
                    $fPath = $candFile
                    $fLine = [int]$Matches[2]
                }
            }
            if (-not [System.IO.Path]::IsPathRooted($fPath)) {
                $fPath = [System.IO.Path]::GetFullPath((Join-Path $cwdPath $fPath))
            }
            $fileTargets.Add(@{ path = $fPath; line = $fLine })
        }

        if ($canRouteRpc -and $fileTargets.Count -ge 1) {
            $sess = if ($env:ZELLIJ_SESSION_NAME -and $env:ZELLIJ_SESSION_NAME.Trim()) {
                $env:ZELLIJ_SESSION_NAME.Trim()
            } elseif ($env:IDE_SESSION -and $env:IDE_SESSION.Trim()) {
                $env:IDE_SESSION.Trim()
            } else {
                ''
            }
            $metaObj = $null
            if ($sess) {
                $metaPath = Join-Path $HOME ".cache\windows-settings\ide\$sess.json"
                if ([System.IO.File]::Exists($metaPath)) {
                    try { $metaObj = [System.IO.File]::ReadAllText($metaPath) | ConvertFrom-Json } catch { $metaObj = $null }
                }
            }
            $candPipe = if ($env:NVIM_IDE_SOCKET -and $env:NVIM_IDE_SOCKET.Trim()) {
                $env:NVIM_IDE_SOCKET.Trim()
            } elseif ($metaObj -and $metaObj.pipe) {
                "$($metaObj.pipe)".Trim()
            } elseif ($sess) {
                "\\.\pipe\nvim-ide-$sess"
            } else {
                ''
            }

            $pipeLive = $false
            if ($candPipe -match '^\\\\\.\\pipe\\(.+)$') {
                $pipeLeaf = $Matches[1]
                try {
                    $pipeLive = ([System.IO.Directory]::GetFiles('\\.\pipe\', $pipeLeaf).Count -gt 0)
                } catch {
                    $pipeLive = $false
                }
            }

            if ($pipeLive) {
                $healDir = if ($env:IDE_WORKDIR -and [System.IO.Directory]::Exists($env:IDE_WORKDIR)) {
                    $env:IDE_WORKDIR
                } elseif ($metaObj -and $metaObj.workdir -and [System.IO.Directory]::Exists("$($metaObj.workdir)")) {
                    "$($metaObj.workdir)"
                } elseif ($metaObj -and $metaObj.root -and [System.IO.Directory]::Exists("$($metaObj.root)")) {
                    "$($metaObj.root)"
                } else {
                    $cwdPath
                }
                $syncCwd = [bool](($metaObj -and $metaObj.workdir) -or $env:IDE_WORKDIR)
                $rpcPayload = @{
                    workdir  = $healDir
                    sync_cwd = $syncCwd
                    files    = @($fileTargets)
                    line     = $globalLine
                    cmds     = @($exCmds)
                } | ConvertTo-Json -Compress -Depth 4
                $vimJson = $rpcPayload.Replace("'", "''")
                $luaChunk = '(function(raw) vim.schedule(function() local ok, p = pcall(vim.json.decode, raw); if not ok or type(p) ~= "table" then return end; pcall(function() require("mini.files").close() end); local uv = vim.uv or vim.loop; if type(p.workdir) == "string" and p.workdir ~= "" and uv.fs_stat(p.workdir) then if uv.fs_stat(vim.fn.getcwd()) == nil or p.sync_cwd then pcall(vim.fn.chdir, p.workdir) end end; local gl = tonumber(p.line) or 0; for _, it in ipairs(p.files or {}) do if type(it.path) == "string" and it.path ~= "" then vim.cmd("silent! keepjumps edit " .. vim.fn.fnameescape(it.path)); local fl = tonumber(it.line) or 0; if fl > 0 then pcall(vim.api.nvim_win_set_cursor, 0, { fl, 0 }) end end end; if gl > 0 then pcall(vim.api.nvim_win_set_cursor, 0, { gl, 0 }) end; for _, ex in ipairs(p.cmds or {}) do if type(ex) == "string" and ex ~= "" then pcall(vim.cmd, ex) end end; if gl > 0 or #(p.cmds or {}) > 0 then pcall(vim.cmd, "silent! normal! zz") end end); return "OK" end)(_A)'
                $rpcExpr = "luaeval('$($luaChunk.Replace("'", "''"))', '$vimJson')"
                $rpcOut = (& $nvimApp.Source --headless --server $candPipe --remote-expr $rpcExpr 2>$null) -join "`n"
                if ($LASTEXITCODE -eq 0 -and $rpcOut -match 'OK') {
                    if ($env:ZELLIJ) {
                        $zellijApp = Get-Command zellij.exe, zellij -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                        $wasmBarPath = if ($env:APPDATA) { Join-Path $env:APPDATA 'Zellij\data\plugins\windows-settings-bar.wasm' } else { '' }
                        if ($zellijApp -and $wasmBarPath -and [System.IO.File]::Exists($wasmBarPath)) {
                            try {
                                $zPsi = [System.Diagnostics.ProcessStartInfo]::new($zellijApp.Source)
                                foreach ($za in @('pipe', '--name', 'ws-ide-role', '--', 'ensure:editor')) {
                                    $zPsi.ArgumentList.Add($za)
                                }
                                $zPsi.RedirectStandardInput = $true
                                $zPsi.RedirectStandardOutput = $true
                                $zPsi.RedirectStandardError = $true
                                $zPsi.UseShellExecute = $false
                                $zPsi.CreateNoWindow = $true
                                $zProc = [System.Diagnostics.Process]::Start($zPsi)
                                if ($zProc) {
                                    try { $zProc.StandardInput.Close() } catch { $null = $_ }
                                    if (-not $zProc.WaitForExit(1500)) {
                                        try { $zProc.Kill($true) } catch { $null = $_ }
                                    }
                                }
                            } catch {
                                $null = $_
                            }
                        } else {
                            $ideScript = Resolve-WsBinScript 'ide'
                            if ($ideScript) { & $ideScript --focus-role editor *> $null }
                        }
                    }
                    return
                }
            }
        }
    }

    if ($nvimApp) {
        & $nvimApp.Source @args
        return
    }
    $vimAppFallback = Get-Command vim.exe, vim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vimAppFallback) {
        & $vimAppFallback.Source @args
    } else {
        Write-Error "Error: Neither 'nvim' nor 'vim' is installed."
    }
}

# Hybrid Zellij + Neovim RPC IDE Workspace Shortcuts
function ide {
    $ideScript = Resolve-WsBinScript 'ide'
    if ($ideScript) {
        & $ideScript @args
    } else {
        Write-Error "Error: bin/ide.ps1 was not found."
    }
}

function ide2 { ide --2pane @args }
function ide3 { ide --3pane @args }
function idek { ide --kill @args }
function qide { ide --quit @args }
function quit { ide --quit @args }

# Backward Compatibility Wrappers for legacy snake_case aliases
function go_testall  { go-testall @args }
function go_buildall { go-buildall @args }
function go_lint     { go-lint @args }
function yaml_lint   { yaml-lint @args }
