# =============================================================
# Developer Tool Shortcuts & Language Workspace Handlers
# =============================================================

function go-testall  { go test ./... @args }
function go-buildall { go build ./... @args }

function go-lint {
    $localConfigs = @('.golangci.yml', '.golangci.yaml', '.golangci.toml')
    $hasLocalConfig = $false
    foreach ($conf in $localConfigs) {
        if (Test-Path $conf) {
            $hasLocalConfig = $true
            break
        }
    }
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
    $localYamlConfigs = @('.yamllint', '.yamllint.yml', '.yamllint.yaml')
    $hasLocalConfig = $false
    foreach ($conf in $localYamlConfigs) {
        if (Test-Path $conf) {
            $hasLocalConfig = $true
            break
        }
    }
    if ($hasLocalConfig) {
        yamllint @args
    } elseif (Test-Path "$HOME\.yamllint.yml") {
        yamllint -c "$HOME\.yamllint.yml" @args
    } elseif (Test-Path "$HOME\.yamllint") {
        yamllint -c "$HOME\.yamllint" @args
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
    $vimApp = Get-Command vim.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $vimApp) {
        $vimApp = Get-Command vim -CommandType Application -ErrorAction SilentlyContinue
    }
    if ($vimApp) {
        Set-Alias -Name vim -Value $vimApp.Source -ErrorAction SilentlyContinue
    } else {
        Set-Alias -Name vim -Value nvim -ErrorAction SilentlyContinue
    }
    Set-Alias -Name vi -Value vim -ErrorAction SilentlyContinue
    Set-Alias -Name v -Value vim -ErrorAction SilentlyContinue
}

# Backward Compatibility Wrappers for legacy snake_case aliases
function go_testall  { go-testall @args }
function go_buildall { go-buildall @args }
function go_lint     { go-lint @args }
function yaml_lint   { yaml-lint @args }
