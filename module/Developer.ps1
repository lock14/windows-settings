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
        $ideScript = Resolve-WsBinScript 'ide'
        $ideLibDir = if ($ideScript) { Join-Path (Join-Path (Split-Path -Parent $ideScript) 'lib') 'ide' } else { '' }
        $corePath = if ($ideLibDir) { Join-Path $ideLibDir 'Core.ps1' } else { '' }
        $rpcPath = if ($ideLibDir) { Join-Path $ideLibDir 'Rpc.ps1' } else { '' }
        if ($corePath -and $rpcPath -and [System.IO.File]::Exists($corePath) -and [System.IO.File]::Exists($rpcPath)) {
            . $corePath
            . $rpcPath
            $parsed = ConvertFrom-EditorCliArgList -RawArgs $args -BaseCwd (Get-Location).ProviderPath
            if ($parsed.CanRouteRpc) {
                $sent = Send-IdeEditorBatch `
                    -FileTargets $parsed.FileTargets `
                    -GlobalLine $parsed.GlobalLine `
                    -ExCmds $parsed.ExCmds `
                    -FocusEditor $true `
                    -BaseCwd $parsed.BaseCwd `
                    -NvimExecutable $nvimApp.Source
                if ($sent) {
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
