# =============================================================
# Developer Tool Shortcuts & Language Workspace Handlers
# =============================================================

function go-testall  { go test ./... @args }
function go-buildall { go build ./... @args }

function go-lint {
    $cacheDir = if ($env:XDG_CACHE_HOME) { "$env:XDG_CACHE_HOME" } else { "$HOME\.cache" }
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
    $cfg = Join-Path $cacheDir "golangci.yml"
    if (-not (Test-Path $cfg)) {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/abcxyz/pkg/main/.golangci.yml" -OutFile $cfg -UseBasicParsing
    }
    golangci-lint run -c $cfg @args
}

function yaml-lint {
    yamllint -c "$HOME\.yamllint.yml" @args
}

# Editor & CLI Aliases
Set-Alias -Name tf -Value terraform -ErrorAction SilentlyContinue
Set-Alias -Name vi -Value nvim -ErrorAction SilentlyContinue
Set-Alias -Name vim -Value nvim -ErrorAction SilentlyContinue
Set-Alias -Name v -Value nvim -ErrorAction SilentlyContinue
if (-not (Get-Command nvim -ErrorAction SilentlyContinue)) {
    Set-Alias -Name vi -Value vim -ErrorAction SilentlyContinue
    Set-Alias -Name v -Value vim -ErrorAction SilentlyContinue
}

# Backward Compatibility Wrappers for legacy snake_case aliases
function go_testall  { go-testall @args }
function go_buildall { go-buildall @args }
function go_lint     { go-lint @args }
function yaml_lint   { yaml-lint @args }
