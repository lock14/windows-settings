-- =============================================================
-- Modern Modular Neovim Configuration (init.lua)
-- Developer Workstation Orchestrator (Windows, Linux, macOS)
-- =============================================================

-- Resolve init.lua's physical config directory and ensure it is on runtimepath BEFORE requiring
-- `solarized.*` modules so `-u ./config/nvim/init.lua` works even when %LOCALAPPDATA%\nvim or
-- XDG_CONFIG_HOME has not been provisioned yet (e.g., fresh headless test sandboxes).
local uv = vim.uv or vim.loop
local is_win32 = vim.fn.has("win32") == 1

local init_source = debug.getinfo(1, "S").source
local init_path = (init_source and init_source:sub(1, 1) == "@")
    and init_source:sub(2)
    or (vim.fn.stdpath("config") .. "/init.lua")
local init_real = (uv and uv.fs_realpath and uv.fs_realpath(init_path)) or init_path
local init_dir = vim.fn.fnamemodify(init_path, ":p:h")
local real_config_dir = vim.fn.fnamemodify(init_real, ":p:h")
local config_dir = (uv and uv.fs_stat(init_dir .. "/lua/solarized")) and init_dir or real_config_dir

local rtp_entries = vim.opt.rtp:get()
if not vim.tbl_contains(rtp_entries, config_dir) then
    vim.opt.rtp:prepend(config_dir)
end
local after_dir = config_dir .. "/after"
if uv and uv.fs_stat(after_dir) and not vim.tbl_contains(rtp_entries, after_dir) then
    vim.opt.rtp:append(after_dir)
end

-- Build candidate repository roots so both direct `-u ./config/nvim/init.lua` invocations and
-- deployed copies under `%LOCALAPPDATA%\nvim` locate repository themes, lockfiles, and `bin/*` tools.
local function build_candidate_roots()
    local roots = {}
    local function add_root(r)
        if r and r ~= "" then
            local norm = vim.fs.normalize(r):gsub("/+$", "")
            if norm ~= "" and not vim.tbl_contains(roots, norm) then
                table.insert(roots, norm)
            end
        end
    end
    add_root(vim.fn.fnamemodify(init_real, ":h:h:h"))
    add_root(vim.fn.fnamemodify(init_real, ":h:h:h:h"))
    for _, tool in ipairs({ "theme", "ide" }) do
        local exe = vim.fn.exepath(tool)
        if exe ~= "" then
            local real_exe = (uv and uv.fs_realpath and uv.fs_realpath(exe)) or exe
            add_root(vim.fn.fnamemodify(real_exe, ":h:h"))
        end
    end
    return roots
end

local candidate_roots = build_candidate_roots()

local function detect_repo_root(roots)
    for _, r in ipairs(roots) do
        if uv and (uv.fs_stat(r .. "/config/themes") or uv.fs_stat(r .. "/colors/themes")) then
            return r
        end
    end
    return roots[1] or vim.fn.fnamemodify(init_real, ":h:h:h")
end

local repo_root = detect_repo_root(candidate_roots)

local function resolve_cli_bin(name)
    if type(name) ~= "string" or name == "" then
        return ""
    end
    local exe = vim.fn.exepath(name)
    if exe ~= "" and vim.fn.executable(exe) == 1 then
        return exe
    end
    for _, root in ipairs(build_candidate_roots()) do
        if is_win32 then
            local cmd_bin = root .. "/bin/" .. name .. ".cmd"
            if vim.fn.executable(cmd_bin) == 1 then
                return cmd_bin
            end
        end
        local plain_bin = root .. "/bin/" .. name
        if vim.fn.executable(plain_bin) == 1 then
            return plain_bin
        end
    end
    local home_dir = vim.env.HOME or vim.env.USERPROFILE or vim.fn.expand("~")
    local local_bin = home_dir .. "/.local/bin/" .. name
    if vim.fn.executable(local_bin) == 1 then
        return local_bin
    end
    return ""
end

-- Allow `:source $MYVIMRC` to pick up edits to local orchestrator submodules without evicting
-- maxmx03/solarized.nvim's own `solarized`, `solarized.palette`, or `solarized.highlights` modules.
for _, mod in ipairs({
    "options",
    "autocmds",
    "links",
    "keymaps",
    "ide",
    "images",
    "theme_groups",
    "theme",
    "treesitter",
    "lsp",
    "plugins",
}) do
    package.loaded["solarized." .. mod] = nil
end

local ctx = {
    config_dir = config_dir,
    repo_root = repo_root,
    candidate_roots = candidate_roots,
    resolve_cli_bin = resolve_cli_bin,
}

require("solarized.options").setup()

local ide = require("solarized.ide")
ide.setup(ctx)

local keymaps = require("solarized.keymaps")

local links = require("solarized.links")
links.setup({
    ide_job = ide.ide_job,
    resolve_cli_bin = resolve_cli_bin,
    open_external_url = keymaps.open_external_url,
})

local autocmds = require("solarized.autocmds")
autocmds.setup({ follow_editor_link = links.follow_editor_link })

keymaps.setup({
    follow_editor_link = links.follow_editor_link,
    recover_stale_cwd = autocmds.recover_stale_cwd,
})

local theme = require("solarized.theme")
theme.setup(ctx)

require("solarized.plugins").setup(ctx, theme)
