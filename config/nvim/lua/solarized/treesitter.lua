-- Tree-sitter polyglot parser management (45 parsers), WinLibs GCC discovery, orphaned lock reaping,
-- pinned upstream revisions, runtimepath precedence, and Neovim 0.12 query directive compatibility.

local M = {}

local is_win32 = vim.fn.has("win32") == 1

M.parsers = {
    "c", "cpp", "go", "java", "kotlin", "swift", "python", "rust",
    "typescript", "javascript", "bash", "markdown", "markdown_inline",
    "json", "yaml", "toml", "terraform", "sql", "lua",
    "vim", "vimdoc", "diff", "printf", "xml", "html", "css",
    "properties", "proto", "textproto", "regex",
    "elixir", "haskell", "ocaml", "clojure", "lean",
    "zig", "c_sharp", "scala", "ruby",
    "graphql", "starlark", "rego", "dockerfile", "make", "powershell",
}

local css_pinned_rev = "a93651c7bef1b73c47bdc7cd530ffa4ebffae032"
local lean_pinned_rev = "916c44f4d89c970f66dd34a49e7ce848f4d29e72"
M.pinned_revs = {
    css = css_pinned_rev,
    lean = lean_pinned_rev,
}
local lean_parser_spec = {
    install_info = {
        url = "https://github.com/Julian/tree-sitter-lean",
        revision = lean_pinned_rev,
        files = { "src/parser.c", "src/scanner.c" },
        location = "",
    },
    maintainers = { "@Julian" },
    tier = 2,
}

local ts_compiler_configured = false

function M.ensure_ts_compiler_configured()
    if ts_compiler_configured then
        return
    end
    ts_compiler_configured = true
    if is_win32 then
        if vim.fn.executable("gcc") == 0 then
            local local_app_data = vim.env.LOCALAPPDATA
            if local_app_data and local_app_data ~= "" then
                local winlibs_pattern = local_app_data .. "\\Microsoft\\WinGet\\Packages\\BrechtSanders.WinLibs*\\mingw64\\bin"
                local winlibs_matches = vim.fn.glob(winlibs_pattern, true, true)
                if type(winlibs_matches) == "table" and #winlibs_matches > 0 and vim.fn.isdirectory(winlibs_matches[1]) == 1 then
                    vim.env.PATH = winlibs_matches[1] .. ";" .. (vim.env.PATH or "")
                end
            end
        end
        if vim.fn.executable("gcc") == 1 then
            vim.env.CC = "gcc"
            vim.env.CXX = "g++"
        elseif vim.fn.executable("clang") == 1 then
            vim.env.CC = "clang"
            vim.env.CXX = "clang++"
        elseif vim.fn.executable("cl") == 1 then
            vim.env.CC = "cl"
        end

        local ts_install_ok, ts_install = pcall(require, "nvim-treesitter.install")
        if ts_install_ok and ts_install.compilers then
            ts_install.compilers = { "gcc", "clang", "cl", "zig" }
        end
    end
end

local function pin_parsers()
    M.ensure_ts_compiler_configured()
    local parsers_meta_ok, parsers_meta = pcall(require, "nvim-treesitter.parsers")
    if parsers_meta_ok then
        if parsers_meta.css and parsers_meta.css.install_info then
            parsers_meta.css.install_info.revision = css_pinned_rev
        end
        if not parsers_meta.get_parser_configs then
            parsers_meta.lean = vim.deepcopy(lean_parser_spec)
        else
            local pconfigs = parsers_meta.get_parser_configs()
            if pconfigs.css and pconfigs.css.install_info then
                pconfigs.css.install_info.revision = css_pinned_rev
            end
            pconfigs.lean = vim.deepcopy(lean_parser_spec)
        end
    end
end

M.pin_parsers = pin_parsers

function M.reap_orphan_ts_locks()
    local uv = vim.uv or vim.loop
    if not uv then
        return
    end
    local home_dir = vim.env.HOME or vim.env.USERPROFILE or vim.fn.expand("~")
    local ts_lock_dirs = {}
    if is_win32 and vim.env.LOCALAPPDATA and vim.env.LOCALAPPDATA ~= "" then
        table.insert(ts_lock_dirs, vim.env.LOCALAPPDATA .. "/tree-sitter/lock")
    end
    if vim.env.XDG_CACHE_HOME and vim.env.XDG_CACHE_HOME ~= "" then
        table.insert(ts_lock_dirs, vim.env.XDG_CACHE_HOME .. "/tree-sitter/lock")
    end
    if home_dir and home_dir ~= "" then
        table.insert(ts_lock_dirs, home_dir .. "/.cache/tree-sitter/lock")
        table.insert(ts_lock_dirs, home_dir .. "/Library/Caches/tree-sitter/lock")
    end

    local checked_proc = false
    local ts_running = false
    for _, ldir in ipairs(ts_lock_dirs) do
        local locks = vim.fn.glob(ldir .. "/*.lock", true, true)
        if type(locks) == "table" and #locks > 0 then
            if not checked_proc then
                checked_proc = true
                if is_win32 then
                    local out = vim.fn.system({ "tasklist", "/FI", "IMAGENAME eq tree-sitter.exe", "/NH" })
                    ts_running = (type(out) == "string" and out:lower():find("tree%-sitter%.exe") ~= nil)
                else
                    vim.fn.system({ "pgrep", "-x", "tree-sitter" })
                    ts_running = (vim.v.shell_error == 0)
                end
            end
            for _, lf in ipairs(locks) do
                local lst = uv.fs_stat(lf)
                local lage = lst and (os.time() - (lst.mtime and lst.mtime.sec or 0)) or 9999
                if (not ts_running) or lage > 180 then
                    pcall(uv.fs_unlink, lf)
                end
            end
        end
    end
end

local function read_parser_rev(site_dir, lang)
    local uv = vim.uv or vim.loop
    local rev_file = site_dir .. "/parser-info/" .. lang .. ".revision"
    if uv and uv.fs_open then
        local fd_rev = uv.fs_open(rev_file, "r", 292)
        if fd_rev then
            local chunk = uv.fs_read(fd_rev, 128, 0)
            uv.fs_close(fd_rev)
            if type(chunk) == "string" and chunk ~= "" then
                return vim.trim((chunk:match("^[^\r\n]+") or ""))
            end
        end
    elseif vim.fn.filereadable(rev_file) == 1 then
        local rev_lines = vim.fn.readfile(rev_file)
        if rev_lines and #rev_lines > 0 then
            return vim.trim(rev_lines[1])
        end
    end
    return ""
end

local function register_query_directives()
    if not (vim.treesitter and vim.treesitter.query and vim.treesitter.query.add_directive) then
        return
    end
    local function unwrap_node(node)
        if type(node) == "table" and not node.range then
            return node[1]
        end
        return node
    end

    vim.treesitter.query.add_directive("set-lang-from-info-string!", function(match, _, bufnr, pred, metadata)
        local capture_id = pred[2]
        local node = unwrap_node(match[capture_id])
        if not node or not node.range then
            return
        end
        metadata["injection.language"] = vim.treesitter.get_node_text(node, bufnr):lower()
    end, { force = true })

    vim.treesitter.query.add_directive("set-lang-from-mimetype!", function(match, _, bufnr, pred, metadata)
        local capture_id = pred[2]
        local node = unwrap_node(match[capture_id])
        if not node or not node.range then
            return
        end
        local type_attr_value = vim.treesitter.get_node_text(node, bufnr)
        local mimes = {
            ["importmap"] = "json",
            ["module"] = "javascript",
            ["application/ecmascript"] = "javascript",
            ["text/ecmascript"] = "javascript",
            ["text/javascript"] = "javascript",
        }
        if mimes[type_attr_value] then
            metadata["injection.language"] = mimes[type_attr_value]
        else
            local parts = vim.split(type_attr_value, "/", { trimempty = true })
            metadata["injection.language"] = parts[#parts]
        end
    end, { force = true })

    vim.treesitter.query.add_directive("downcase!", function(match, _, bufnr, pred, metadata)
        local capture_id = pred[2]
        local node = unwrap_node(match[capture_id])
        if not node or not node.range then
            return
        end
        metadata[pred[3]] = vim.treesitter.get_node_text(node, bufnr):lower()
    end, { force = true })
end

function M.plugin_spec(ctx)
    local config_dir = ctx and ctx.config_dir or nil
    return {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        build = function()
            if vim.env.NVIM_TS_SKIP_AUTO_INSTALL == "1" or package.loaded["nvim-treesitter.configs"] then
                return
            end
            M.ensure_ts_compiler_configured()
            pin_parsers()
            local ok_inst, install = pcall(require, "nvim-treesitter.install")
            if ok_inst and type(install.update) == "function" then
                local task = install.update("all", { summary = true })
                if #vim.api.nvim_list_uis() == 0 and type(task) == "table" and type(task.pwait) == "function" then
                    pcall(task.pwait, task, 300000)
                end
            end
        end,
        lazy = false,
        priority = 900,
        config = function()
            pin_parsers()
            vim.api.nvim_create_autocmd("User", {
                group = vim.api.nvim_create_augroup("SolarizedTreesitterPin", { clear = true }),
                pattern = { "TSUpdate*", "TSInstall*" },
                callback = pin_parsers,
            })

            -- Legacy nvim-treesitter.configs compatibility (when opened before lazy-lock.json syncs to main):
            -- enable highlight and indent only without triggering legacy `tree-sitter generate --no-bindings` installs.
            local ts_configs_ok, ts_configs = pcall(require, "nvim-treesitter.configs")
            if ts_configs_ok then
                ts_configs.setup({
                    ensure_installed = {},
                    auto_install = false,
                    highlight = {
                        enable = true,
                        additional_vim_regex_highlighting = false,
                    },
                    indent = { enable = true },
                })
            end

            -- Modern nvim-treesitter rewrite API
            local nts_ok, nts = pcall(require, "nvim-treesitter")
            if nts_ok and nts.setup and type(nts.get_installed) == "function" then
                local site_dir = vim.fn.stdpath("data") .. "/site"
                pcall(function()
                    nts.setup({
                        install_dir = site_dir,
                    })
                end)
                if vim.env.NVIM_TS_SKIP_AUTO_INSTALL ~= "1" then
                    local uv = vim.uv or vim.loop
                    local installed = {}
                    local scan_req = uv and uv.fs_scandir and uv.fs_scandir(site_dir .. "/parser") or nil
                    if scan_req then
                        while true do
                            local fname = uv.fs_scandir_next(scan_req)
                            if not fname then
                                break
                            end
                            local stem = fname:match("^(.+)%.[%w_]+$")
                            if stem then
                                installed[stem] = true
                            end
                        end
                    end
                    local any_missing_fast = false
                    for _, p in ipairs(M.parsers) do
                        if not installed[p] then
                            any_missing_fast = true
                            break
                        end
                    end
                    if any_missing_fast then
                        local ok_inst, inst_list = pcall(nts.get_installed, "parsers")
                        if not ok_inst or type(inst_list) ~= "table" then
                            inst_list = nts.get_installed()
                        end
                        for _, p in ipairs(inst_list) do
                            installed[p] = true
                        end
                    end
                    local need_css_install = (not installed["css"]) or (read_parser_rev(site_dir, "css") ~= css_pinned_rev)
                    local need_lean_install = (not installed["lean"]) or (read_parser_rev(site_dir, "lean") ~= lean_pinned_rev)
                    local to_install = {}
                    for _, p in ipairs(M.parsers) do
                        if not installed[p] and p ~= "css" and p ~= "lean" then
                            table.insert(to_install, p)
                        end
                    end
                    local pinned_to_install = {}
                    if need_css_install then
                        table.insert(pinned_to_install, "css")
                    end
                    if need_lean_install then
                        table.insert(pinned_to_install, "lean")
                    end

                    if (#to_install > 0 or #pinned_to_install > 0) and type(nts.install) == "function" then
                        pin_parsers()
                        local guard_path = vim.fn.stdpath("data") .. "/ws-ts-auto-install.lock"
                        local acquired_guard = false

                        local existing_stat = uv and uv.fs_stat(guard_path) or nil
                        if existing_stat then
                            local age = os.time() - (existing_stat.mtime and existing_stat.mtime.sec or 0)
                            local holder_alive = false
                            if age < 300 and vim.fn.filereadable(guard_path) == 1 then
                                local lines = vim.fn.readfile(guard_path)
                                local holder_pid = lines and tonumber(lines[1] or "") or nil
                                if holder_pid and holder_pid > 0 and uv and uv.kill then
                                    local ok_kill = pcall(uv.kill, holder_pid, 0)
                                    holder_alive = ok_kill
                                end
                            end
                            if not holder_alive and uv and uv.fs_unlink then
                                pcall(uv.fs_unlink, guard_path)
                            end
                        end

                        local fd = uv and uv.fs_open and uv.fs_open(guard_path, "wx", 384) or nil
                        if fd then
                            acquired_guard = true
                            pcall(uv.fs_write, fd, tostring(uv.os_getpid()) .. "\n", 0)
                            pcall(uv.fs_close, fd)
                            vim.api.nvim_create_autocmd("VimLeavePre", {
                                once = true,
                                callback = function()
                                    pcall(uv.fs_unlink, guard_path)
                                end,
                            })
                        end

                        if acquired_guard then
                            M.reap_orphan_ts_locks()
                            local is_headless = (#vim.api.nvim_list_uis() == 0)
                            if #to_install > 0 then
                                pcall(function()
                                    local task = nts.install(to_install, { max_jobs = 2 })
                                    if is_headless and task and task.pwait then
                                        task:pwait(120000)
                                    end
                                end)
                            end
                            if #pinned_to_install > 0 then
                                pcall(function()
                                    local task = nts.install(pinned_to_install, { force = true, max_jobs = 2 })
                                    if is_headless and task and task.pwait then
                                        task:pwait(120000)
                                    end
                                end)
                            end
                            if is_headless then
                                pcall(uv.fs_unlink, guard_path)
                            else
                                vim.defer_fn(function()
                                    pcall(uv.fs_unlink, guard_path)
                                end, 90000)
                            end
                        end
                    end
                end
            end

            -- Guarantee our query overrides (queries/ and after/queries/) precede site queries in runtimepath,
            -- including when invoked via `-u ./config/nvim/init.lua` with an unprovisioned stdpath("config").
            local uv = vim.uv or vim.loop
            if config_dir and config_dir ~= "" then
                vim.opt.rtp:prepend(config_dir)
                local after_dir = config_dir .. "/after"
                if uv and uv.fs_stat(after_dir) and not vim.tbl_contains(vim.opt.rtp:get(), after_dir) then
                    vim.opt.rtp:append(after_dir)
                end
            end
            local std_cfg = vim.fn.stdpath("config")
            if std_cfg ~= config_dir and uv and uv.fs_stat(std_cfg) then
                vim.opt.rtp:prepend(std_cfg)
            end

            register_query_directives()

            vim.api.nvim_create_autocmd("FileType", {
                group = vim.api.nvim_create_augroup("SolarizedTreesitterHighlight", { clear = true }),
                callback = function(args)
                    pcall(vim.treesitter.start, args.buf)
                end,
            })
        end,
    }
end

return M
