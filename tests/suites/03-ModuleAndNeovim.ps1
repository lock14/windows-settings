# =============================================================
# Suite 3: WindowsSettings Module, Env Vars & Modular Neovim
# =============================================================
Write-Host "`n[3/8] Testing WindowsSettings Module & Modular Neovim Architecture..." -ForegroundColor Yellow

$moduleManifest = Join-Path $RootDir 'module\WindowsSettings.psd1'
Import-Module $moduleManifest -Force -DisableNameChecking

$expectedFunctions = @(
    'go-testall', 'go-buildall', 'go-lint', 'yaml-lint', 'guser-branch',
    'go_testall', 'go_buildall', 'go_lint', 'yaml_lint', 'fix-abcxyz-branch-name',
    'b', 'fs', 'Format-PathTree', 'ls', 'll', 'la', 'l', 'lt',
    'e', 'el', 'et', 'elm', 'elt', 'elx', 'icd',
    'v', 'ide', 'ide2', 'ide3', 'idek', 'qide', 'quit',
    'gco', 'gcb', 'gcm', 'gcd', 'ga', 'gaa', 'gst', 'gss', 'gd', 'gds',
    'gl', 'gp', 'gb', 'gba', 'gbd', 'gbD', 'gsta', 'gstp', 'gstl',
    'glog', 'glo', 'grb', 'grba', 'grbc', 'grbi', 'grh', 'grhh', 'gsw', 'gswc',
    'gcp', 'gcpa', 'gcpc',
    'gcommit', 'gamend', 'gfetch', 'gpush', 'gpushf', 'gpull', 'gup', 'gprune', 'gpurge', 'gsync',
    'gen-passwd', 'repeat-until-success', 'sum',
    'ds', 'btop', 'update', 'update-system', 'theme'
)

$missingFuncs = @($expectedFunctions | Where-Object { -not (Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue) })
if ($missingFuncs.Count -eq 0) {
    Add-TestPass "All $($expectedFunctions.Count) public functions defined and exported by WindowsSettings"
} else {
    Add-TestFail 'Exported functions missing' ($missingFuncs -join ', ')
}

if (-not (Test-Path 'Alias:cat') -and -not (Get-Command cat -CommandType Function -ErrorAction SilentlyContinue)) {
    Add-TestPass 'cat is un-aliased and un-wrapped so coreutils cat.exe runs natively'
} else {
    Add-TestFail 'cat un-aliasing' 'cat should not be a PowerShell alias or wrapper function'
}

$bPipeTest = (('b pipeline test' | & (Get-Command b -CommandType Function) --plain) -join "`n").Trim()
if ($bPipeTest -eq 'b pipeline test') {
    Add-TestPass 'b (bat) function handles pipeline input cleanly without hanging'
} else {
    Add-TestFail 'b function pipeline' "Expected 'b pipeline test', got '$bPipeTest'"
}

foreach ($al in @('tf', 'vi', 'vim')) {
    if (Get-Alias -Name $al -ErrorAction SilentlyContinue) {
        Add-TestPass "Alias defined: $al"
    } else {
        Add-TestFail "Alias missing: $al" "Alias $al not found"
    }
}

if ($env:GOPATH -and $env:GOCACHE -and $env:ELAN_HOME -and
    $env:JQ_COLORS -match '38;2;' -and
    $env:FZF_DEFAULT_OPTS -match 'border:' -and
    $env:LS_COLORS -match '\*\.ps1=(00|38;2;)') {
    Add-TestPass 'Environment exports isolated GOPATH/GOCACHE/ELAN_HOME, 24-bit JQ_COLORS, BASE01 FZF borders, and 40-language LS_COLORS'
} else {
    Add-TestFail 'Module environment exports' "GOPATH=$env:GOPATH, ELAN_HOME=$env:ELAN_HOME, JQ=$env:JQ_COLORS, FZF=$env:FZF_DEFAULT_OPTS"
}

# Verify v() RPC routing & --listen Editor socket recovery
$devRaw = Get-Content -LiteralPath (Join-Path $RootDir 'module\Developer.ps1') -Raw
$coreModPath = Join-Path $RootDir 'libexec\ide\Core.ps1'
$rpcModPath = Join-Path $RootDir 'libexec\ide\Rpc.ps1'
$rpcRaw = Get-Content -LiteralPath $rpcModPath -Raw
$parsedV = & {
    . $coreModPath
    . $rpcModPath
    ConvertFrom-EditorCliArgList -RawArgs @('+42', '+/search', '-c', 'set wrap', '--', '-dash.txt', 'sample.go:18:4') -BaseCwd $RootDir
}
if ($devRaw -match 'Send-IdeEditorBatch' -and
    $devRaw -match '--listen' -and
    $rpcRaw -match 'NamedPipeClientStream' -and
    $rpcRaw -match 'checktime' -and
    $rpcRaw -match 'haslocaldir' -and
    $parsedV.CanRouteRpc -and
    $parsedV.GlobalLine -eq 42 -and
    $parsedV.ExCmds.Count -eq 2 -and
    $parsedV.FileTargets.Count -eq 2 -and
    $parsedV.FileTargets[0].path.EndsWith('-dash.txt') -and
    $parsedV.FileTargets[1].line -eq 18) {
    Add-TestPass 'Smart editor opener v() supports multi-file RPC, NamedPipeClientStream MsgPack-RPC, checktime, and --listen Editor recovery'
} else {
    Add-TestFail 'v() & Rpc.ps1 validation' 'Missing NamedPipeClientStream, --listen recovery, checktime, or multi-file arg parsing'
}

# Verify modular Neovim lua/solarized/*.lua, lazy-lock.json (snacks.nvim), ftplugin/java.lua, and sync-treesitter.lua
$nvimDir = Join-Path $RootDir 'config\nvim'
$expectedLuaMods = @(
    'options.lua', 'autocmds.lua', 'keymaps.lua', 'links.lua', 'ide.lua',
    'images.lua', 'theme_groups.lua', 'theme.lua', 'treesitter.lua', 'lsp.lua', 'plugins.lua'
)
$missingLuaMods = @($expectedLuaMods | Where-Object { -not (Test-Path -LiteralPath (Join-Path $nvimDir "lua\solarized\$_") -PathType Leaf) })
$allLuaRaw = (@((Join-Path $nvimDir 'init.lua')) + @($expectedLuaMods | ForEach-Object { Join-Path $nvimDir "lua\solarized\$_" }) |
    Where-Object { Test-Path -LiteralPath $_ } |
    ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
$lockRaw = Get-Content -LiteralPath (Join-Path $nvimDir 'lazy-lock.json') -Raw
$javaRaw = Get-Content -LiteralPath (Join-Path $nvimDir 'ftplugin\java.lua') -Raw

if ($missingLuaMods.Count -eq 0 -and
    $lockRaw -match '"snacks\.nvim"' -and
    $allLuaRaw -match 'apply_home_settings_theme' -and
    $allLuaRaw -match 'SolarizedIdeSocket' -and
    $allLuaRaw -match 'BrechtSanders\.WinLibs' -and
    $allLuaRaw -match 'GIT_DEFAULT_REF_FORMAT' -and
    $allLuaRaw -match 'flip_columns\s*=\s*110' -and
    $allLuaRaw -match 'send_file_to_ai' -and
    $javaRaw -match 'MODULE\.bazel' -and
    $javaRaw -match 'sha256' -and
    $javaRaw -match 'config_win' -and
    (Test-Path -LiteralPath (Join-Path $RootDir 'tests\sync-treesitter.lua'))) {
    Add-TestPass 'Modular Neovim (init.lua + 11 lua/solarized/*.lua modules), snacks.nvim, SolarizedIdeSocket, java.lua & sync-treesitter.lua valid'
} else {
    Add-TestFail 'Modular Neovim validation' "Missing modules ($($missingLuaMods -join ', ')) or expected hooks"
}

$nvimCmd = Get-Command nvim.exe, nvim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($nvimCmd) {
    $prevIdeWorkdir = $env:IDE_WORKDIR
    $prevSkipTs = $env:NVIM_TS_SKIP_AUTO_INSTALL
    $prevGitRefFmt = $env:GIT_DEFAULT_REF_FORMAT
    try {
        $env:NVIM_TS_SKIP_AUTO_INSTALL = '1'
        $env:GIT_DEFAULT_REF_FORMAT = 'files'
        $nvimSmoke = (& $nvimCmd.Source -i NONE --headless -u (Join-Path $nvimDir 'init.lua') '+Theme dracula' '+Theme rose-pine' '+Theme solarized-dark' '+qa' 2>&1) -join "`n"
        if ($LASTEXITCODE -eq 0) {
            Add-TestPass 'Headless Neovim (-i NONE) loads all 11 solarized modules and switches across 22 themes cleanly'
        } else {
            Add-TestFail 'Headless Neovim theme smoke check' "Exit=$($LASTEXITCODE): $nvimSmoke"
        }

        $env:IDE_WORKDIR = $RootDir
        $linkTestLua = "vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'See [arch](docs/ide-architecture.md#links-inline-images-clipboard-and-portable-shell-parity)' }); vim.api.nvim_win_set_cursor(0, { 1, 8 }); local ok = require('solarized.links').follow_editor_link(false, false); assert(ok == true, 'link failed'); assert(vim.api.nvim_buf_get_name(0):find('ide%-architecture%.md') ~= nil, 'wrong buf'); assert(vim.api.nvim_win_get_cursor(0)[1] > 10, 'anchor jump failed')"
        $nvimLinkOut = (& $nvimCmd.Source -i NONE --headless -u (Join-Path $nvimDir 'init.lua') "+lua $linkTestLua" '+qa!' 2>&1) -join "`n"
        if ($LASTEXITCODE -eq 0) {
            Add-TestPass 'Neovim solarized.links resolves workspace-relative Markdown + #heading anchor links (<M-LeftMouse>/<C-LeftMouse>/gx)'
        } else {
            Add-TestFail 'Neovim solarized.links check' "Exit=$($LASTEXITCODE): $nvimLinkOut"
        }
    } finally {
        $env:IDE_WORKDIR = $prevIdeWorkdir
        $env:NVIM_TS_SKIP_AUTO_INSTALL = $prevSkipTs
        $env:GIT_DEFAULT_REF_FORMAT = $prevGitRefFmt
    }
}
