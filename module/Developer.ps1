# =============================================================
# Developer Tool Shortcuts & Language Workspace Handlers
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
        $cfg = Join-Path $cacheDir "golangci.yml"
        if (-not (Test-Path $cfg) -or (Get-Item $cfg).Length -eq 0) {
            try {
                Invoke-WebRequest -Uri "https://raw.githubusercontent.com/abcxyz/pkg/main/.golangci.yml" -OutFile $cfg -UseBasicParsing -ErrorAction Stop
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
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Set-Alias -Name vi -Value nvim -ErrorAction SilentlyContinue
    Set-Alias -Name vim -Value nvim -ErrorAction SilentlyContinue
    Set-Alias -Name v -Value nvim -ErrorAction SilentlyContinue
} else {
    $vimApp = Get-Command vim.exe, vim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $vimTarget = if ($vimApp) { $vimApp.Source } else { 'nvim' }
    Set-Alias -Name vim -Value $vimTarget -ErrorAction SilentlyContinue
    Set-Alias -Name vi -Value vim -ErrorAction SilentlyContinue
    Set-Alias -Name v -Value vim -ErrorAction SilentlyContinue
}

# Backward Compatibility Wrappers for legacy snake_case aliases
function go_testall  { go-testall @args }
function go_buildall { go-buildall @args }
function go_lint     { go-lint @args }
function yaml_lint   { yaml-lint @args }
