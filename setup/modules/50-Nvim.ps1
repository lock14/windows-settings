# =============================================================
# setup/modules/50-Nvim.ps1 - Neovim, Vim & Headless Lockfile Sync
# =============================================================
param(
    [string]$RepoRoot = '',
    [switch]$SkipNvim,
    [switch]$SkipVim,
    [switch]$FunctionsOnly,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
if (-not (Get-Command Write-SetupStage -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Log.ps1')
}
if (-not (Get-Command Deploy-ConfigFile -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Deploy.ps1')
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,
        [hashtable]$EnvironmentOverrides = @{},
        [int]$TimeoutSeconds = 60
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($a in $ArgumentList) {
        $psi.ArgumentList.Add($a)
    }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    foreach ($kv in $EnvironmentOverrides.GetEnumerator()) {
        $psi.Environment[$kv.Key] = [string]$kv.Value
    }

    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $proc) {
        return @{ ExitCode = 1; StdOut = ''; StdErr = 'Failed to start process' }
    }
    try { $proc.StandardInput.Close() } catch { Write-Verbose 'stdin close skipped' }
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out process killed' }
        return @{ ExitCode = 124; StdOut = ''; StdErr = "Timed out after ${TimeoutSeconds}s" }
    }
    return @{
        ExitCode = $proc.ExitCode
        StdOut   = $outTask.GetAwaiter().GetResult()
        StdErr   = $errTask.GetAwaiter().GetResult()
    }
}

function Invoke-TreeSitterTempCleanup([string]$NvimDataDir) {
    if (-not $NvimDataDir -or -not (Test-Path -LiteralPath $NvimDataDir -PathType Container)) { return }
    foreach ($tsTmp in (Get-ChildItem -LiteralPath $NvimDataDir -Filter 'tree-sitter-*' -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $tsTmp.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-HeadlessNvimSync {
    param(
        [string]$RepoRoot = '',
        [switch]$DryRun
    )
    $resolvedRepo = if ($RepoRoot) { $RepoRoot } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
    $nvimCfgDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'nvim' } else { Join-Path (Join-Path $HOME '.config') 'nvim' }
    $repoNvimDir = Join-Path (Join-Path $resolvedRepo 'config') 'nvim'

    $lockFile = if (Test-Path -LiteralPath (Join-Path $nvimCfgDir 'lazy-lock.json') -PathType Leaf) {
        Join-Path $nvimCfgDir 'lazy-lock.json'
    } else {
        Join-Path $repoNvimDir 'lazy-lock.json'
    }
    $initLua = if (Test-Path -LiteralPath (Join-Path $nvimCfgDir 'init.lua') -PathType Leaf) {
        Join-Path $nvimCfgDir 'init.lua'
    } else {
        Join-Path $repoNvimDir 'init.lua'
    }

    if ($DryRun) {
        Write-Host '  [DryRun] Would reconcile headless Neovim plugins against lazy-lock.json (-i NONE)' -ForegroundColor DarkCyan
        return
    }

    if (-not (Test-Path -LiteralPath $lockFile -PathType Leaf) -or -not (Test-Path -LiteralPath $initLua -PathType Leaf)) {
        return
    }

    $nvimCmd = Get-Command nvim.exe, nvim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $gitCmd = Get-Command git.exe, git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $nvimCmd -or $null -eq $gitCmd) {
        Write-Host '  Notice: nvim or git not found on PATH; skipping headless plugin sync.' -ForegroundColor DarkYellow
        return
    }

    $verCheck = Invoke-BoundedProcess -FilePath $nvimCmd.Source `
        -ArgumentList @('--headless', '-u', 'NONE', '-i', 'NONE', '-c', 'if !has("nvim-0.10") | cquit 1 | endif', '-c', 'qall!') `
        -TimeoutSeconds 15
    if ($verCheck.ExitCode -ne 0) {
        Write-Host '  Notice: Neovim < 0.10 detected; skipping headless plugin sync.' -ForegroundColor DarkYellow
        return
    }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws-nvim-sync-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    try {
        $nullLog = Join-Path $tmpDir 'nvim.log'
        $checkLuaPath = Join-Path $tmpDir 'check.lua'
        $checkLua = @'
local uv = vim.uv or vim.loop
local lock_path = vim.env.HS_LOCKFILE or ""

local function read_file(path)
    local fd = uv.fs_open(path, "r", 438)
    if not fd then
        return nil
    end
    local st = uv.fs_fstat(fd)
    local data = (st and st.size and st.size > 0 and st.size <= 262144) and uv.fs_read(fd, st.size, 0) or nil
    uv.fs_close(fd)
    return data
end

local function is_dir_entry(parent, name, ftype)
    if ftype == "directory" then
        return true
    end
    if ftype == nil or ftype == "link" then
        local st = uv.fs_stat(parent .. "/" .. name)
        return st ~= nil and st.type == "directory"
    end
    return false
end

local function resolve_head_sha(git_dir)
    local head = vim.trim(read_file(git_dir .. "/HEAD") or "")
    if head == "" then
        return nil
    end
    local sym = head:match("^ref:%s*(.+)$")
    if not sym then
        return head:match("^%x+$") and head or nil
    end
    local loose = vim.trim(read_file(git_dir .. "/" .. sym) or "")
    if loose ~= "" and loose:match("^%x+$") then
        return loose
    end
    local packed = read_file(git_dir .. "/packed-refs") or ""
    for line in packed:gmatch("[^\r\n]+") do
        local sha, ref = line:match("^(%x+)%s+(.+)$")
        if sha and ref == sym then
            return sha
        end
    end
    return nil
end

local raw_lock = read_file(lock_path)
local ok, lock = pcall(vim.json.decode, raw_lock or "")
if not ok or type(lock) ~= "table" then
    io.stderr:write("Failed to decode lazy-lock.json\n")
    vim.cmd("cquit 1")
end

local nvim_data = vim.fn.stdpath("data")
local lazy_dir = nvim_data .. "/lazy"
local lazy_sha = (lock["lazy.nvim"] and lock["lazy.nvim"].commit) or ""
local synced = true

local data_scan = uv.fs_scandir(nvim_data)
if data_scan then
    while true do
        local name = uv.fs_scandir_next(data_scan)
        if not name then
            break
        end
        if name:find("^tree%-sitter%-") then
            synced = false
            break
        end
    end
end

local lazy_scan = synced and uv.fs_scandir(lazy_dir) or nil
if not lazy_scan then
    synced = false
else
    local seen = {}
    while true do
        local name, ftype = uv.fs_scandir_next(lazy_scan)
        if not name then
            break
        end
        if name:sub(-8) == ".cloning" then
            synced = false
            break
        end
        if is_dir_entry(lazy_dir, name, ftype) then
            if not lock[name] then
                synced = false
                break
            end
            seen[name] = true
        end
    end
    if synced then
        for name, spec in pairs(lock) do
            if not seen[name] or type(spec) ~= "table" or type(spec.commit) ~= "string" then
                synced = false
                break
            end
            local git_dir = lazy_dir .. "/" .. name .. "/.git"
            local git_st = uv.fs_stat(git_dir)
            if not (git_st and git_st.type == "directory") then
                synced = false
                break
            end
            if uv.fs_stat(git_dir .. "/reftable") then
                synced = false
                break
            end
            local cfg = read_file(git_dir .. "/config") or ""
            if cfg:find("refs/heads/.invalid", 1, true) then
                synced = false
                break
            end
            if resolve_head_sha(git_dir) ~= spec.commit then
                synced = false
                break
            end
            if name == "nvim-treesitter" then
                local origin_head = read_file(git_dir .. "/refs/remotes/origin/HEAD") or ""
                if origin_head:find("refs/remotes/origin/master", 1, true) then
                    synced = false
                    break
                end
            end
        end
    end
end

io.write(string.format("SYNCED=%s\nLAZY_SHA=%s\nNVIM_DATA=%s\n", tostring(synced), lazy_sha, nvim_data))
'@
        [System.IO.File]::WriteAllText($checkLuaPath, $checkLua.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

        $probe = Invoke-BoundedProcess -FilePath $nvimCmd.Source `
            -ArgumentList @('--headless', '-u', 'NONE', '-i', 'NONE', '-c', 'lua local ok, err = pcall(dofile, vim.env.HS_CHECK_LUA); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit 1") end', '-c', 'qall!') `
            -EnvironmentOverrides @{
                HS_LOCKFILE   = $lockFile
                HS_CHECK_LUA  = $checkLuaPath
                NVIM_LOG_FILE = $nullLog
            } `
            -TimeoutSeconds 30

        $synced = $false
        $lazySha = ''
        $nvimData = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'nvim-data' } else { Join-Path (Join-Path (Join-Path $HOME '.local') 'share') 'nvim' }
        foreach ($line in ($probe.StdOut -split '\r?\n')) {
            if ($line -match '^SYNCED=(.+)$') { $synced = ($Matches[1].Trim() -eq 'true') }
            elseif ($line -match '^LAZY_SHA=(.*)$') { $lazySha = $Matches[1].Trim() }
            elseif ($line -match '^NVIM_DATA=(.+)$') { $nvimData = $Matches[1].Trim() }
        }

        if ($synced) {
            Write-Host '==> Neovim plugins already match lazy-lock.json.' -ForegroundColor Green
            return
        }

        Write-Host '==> Reconciling Neovim plugins from lazy-lock.json...' -ForegroundColor Cyan
        $lazyDir = Join-Path $nvimData 'lazy'
        if (-not (Test-Path -LiteralPath $lazyDir -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $lazyDir | Out-Null
        }

        Invoke-TreeSitterTempCleanup $nvimData

        $prevGitRefFmt = $env:GIT_DEFAULT_REF_FORMAT
        $env:GIT_DEFAULT_REF_FORMAT = 'files'
        try {
            foreach ($repoDir in (Get-ChildItem -LiteralPath $lazyDir -Directory -ErrorAction SilentlyContinue)) {
                $dotGit = Join-Path $repoDir.FullName '.git'
                if (-not (Test-Path -LiteralPath $dotGit -PathType Container)) { continue }
                if (Test-Path -LiteralPath (Join-Path $dotGit 'reftable') -PathType Container) {
                    & $gitCmd.Source -C $repoDir.FullName refs migrate --ref-format=files *> $null
                    if ($LASTEXITCODE -ne 0) {
                        Remove-Item -LiteralPath $repoDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        continue
                    }
                }
                $gitCfg = Join-Path $dotGit 'config'
                if ((Test-Path -LiteralPath $gitCfg -PathType Leaf) -and ([System.IO.File]::ReadAllText($gitCfg).Contains('refs/heads/.invalid'))) {
                    & $gitCmd.Source -C $repoDir.FullName config --unset-all remote.origin.fetch 'refs/heads/\.invalid' *> $null
                }
            }

            if ($lazySha) {
                $lazyPluginDir = Join-Path $lazyDir 'lazy.nvim'
                if (-not (Test-Path -LiteralPath (Join-Path $lazyPluginDir '.git') -PathType Container)) {
                    if (Test-Path -LiteralPath $lazyPluginDir) {
                        Remove-Item -LiteralPath $lazyPluginDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    & $gitCmd.Source clone --filter=blob:none 'https://github.com/folke/lazy.nvim.git' $lazyPluginDir *> $null
                }
                if (Test-Path -LiteralPath (Join-Path $lazyPluginDir '.git') -PathType Container) {
                    $curLazySha = (& $gitCmd.Source -C $lazyPluginDir rev-parse HEAD 2>$null | Out-String).Trim()
                    if ($curLazySha -ne $lazySha) {
                        & $gitCmd.Source -C $lazyPluginDir cat-file -e "${lazySha}^{commit}" *> $null
                        if ($LASTEXITCODE -ne 0) {
                            & $gitCmd.Source -C $lazyPluginDir fetch --tags --force origin *> $null
                        }
                        & $gitCmd.Source -C $lazyPluginDir checkout --force $lazySha *> $null
                    }
                }
            }
        } finally {
            $env:GIT_DEFAULT_REF_FORMAT = $prevGitRefFmt
        }

        $ephemeralLock = Join-Path $tmpDir 'lazy-lock.json'
        Copy-Item -LiteralPath $lockFile -Destination $ephemeralLock -Force
        $syncLuaPath = Join-Path $tmpDir 'sync.lua'
        $syncLua = @'
local ok, lazy = pcall(require, "lazy")
if not ok then
    io.stderr:write("Failed to load lazy.nvim\n")
    vim.cmd("cquit 1")
end
local Config = require("lazy.core.config")
if vim.env.NVIM_LAZY_LOCKFILE and vim.env.NVIM_LAZY_LOCKFILE ~= "" and Config.options then
    Config.options.lockfile = vim.env.NVIM_LAZY_LOCKFILE
end
lazy.restore({ wait = true, show = false })
lazy.clean({ wait = true, show = false })
local Plugin = require("lazy.core.plugin")
local errs = {}
for name, plugin in pairs(Config.plugins or {}) do
    if Plugin.has_errors(plugin) then
        for _, task in ipairs((plugin._ and plugin._.tasks) or {}) do
            if task:has_errors() then
                table.insert(errs, name .. " (" .. tostring(task.name) .. "): " .. tostring(task:output(vim.log.levels.ERROR)))
            end
        end
    end
end
if #errs > 0 then
    io.stderr:write("Neovim plugin sync failed:\n" .. table.concat(errs, "\n") .. "\n")
    vim.cmd("cquit 1")
end
'@
        [System.IO.File]::WriteAllText($syncLuaPath, $syncLua.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

        $syncRes = Invoke-BoundedProcess -FilePath $nvimCmd.Source `
            -ArgumentList @('--headless', '-i', 'NONE', '-u', $initLua, '-c', 'lua local ok, err = pcall(dofile, vim.env.HS_NVIM_SYNC_LUA); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit 1") end', '-c', 'qall!') `
            -EnvironmentOverrides @{
                NVIM_LAZY_LOCKFILE        = $ephemeralLock
                NVIM_TS_SKIP_AUTO_INSTALL = '1'
                NVIM_LOG_FILE             = $nullLog
                GIT_DEFAULT_REF_FORMAT    = 'files'
                HS_NVIM_SYNC_LUA          = $syncLuaPath
            } `
            -TimeoutSeconds 180

        Invoke-TreeSitterTempCleanup $nvimData

        $tsOriginHead = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $lazyDir 'nvim-treesitter') '.git') 'refs') 'remotes') 'origin\HEAD'
        if ((Test-Path -LiteralPath $tsOriginHead -PathType Leaf) -and ([System.IO.File]::ReadAllText($tsOriginHead).Contains('refs/remotes/origin/master'))) {
            & $gitCmd.Source -C (Join-Path $lazyDir 'nvim-treesitter') remote set-head origin main *> $null
        }

        if ($syncRes.ExitCode -ne 0) {
            Write-Warning "Headless Neovim lockfile restore exited with code $($syncRes.ExitCode): $($syncRes.StdErr.Trim())"
        } else {
            Write-Host '==> Neovim plugins synchronized with lazy-lock.json.' -ForegroundColor Green
        }
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($FunctionsOnly) { return }

if ($SkipNvim -and $SkipVim) {
    Write-SetupSkip -Stage '50-Nvim' -Message 'Skipping Neovim and Vim configuration.'
    return
}

Write-SetupStage -Stage '50-Nvim' -Message 'Configuring Neovim and Vim editors...'
$resolvedRoot = if ($RepoRoot) { $RepoRoot } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }

if (-not $SkipNvim) {
    $nvimSourceDir = Join-Path (Join-Path $resolvedRoot 'config') 'nvim'
    $nvimDestDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'nvim' } else { Join-Path (Join-Path $userHome '.config') 'nvim' }

    Deploy-ConfigFile -Name 'Neovim configuration' `
        -SourcePath (Join-Path $nvimSourceDir 'init.lua') `
        -DestinationPath (Join-Path $nvimDestDir 'init.lua') `
        -DryRun:$DryRun

    $staleMdInline = Join-Path (Join-Path (Join-Path $nvimDestDir 'after') 'queries') 'markdown_inline'
    if (-not $DryRun -and (Test-Path -LiteralPath $staleMdInline)) {
        Remove-Item -Recurse -Force -LiteralPath $staleMdInline -ErrorAction SilentlyContinue
    }

    foreach ($subDir in @('lua', 'queries', 'after', 'ftplugin')) {
        $srcPath = Join-Path $nvimSourceDir $subDir
        $dstPath = Join-Path $nvimDestDir $subDir
        if (Test-Path -LiteralPath $srcPath -PathType Container) {
            if ($DryRun) {
                Write-SetupDryRun "Would deploy Neovim $subDir to $dstPath"
            } else {
                if (-not (Test-Path -LiteralPath $dstPath -PathType Container)) {
                    New-Item -ItemType Directory -Force -Path $dstPath | Out-Null
                }
                Copy-Item -Path (Join-Path $srcPath '*') -Destination $dstPath -Recurse -Force
                Write-SetupSuccess "Neovim $subDir deployed to $dstPath"
            }
        }
    }

    $lockSrc = Join-Path $nvimSourceDir 'lazy-lock.json'
    if (Test-Path -LiteralPath $lockSrc -PathType Leaf) {
        Deploy-ConfigFile -Name 'Neovim lazy-lock' `
            -SourcePath $lockSrc `
            -DestinationPath (Join-Path $nvimDestDir 'lazy-lock.json') `
            -DryRun:$DryRun
    }

    Invoke-HeadlessNvimSync -RepoRoot $resolvedRoot -DryRun:$DryRun
}

if (-not $SkipVim) {
    $vimrcSource = Join-Path (Join-Path (Join-Path $resolvedRoot 'config') 'vim') '_vimrc'
    Deploy-ConfigFile -Name 'Vim configuration' `
        -SourcePath $vimrcSource `
        -DestinationPath (Join-Path $userHome '_vimrc') `
        -AltDestinations @((Join-Path $userHome '.vimrc')) `
        -DryRun:$DryRun
}
