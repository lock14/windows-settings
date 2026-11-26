-- Live buffer reloading, Win32-safe stale working directory recovery, and Markdown prose readability autocmds.

local M = {}

local is_win32 = vim.fn.has("win32") == 1

local function is_abs_path(p)
    if type(p) ~= "string" or p == "" then
        return false
    end
    return p:match("^/") ~= nil or p:match("^%a:[/\\]") ~= nil or p:match("^\\\\") ~= nil
end

local function same_dir_stat(p1, s1, p2, s2)
    if not s1 or not s2 then
        return false
    end
    if not is_win32 and s1.ino and s2.ino and s1.ino ~= 0 and s2.ino ~= 0 then
        return s1.dev == s2.dev and s1.ino == s2.ino
    end
    if type(p1) == "string" and type(p2) == "string" and p1 ~= "" and p2 ~= "" then
        if is_win32 then
            return vim.fs.normalize(p1):lower() == vim.fs.normalize(p2):lower()
        end
        return vim.fs.normalize(p1) == vim.fs.normalize(p2)
    end
    return false
end

M.is_abs_path = is_abs_path
M.same_dir_stat = same_dir_stat

function M.recover_stale_cwd()
    local uv = vim.uv or vim.loop
    if not uv then
        return
    end
    local pwd = nil
    for _, cand in ipairs({ vim.env.PWD or "", vim.env.IDE_WORKDIR or "", vim.env.IDE_INITIAL_ROOT or "" }) do
        if cand and cand ~= "" and vim.fn.isdirectory(cand) == 1 then
            pwd = cand
            break
        end
    end
    if pwd then
        local cur_cwd = uv.cwd()
        local s_dot = uv.fs_stat(".")
        local s_pwd = uv.fs_stat(pwd)
        local deleted_dir = (not is_win32) and (not s_dot or s_dot.nlink == 0)
        if
            not cur_cwd
            or not s_dot
            or deleted_dir
            or (
                vim.fn.haslocaldir() == 0
                and vim.fn.haslocaldir(-1, 0) == 0
                and s_pwd
                and not same_dir_stat(cur_cwd, s_dot, pwd, s_pwd)
            )
        then
            pcall(vim.fn.chdir, pwd)
            vim.env.PWD = pwd
        end
    end
end

local function wrap_fs_abspath()
    if vim.fs and type(vim.fs.abspath) == "function" and not vim.fs._hs_abspath_wrapped then
        local orig_abspath = vim.fs.abspath
        vim.fs._hs_abspath_wrapped = true
        vim.fs.abspath = function(path)
            local ok, res = pcall(orig_abspath, path)
            if ok then
                return res
            end
            M.recover_stale_cwd()
            ok, res = pcall(orig_abspath, path)
            if ok then
                return res
            end
            if type(path) ~= "string" then
                error(res, 2)
            end
            local home_dir = vim.env.HOME or vim.env.USERPROFILE or "~"
            local expanded = path:gsub("^~", home_dir)
            if is_abs_path(expanded) then
                return vim.fs.normalize(expanded)
            end
            local default_root = (home_dir ~= "~") and home_dir or (is_win32 and ((vim.env.SystemDrive or "C:") .. "/") or "/")
            local fb = (vim.env.PWD and is_abs_path(vim.env.PWD)) and vim.env.PWD
                or (vim.env.IDE_WORKDIR and is_abs_path(vim.env.IDE_WORKDIR)) and vim.env.IDE_WORKDIR
                or (vim.env.IDE_INITIAL_ROOT and is_abs_path(vim.env.IDE_INITIAL_ROOT)) and vim.env.IDE_INITIAL_ROOT
                or default_root
            if expanded == "." or expanded == "" then
                return vim.fs.normalize(fb)
            end
            return vim.fs.normalize(vim.fs.joinpath(fb, expanded))
        end
    end
end

function M.setup(opts)
    local follow_editor_link = opts and opts.follow_editor_link or nil

    M.recover_stale_cwd()
    local uv = vim.uv or vim.loop
    if uv then
        local init_cwd = uv.cwd()
        local s_dot = uv.fs_stat(".")
        local cur_pwd = vim.env.PWD
        local s_pwd = (cur_pwd and cur_pwd ~= "") and uv.fs_stat(cur_pwd) or nil
        if
            init_cwd
            and init_cwd ~= ""
            and s_dot
            and (is_win32 or s_dot.nlink ~= 0)
            and not same_dir_stat(init_cwd, s_dot, cur_pwd, s_pwd)
        then
            vim.env.PWD = init_cwd
        end
    end
    wrap_fs_abspath()

    local autoread_group = vim.api.nvim_create_augroup("SolarizedAutoRead", { clear = true })
    vim.api.nvim_create_autocmd("DirChanged", {
        group = autoread_group,
        pattern = "global",
        callback = function(ev)
            if ev.file and ev.file ~= "" then
                local cur_uv = vim.uv or vim.loop
                local cur_pwd = vim.env.PWD
                local s_cur = (cur_uv and cur_pwd and cur_pwd ~= "") and cur_uv.fs_stat(cur_pwd) or nil
                local s_ev = cur_uv and cur_uv.fs_stat(ev.file) or nil
                if not same_dir_stat(cur_pwd, s_cur, ev.file, s_ev) then
                    vim.env.PWD = ev.file
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufReadPre", "FileType" }, {
        group = autoread_group,
        callback = function()
            M.recover_stale_cwd()
        end,
    })
    vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
        group = autoread_group,
        callback = function()
            M.recover_stale_cwd()
            if vim.fn.getcmdwintype() == "" then
                pcall(vim.cmd, "silent! checktime")
            end
        end,
    })

    -- Word-boundary soft-wrapping, zero buffer-line scrolloff snapback, and conceal-aware link navigation for Markdown
    local md_group = vim.api.nvim_create_augroup("SolarizedMarkdownReadability", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
        group = md_group,
        pattern = { "markdown" },
        callback = function(ev)
            vim.opt_local.wrap = true
            vim.opt_local.linebreak = true
            vim.opt_local.breakindent = true
            vim.opt_local.scrolloff = 0
            vim.w._hs_md_scrolloff = true
            local buf = (ev and ev.buf) or true
            vim.keymap.set({ "n", "x" }, "j", function()
                return vim.v.count == 0 and "gj" or "j"
            end, { buffer = buf, expr = true, silent = true, desc = "Move down by screen line in soft-wrapped Markdown" })
            vim.keymap.set({ "n", "x" }, "k", function()
                return vim.v.count == 0 and "gk" or "k"
            end, { buffer = buf, expr = true, silent = true, desc = "Move up by screen line in soft-wrapped Markdown" })
            vim.keymap.set("n", "<CR>", function()
                if not (follow_editor_link and follow_editor_link(false, false)) then
                    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
                end
            end, { buffer = buf, silent = true, desc = "Follow Markdown link under cursor" })
            vim.keymap.set("n", "gd", function()
                if not (follow_editor_link and follow_editor_link(false, true)) then
                    vim.lsp.buf.definition()
                end
            end, { buffer = buf, silent = true, desc = "Follow Markdown link or LSP definition" })
        end,
    })
    vim.api.nvim_create_autocmd("BufWinEnter", {
        group = md_group,
        callback = function(ev)
            local ft = (ev and ev.buf and vim.api.nvim_buf_is_valid(ev.buf)) and vim.bo[ev.buf].filetype or vim.bo.filetype
            if ft == "markdown" then
                vim.opt_local.wrap = true
                vim.opt_local.linebreak = true
                vim.opt_local.breakindent = true
                vim.opt_local.scrolloff = 0
                vim.w._hs_md_scrolloff = true
            elseif vim.w._hs_md_scrolloff then
                vim.w._hs_md_scrolloff = nil
                vim.opt_local.scrolloff = -1
            end
        end,
    })
end

return M
