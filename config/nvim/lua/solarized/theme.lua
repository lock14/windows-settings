-- Dynamic built-in (config/themes/*.theme & colors/themes/*.theme) + custom user palette resolver,
-- terminal ANSI calibration, and live Named Pipe / socket RPC theme hot-reload.
-- Note: module name avoids `solarized.palette` and `solarized.highlights` owned by maxmx03/solarized.nvim.

local theme_groups = require("solarized.theme_groups")

local M = {}

local repo_root = ""
local candidate_roots = {}
local resolve_cli_bin_fn = nil

local default_solarized_palette = {
    base03 = "#002B36",
    base02 = "#073642",
    base04 = "#002731",
    base01 = "#586E75",
    base00 = "#657B83",
    base0 = "#839496",
    base1 = "#93A1A1",
    base2 = "#EEE8D5",
    base3 = "#FDF6E3",
    yellow = "#B58900",
    orange = "#CB4B16",
    red = "#DC322F",
    magenta = "#D33682",
    violet = "#6C71C4",
    blue = "#268BD2",
    cyan = "#2AA198",
    green = "#859900",
    mix_green = "#274C25",
    mix_yellow = "#364725",
    mix_blue = "#0B4764",
    mix_red = "#422D33",
    mix_magenta = "#3E2E4C",
    mix_base1 = "#2C4E56",
}

local default_solarized_light_palette = {
    base03 = "#FDF6E3",
    base02 = "#EEE8D5",
    base04 = "#E6DFCA",
    base01 = "#93A1A1",
    base00 = "#839496",
    base0 = "#657B83",
    base1 = "#586E75",
    base2 = "#073642",
    base3 = "#002B36",
    yellow = "#B58900",
    orange = "#CB4B16",
    red = "#DC322F",
    magenta = "#D33682",
    violet = "#6C71C4",
    blue = "#268BD2",
    cyan = "#2AA198",
    green = "#859900",
    mix_green = "#E5ECD0",
    mix_yellow = "#F0E4C0",
    mix_blue = "#D8E6EE",
    mix_red = "#F6D8D3",
    mix_magenta = "#F3D9E4",
    mix_base1 = "#E4DEC8",
}

local theme_key_map = {
    BASE03 = "base03",
    BASE02 = "base02",
    BASE04 = "base04",
    BASE01 = "base01",
    BASE00 = "base00",
    BASE0 = "base0",
    BASE1 = "base1",
    BASE2 = "base2",
    BASE3 = "base3",
    YELLOW = "yellow",
    ORANGE = "orange",
    RED = "red",
    MAGENTA = "magenta",
    VIOLET = "violet",
    BLUE = "blue",
    CYAN = "cyan",
    GREEN = "green",
    MIX_GREEN = "mix_green",
    MIX_YELLOW = "mix_yellow",
    MIX_BLUE = "mix_blue",
    MIX_RED = "mix_red",
    MIX_MAGENTA = "mix_magenta",
    MIX_BASE1 = "mix_base1",
}

local function config_home()
    if vim.env.XDG_CONFIG_HOME and vim.env.XDG_CONFIG_HOME ~= "" then
        return vim.env.XDG_CONFIG_HOME
    end
    local home_dir = vim.env.HOME or vim.env.USERPROFILE or vim.fn.expand("~")
    return home_dir .. "/.config"
end

local function add_unique_dir(list, dir)
    if dir and dir ~= "" then
        local norm = vim.fs.normalize(dir):gsub("/+$", "")
        if norm ~= "" and not vim.tbl_contains(list, norm) then
            table.insert(list, norm)
        end
    end
end

local function builtin_theme_dirs(cfg_home)
    local uv = vim.uv or vim.loop
    local cfg_std = vim.fn.stdpath("config")
    local cfg_real = (uv and uv.fs_realpath and uv.fs_realpath(cfg_std)) or cfg_std
    local dirs = {}
    if repo_root ~= "" then
        add_unique_dir(dirs, repo_root .. "/config/themes")
        add_unique_dir(dirs, repo_root .. "/colors/themes")
    end
    for _, root in ipairs(candidate_roots) do
        add_unique_dir(dirs, root .. "/config/themes")
        add_unique_dir(dirs, root .. "/colors/themes")
    end
    add_unique_dir(dirs, cfg_real .. "/../../config/themes")
    add_unique_dir(dirs, cfg_real .. "/../../../colors/themes")
    if cfg_home and cfg_home ~= "" then
        add_unique_dir(dirs, cfg_home .. "/windows-settings/themes")
    end
    return dirs
end

local function user_theme_dirs(cfg_home)
    local dirs = {}
    add_unique_dir(dirs, vim.env.WINDOWS_SETTINGS_USER_THEMES_DIR)
    add_unique_dir(dirs, vim.env.HOME_SETTINGS_USER_THEMES_DIR)
    add_unique_dir(dirs, cfg_home .. "/themes")
    add_unique_dir(dirs, cfg_home .. "/windows-settings/themes")
    add_unique_dir(dirs, cfg_home .. "/home-settings/themes")
    return dirs
end

local function theme_search_dirs(cfg_home)
    local dirs = user_theme_dirs(cfg_home)
    for _, bdir in ipairs(builtin_theme_dirs(cfg_home)) do
        add_unique_dir(dirs, bdir)
    end
    return dirs
end

local function parse_theme_file_kv(path)
    local kv = {}
    if vim.fn.filereadable(path) ~= 1 then
        return kv
    end
    for _, raw_line in ipairs(vim.fn.readfile(path)) do
        local s = vim.trim(raw_line)
        if s ~= "" and s:sub(1, 1) ~= "#" then
            s = s:gsub("^export%s+", "")
            local k, v = s:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.*)$")
            if k and v then
                v = vim.trim(v)
                local q = v:sub(1, 1)
                if (q == '"' or q == "'") and #v >= 2 then
                    local end_idx = v:find(q, 2, true)
                    if end_idx then
                        local rest = vim.trim(v:sub(end_idx + 1))
                        if rest == "" or rest:sub(1, 1) == "#" then
                            v = v:sub(2, end_idx - 1)
                        end
                    end
                else
                    v = vim.trim((v:gsub("%s+#.*$", "")))
                end
                kv[k] = v
            end
        end
    end
    return kv
end

local function is_valid_hex(val)
    return type(val) == "string"
        and val:match("^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") ~= nil
end

function M.resolve_active_theme_palette(_)
    local cfg_home = config_home()
    local theme_files = {
        vim.env.WINDOWS_SETTINGS_THEME_FILE,
        vim.env.HOME_SETTINGS_THEME_FILE,
        cfg_home .. "/windows-settings/active-theme.theme",
        cfg_home .. "/home-settings/active-theme.theme",
    }
    local raw_env_slug = (vim.env.WINDOWS_SETTINGS_THEME and vim.env.WINDOWS_SETTINGS_THEME ~= "")
        and vim.env.WINDOWS_SETTINGS_THEME
        or (vim.env.HOME_SETTINGS_THEME or "")
    local requested_slug = vim.trim(raw_env_slug):lower():gsub("_", "-")
    local parsed = {}
    local found_file = false
    for _, tf in ipairs(theme_files) do
        if tf and tf ~= "" and vim.fn.filereadable(tf) == 1 then
            parsed = parse_theme_file_kv(tf)
            found_file = true
            break
        end
    end
    if not found_file and requested_slug ~= "" then
        local search_dirs = theme_search_dirs(cfg_home)
        for _, dir in ipairs(search_dirs) do
            for _, ext in ipairs({ ".theme", ".conf" }) do
                local candidate = dir .. "/" .. requested_slug .. ext
                if vim.fn.filereadable(candidate) == 1 then
                    parsed = parse_theme_file_kv(candidate)
                    found_file = true
                    break
                end
            end
            if found_file then
                break
            end
        end
        if not found_file then
            for _, dir in ipairs(search_dirs) do
                local files = vim.list_extend(
                    vim.fn.glob(dir .. "/*.theme", false, true),
                    vim.fn.glob(dir .. "/*.conf", false, true)
                )
                table.sort(files)
                for _, f in ipairs(files) do
                    local kv = parse_theme_file_kv(f)
                    local cid = vim.trim(kv.THEME_ID or vim.fn.fnamemodify(f, ":t:r")):lower():gsub("_", "-")
                    if cid == requested_slug then
                        parsed = kv
                        found_file = true
                        break
                    end
                end
                if found_file then
                    break
                end
            end
        end
    end
    local theme_id = (parsed.THEME_ID and parsed.THEME_ID ~= "")
        and parsed.THEME_ID:lower():gsub("_", "-")
        or ((requested_slug ~= "" and found_file) and requested_slug or "solarized-dark")
    local theme_mode = (tostring(parsed.THEME_MODE or ""):lower() == "light") and "light" or "dark"
    vim.g.home_settings_theme = theme_id
    vim.g.windows_settings_theme = theme_id
    vim.g.home_settings_theme_mode = theme_mode
    vim.g.windows_settings_theme_mode = theme_mode
    vim.env.HOME_SETTINGS_THEME = theme_id
    vim.env.WINDOWS_SETTINGS_THEME = theme_id
    vim.env.HOME_SETTINGS_THEME_MODE = theme_mode
    vim.env.WINDOWS_SETTINGS_THEME_MODE = theme_mode
    if parsed.BAT_THEME_NAME and parsed.BAT_THEME_NAME ~= "" then
        vim.env.BAT_THEME = parsed.BAT_THEME_NAME
    end
    local base_defaults = (theme_mode == "light") and default_solarized_light_palette or default_solarized_palette
    local out = vim.tbl_extend("force", {}, base_defaults)
    for env_k, lua_k in pairs(theme_key_map) do
        if is_valid_hex(parsed[env_k]) then
            out[lua_k] = parsed[env_k]:upper()
        end
    end
    if not is_valid_hex(parsed.BASE04) and is_valid_hex(parsed.BASE02) then
        out.base04 = parsed.BASE02:upper()
    end
    return out
end

function M.apply_terminal_ansi_palette(colors)
    vim.g.terminal_color_0 = colors.base02
    vim.g.terminal_color_1 = colors.red
    vim.g.terminal_color_2 = colors.green
    vim.g.terminal_color_3 = colors.yellow
    vim.g.terminal_color_4 = colors.blue
    vim.g.terminal_color_5 = colors.magenta
    vim.g.terminal_color_6 = colors.cyan
    vim.g.terminal_color_7 = colors.base2
    vim.g.terminal_color_8 = colors.base01
    vim.g.terminal_color_9 = colors.orange
    vim.g.terminal_color_10 = colors.base01
    vim.g.terminal_color_11 = colors.base00
    vim.g.terminal_color_12 = colors.base0
    vim.g.terminal_color_13 = colors.violet
    vim.g.terminal_color_14 = colors.base1
    vim.g.terminal_color_15 = colors.base3
end

function M.sync_solarized_plugin_palette(colors)
    local ok, palette_mod = pcall(require, "solarized.palette")
    if ok and type(palette_mod) == "table" and type(palette_mod.solarized) == "table" then
        local sp = palette_mod.solarized
        for k, v in pairs(colors) do
            sp[k] = v
        end
        sp.base4 = colors.base3
        sp.diag_error = colors.red
        sp.diag_warning = colors.yellow
        sp.diag_info = colors.blue
        sp.diag_hint = colors.cyan
        sp.diag_ok = colors.green
        sp.git_add = colors.green
        sp.git_modify = colors.yellow
        sp.git_delete = colors.red
    end
    local ok_light, light_mod = pcall(require, "solarized.palette.solarized-light")
    if ok_light and type(light_mod) == "table" and type(light_mod.solarized) == "table" then
        local lp = light_mod.solarized
        lp.base3 = colors.base03
        lp.base2 = colors.base02
        lp.base4 = colors.base04
        lp.base1 = colors.base01
        lp.base0 = colors.base00
        lp.base00 = colors.base0
        lp.base01 = colors.base1
        lp.base02 = colors.base2
        lp.base03 = colors.base3
        lp.yellow = colors.yellow
        lp.orange = colors.orange
        lp.red = colors.red
        lp.magenta = colors.magenta
        lp.violet = colors.violet
        lp.blue = colors.blue
        lp.cyan = colors.cyan
        lp.green = colors.green
        lp.mix_green = colors.mix_green
        lp.mix_yellow = colors.mix_yellow
        lp.mix_blue = colors.mix_blue
        lp.mix_red = colors.mix_red
        lp.mix_magenta = colors.mix_magenta
        lp.mix_base1 = colors.mix_base1
        lp.mix_base01 = colors.mix_base1
        lp.diag_error = colors.red
        lp.diag_warning = colors.yellow
        lp.diag_info = colors.blue
        lp.diag_hint = colors.cyan
        lp.diag_ok = colors.green
        lp.git_add = colors.green
        lp.git_modify = colors.yellow
        lp.git_delete = colors.red
    end
end

local function complete_theme_names(arg_lead)
    local cfg_home = config_home()
    local ws_themes_norm = vim.fs.normalize(cfg_home .. "/windows-settings/themes"):gsub("/+$", "")
    local seen = {}
    local items = {}
    local function add_item(name)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(items, name)
        end
    end
    local builtin_entries = {}
    local seen_builtin = {}
    for _, bdir in ipairs(builtin_theme_dirs(cfg_home)) do
        local is_ws_shared_dir = (bdir == ws_themes_norm)
        for _, f in ipairs(vim.fn.glob(bdir .. "/*.theme", false, true)) do
            local stem = vim.fn.fnamemodify(f, ":t:r")
            if stem ~= "active-theme" then
                local kv = parse_theme_file_kv(f)
                local slug = vim.trim(kv.THEME_ID or stem):lower():gsub("_", "-")
                local has_builtin_meta = (kv.THEME_ORDER ~= nil and kv.THEME_ORDER ~= "")
                    or (kv.THEME_CATEGORY ~= nil and kv.THEME_CATEGORY ~= "")
                if slug ~= "" and slug ~= "active-theme" and not seen_builtin[slug] and (not is_ws_shared_dir or has_builtin_meta) then
                    seen_builtin[slug] = true
                    local cat = vim.trim(kv.THEME_CATEGORY or ""):lower()
                    if cat == "" then
                        cat = (kv.HOLIDAY_DATE and kv.HOLIDAY_DATE ~= "") and "holiday" or "classic"
                    end
                    local ord = tonumber(kv.THEME_ORDER or "") or 9999
                    table.insert(builtin_entries, {
                        slug = slug,
                        cat_rank = (cat == "holiday") and 1 or 0,
                        ord = ord,
                    })
                end
            end
        end
    end
    table.sort(builtin_entries, function(a, b)
        if a.cat_rank ~= b.cat_rank then
            return a.cat_rank < b.cat_rank
        end
        if a.ord ~= b.ord then
            return a.ord < b.ord
        end
        return a.slug < b.slug
    end)
    if #builtin_entries == 0 then
        add_item("solarized-dark")
    else
        for _, entry in ipairs(builtin_entries) do
            add_item(entry.slug)
        end
    end
    local custom = {}
    for _, dir in ipairs(user_theme_dirs(cfg_home)) do
        local files = vim.list_extend(
            vim.fn.glob(dir .. "/*.theme", false, true),
            vim.fn.glob(dir .. "/*.conf", false, true)
        )
        for _, f in ipairs(files) do
            local stem = vim.fn.fnamemodify(f, ":t:r")
            if stem ~= "active-theme" then
                local kv = parse_theme_file_kv(f)
                local slug = vim.trim(kv.THEME_ID or stem):lower():gsub("_", "-")
                if slug ~= "" and slug ~= "active-theme" and not seen[slug] then
                    seen[slug] = true
                    table.insert(custom, slug)
                end
            end
        end
    end
    table.sort(custom)
    for _, slug in ipairs(custom) do
        table.insert(items, slug)
    end
    add_item("--holiday")
    return vim.tbl_filter(function(item)
        return item:find(arg_lead, 1, true) == 1
    end, items)
end

local function resolve_theme_bin()
    if resolve_cli_bin_fn then
        local resolved = resolve_cli_bin_fn("theme")
        if resolved and resolved ~= "" then
            return resolved
        end
    end
    local exe = vim.fn.exepath("theme")
    if exe ~= "" and vim.fn.executable(exe) == 1 then
        return exe
    end
    local is_win32 = vim.fn.has("win32") == 1
    if repo_root ~= "" then
        if is_win32 and vim.fn.executable(repo_root .. "/bin/theme.cmd") == 1 then
            return repo_root .. "/bin/theme.cmd"
        end
        if vim.fn.executable(repo_root .. "/bin/theme") == 1 then
            return repo_root .. "/bin/theme"
        end
    end
    local home_dir = vim.env.HOME or vim.env.USERPROFILE or vim.fn.expand("~")
    local local_bin = home_dir .. "/.local/bin/theme"
    if vim.fn.executable(local_bin) == 1 then
        return local_bin
    end
    return ""
end

local function run_theme_command(opts)
    local arg = vim.trim(opts.args or "")
    if arg == "" then
        vim.notify("Active theme: " .. tostring(vim.g.home_settings_theme or "solarized-dark"), vim.log.levels.INFO)
        return
    end
    local theme_bin = resolve_theme_bin()
    if theme_bin == "" or vim.fn.executable(theme_bin) ~= 1 then
        vim.notify("Theme executable not found", vim.log.levels.ERROR)
        return
    end
    local cmd = (arg == "--holiday" or arg == "holiday")
        and { theme_bin, "--holiday" }
        or { theme_bin, "--set=" .. arg }
    local prev_skip = vim.env.THEME_SKIP_NVIM_SOCKET
    vim.env.THEME_SKIP_NVIM_SOCKET = vim.v.servername or ""
    local out = vim.fn.system(cmd)
    local rc = vim.v.shell_error
    vim.env.THEME_SKIP_NVIM_SOCKET = prev_skip
    if rc ~= 0 then
        local msg = vim.trim(out or "")
        vim.notify("Theme switch failed: " .. (msg ~= "" and msg or arg), vim.log.levels.ERROR)
        return
    end
    _G.apply_home_settings_theme()
end

function M.solarized_plugin_spec()
    return {
        "maxmx03/solarized.nvim",
        lazy = false,
        priority = 1000,
        opts = {
            variant = "spring",
            transparent = {
                enabled = false,
            },
            styles = {
                comments = { italic = false },
                keywords = { italic = false },
                functions = { bold = false },
                variables = { italic = false },
                parameters = { italic = false },
            },
            on_highlights = function(base_colors, _)
                local colors = M.resolve_active_theme_palette(base_colors)
                M.sync_solarized_plugin_palette(colors)
                return theme_groups.build(colors)
            end,
        },
        config = function(_, opts)
            _G._hs_solarized_opts = opts
            local p = M.resolve_active_theme_palette(nil)
            vim.o.background = (vim.g.home_settings_theme_mode == "light") and "light" or "dark"
            M.sync_solarized_plugin_palette(p)
            require("solarized").setup(opts)
            vim.cmd.colorscheme("solarized")
            M.apply_terminal_ansi_palette(p)
        end,
    }
end

function M.setup(ctx)
    repo_root = (ctx and ctx.repo_root) or ""
    candidate_roots = (ctx and ctx.candidate_roots) or {}
    resolve_cli_bin_fn = (ctx and ctx.resolve_cli_bin) or nil

    _G.apply_home_settings_theme = function()
        local p = M.resolve_active_theme_palette(nil)
        local target_bg = (vim.g.home_settings_theme_mode == "light") and "light" or "dark"
        vim.o.background = target_bg
        M.sync_solarized_plugin_palette(p)
        local applied_via_colorscheme = false
        if package.loaded["solarized"] and _G._hs_solarized_opts then
            applied_via_colorscheme = pcall(function()
                require("solarized").setup(_G._hs_solarized_opts)
                vim.cmd.colorscheme("solarized")
            end)
        end
        if not applied_via_colorscheme then
            local hl = theme_groups.build(p)
            for group, spec in pairs(hl) do
                pcall(vim.api.nvim_set_hl, 0, group, spec)
            end
        end
        M.apply_terminal_ansi_palette(p)
        return vim.g.home_settings_theme or "solarized-dark"
    end
    _G.apply_windows_settings_theme = _G.apply_home_settings_theme

    local initial_palette = M.resolve_active_theme_palette(nil)
    vim.o.background = (vim.g.home_settings_theme_mode == "light") and "light" or "dark"
    M.apply_terminal_ansi_palette(initial_palette)

    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("SolarizedTerminalAnsiPalette", { clear = true }),
        pattern = "solarized",
        callback = function()
            M.apply_terminal_ansi_palette(M.resolve_active_theme_palette(nil))
        end,
    })

    vim.api.nvim_create_user_command("Theme", run_theme_command, {
        nargs = "?",
        complete = complete_theme_names,
        desc = "Switch or inspect active windows-settings color theme",
    })
end

return M
