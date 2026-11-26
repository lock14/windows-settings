-- Hybrid IDE workspace integration (Zellij 0.46+, Windows Terminal fallback, Tmux):
-- pane focus/parking/swapping, fleet session switcher, focus-preserving AI context staging,
-- self-healing Named Pipe RPC server binding, workspace directory dive (:IdeCd), and workspace quit (:Q / :Quit).

local M = {}

local is_win32 = vim.fn.has("win32") == 1
local unpack_fn = table.unpack or unpack
local resolve_cli_bin_fn = nil

local function resolve_ide_bin()
    if resolve_cli_bin_fn then
        local resolved = resolve_cli_bin_fn("ide")
        if resolved and resolved ~= "" then
            return resolved
        end
    end
    local exe = vim.fn.exepath("ide")
    if exe ~= "" and vim.fn.executable(exe) == 1 then
        return exe
    end
    local home_dir = vim.env.HOME or vim.env.USERPROFILE or vim.fn.expand("~")
    local local_bin = home_dir .. "/.local/bin/ide"
    if vim.fn.executable(local_bin) == 1 then
        return local_bin
    end
    return ""
end

function M.in_ide_workspace()
    return (vim.env.TMUX ~= nil and vim.env.TMUX ~= "")
        or (vim.env.ZELLIJ ~= nil and vim.env.ZELLIJ ~= "")
        or (vim.env.IDE_SESSION ~= nil and vim.env.IDE_SESSION ~= "")
        or (vim.env.NVIM_IDE_SOCKET ~= nil and vim.env.NVIM_IDE_SOCKET ~= "")
end

-- Runs `ide` for this Editor's own workspace, naming $IDE_SESSION explicitly when set so `ide`
-- never guesses a session.
function M.ide_job(...)
    local ide_bin = resolve_ide_bin()
    if ide_bin == "" then
        return
    end
    local cmd = { ide_bin, ... }
    local sess = vim.env.IDE_SESSION
    if sess and sess ~= "" then
        table.insert(cmd, sess)
    end
    vim.fn.jobstart(cmd, { detach = true })
end

local function ide_action(...)
    local args = { ... }
    return function()
        if M.in_ide_workspace() then
            M.ide_job(unpack_fn(args))
        end
    end
end

local function ide_modal_launcher(modal_name, fallback_subcmd)
    return function()
        if not M.in_ide_workspace() then
            return
        end
        local ide_bin = resolve_ide_bin()
        if ide_bin == "" then
            return
        end
        local sess = vim.env.IDE_SESSION
        local opts = { detach = true }
        if sess and sess ~= "" then
            opts.env = { IDE_ORIGIN_SESSION = sess }
        end
        if (vim.env.ZELLIJ or "") ~= "" then
            vim.fn.jobstart({ ide_bin, "_internal", "toggle-modal", modal_name }, opts)
        elseif fallback_subcmd == "switch" and (vim.env.TMUX or "") ~= "" then
            M.ide_job("switch")
        else
            vim.fn.jobstart({ ide_bin, fallback_subcmd }, opts)
        end
    end
end

local function send_to_ai_pane(kind, payload, opts)
    opts = opts or {}
    if not payload or payload == "" then
        return false
    end
    local ide_bin = resolve_ide_bin()
    local target = vim.trim(opts.target or "")
    if target == "" then
        target = vim.env.IDE_SESSION or ""
    end
    if ide_bin ~= "" and (M.in_ide_workspace() or (opts.target and vim.trim(opts.target) ~= "")) then
        local cmd = { ide_bin, "send" }
        local use_stdin = false
        if kind == "ref" then
            table.insert(cmd, "--ref")
            table.insert(cmd, payload)
        elseif opts.use_text and not is_win32 and not payload:find("[\r\n]") then
            table.insert(cmd, "--text")
            table.insert(cmd, payload)
        else
            table.insert(cmd, "--stdin")
            use_stdin = true
        end
        if opts.mode_flag and opts.mode_flag ~= "" then
            table.insert(cmd, opts.mode_flag)
        end
        if target ~= "" then
            table.insert(cmd, target)
        end
        local jid = vim.fn.jobstart(cmd, { detach = true })
        if use_stdin and type(jid) == "number" and jid > 0 then
            pcall(vim.fn.chansend, jid, payload)
            pcall(vim.fn.chanclose, jid, "stdin")
        end
        if opts.notify_msg then
            vim.notify(opts.notify_msg, vim.log.levels.INFO)
        end
        return true
    end
    pcall(vim.fn.setreg, "+", payload)
    if opts.fallback_msg then
        vim.notify(opts.fallback_msg, vim.log.levels.INFO)
    end
    return false
end

M.send_to_ai_pane = send_to_ai_pane

local function send_visual_to_ai(no_focus)
    local cur_mode = vim.fn.mode()
    local in_visual = (cur_mode == "v" or cur_mode == "V" or cur_mode == "\22")
    local v1, v2
    if in_visual then
        v1 = vim.fn.line("v")
        v2 = vim.fn.line(".")
    else
        v1 = vim.fn.line("'<")
        v2 = vim.fn.line("'>")
        if v1 == 0 or v2 == 0 then
            v1 = vim.fn.line(".")
            v2 = v1
        end
    end
    local l1 = math.min(v1, v2)
    local l2 = math.max(v1, v2)
    local buf_name = vim.api.nvim_buf_get_name(0)
    local is_file_buf = (vim.bo.buftype == "" and buf_name ~= "")
    local region_lines = nil
    if not is_file_buf then
        if in_visual and vim.fn.getregion then
            local ok, reg = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = cur_mode })
            if ok and reg and #reg > 0 then
                region_lines = reg
            end
        end
        if not region_lines then
            region_lines = vim.api.nvim_buf_get_lines(0, math.max(0, l1 - 1), l2, false)
        end
    end
    if in_visual then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    end
    if is_file_buf then
        local buf_path = vim.fn.fnamemodify(buf_name, ":p")
        local rel_lbl = vim.fn.fnamemodify(buf_name, ":.")
        local range_lbl = (l1 == l2) and string.format("#L%d", l1) or string.format("#L%d-L%d", l1, l2)
        local ref = string.format("%s:%d-%d", buf_path, l1, l2)
        send_to_ai_pane("ref", ref, {
            mode_flag = no_focus and "--no-focus" or nil,
            notify_msg = no_focus and string.format("Staged @%s%s in AI prompt", rel_lbl, range_lbl) or nil,
            fallback_msg = "Copied reference to clipboard: " .. ref,
        })
    elseif region_lines then
        local text = table.concat(region_lines, "\n")
        if text ~= "" then
            send_to_ai_pane("text", text, {
                mode_flag = no_focus and "--no-focus" or nil,
                notify_msg = no_focus and "Staged selection in AI prompt" or nil,
                fallback_msg = "Copied selection to clipboard",
            })
        end
    end
end

local function send_file_to_ai(no_focus)
    local buf_name = vim.api.nvim_buf_get_name(0)
    if vim.bo.buftype == "" and buf_name ~= "" then
        local buf_path = vim.fn.fnamemodify(buf_name, ":p")
        local rel_lbl = vim.fn.fnamemodify(buf_name, ":.")
        send_to_ai_pane("ref", buf_path, {
            mode_flag = no_focus and "--no-focus" or nil,
            notify_msg = no_focus and string.format("Staged @%s in AI prompt", rel_lbl) or nil,
            fallback_msg = "Copied file reference to clipboard: " .. buf_path,
        })
    else
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local text = table.concat(lines, "\n")
        if text ~= "" then
            send_to_ai_pane("text", text, {
                mode_flag = no_focus and "--no-focus" or nil,
                notify_msg = no_focus and "Staged buffer text in AI prompt" or nil,
                fallback_msg = "Copied buffer text to clipboard",
            })
        end
    end
end

local function send_line_to_ai()
    local buf_name = vim.api.nvim_buf_get_name(0)
    if vim.bo.buftype == "" and buf_name ~= "" then
        local buf_path = vim.fn.fnamemodify(buf_name, ":p")
        local ref = string.format("%s:%d", buf_path, vim.fn.line("."))
        send_to_ai_pane("ref", ref, {
            fallback_msg = "Copied line reference to clipboard: " .. ref,
        })
    else
        local line_text = vim.api.nvim_get_current_line()
        if line_text ~= "" then
            send_to_ai_pane("text", line_text, {
                fallback_msg = "Copied line to clipboard",
            })
        end
    end
end

local function send_diagnostics_to_ai()
    local diags = vim.diagnostic.get(0)
    if not diags or #diags == 0 then
        vim.notify("No diagnostics in current buffer", vim.log.levels.INFO)
        return
    end
    table.sort(diags, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        return (a.col or 0) < (b.col or 0)
    end)
    local sev_names = {
        [vim.diagnostic.severity.ERROR] = "ERROR",
        [vim.diagnostic.severity.WARN] = "WARN",
        [vim.diagnostic.severity.INFO] = "INFO",
        [vim.diagnostic.severity.HINT] = "HINT",
    }
    local buf_name = vim.api.nvim_buf_get_name(0)
    local header_path = (buf_name ~= "") and vim.fn.fnamemodify(buf_name, ":.") or "[No Name]"
    local out = { string.format("Diagnostics in %s:", header_path) }
    for _, d in ipairs(diags) do
        local sev = sev_names[d.severity] or "DIAG"
        local msg = tostring(d.message or ""):gsub("%s*\n%s*", " ")
        table.insert(out, string.format("- [%s] L%d:%d: %s", sev, (d.lnum or 0) + 1, (d.col or 0) + 1, msg))
    end
    local payload = table.concat(out, "\n") .. "\n"
    send_to_ai_pane("text", payload, {
        fallback_msg = "Copied buffer diagnostics to clipboard",
    })
end

local function tmux_dquote(s)
    return '"'
        .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%$", "\\$"):gsub("#", "##")
        .. '"'
end

local function open_ide_keys_popup()
    local ide_bin = resolve_ide_bin()
    if ide_bin == "" then
        return
    end
    if (vim.env.ZELLIJ or "") ~= "" then
        local opts = { detach = true }
        local sess = vim.env.IDE_SESSION
        if sess and sess ~= "" then
            opts.env = { IDE_ORIGIN_SESSION = sess }
        end
        vim.fn.jobstart({ ide_bin, "_internal", "toggle-modal", "keys" }, opts)
        return
    elseif (vim.env.TMUX or "") ~= "" then
        local pane = vim.env.TMUX_PANE or ""
        local t_flag = (pane ~= "") and ("-t " .. tmux_dquote(pane) .. " ") or ""
        local sh_cmd = vim.fn.shellescape(ide_bin) .. " keys"
        local sh_q = tmux_dquote(sh_cmd)
        local p_wide_tall = "display-popup " .. t_flag .. "-E -w 108 -h 34 " .. sh_q
        local p_wide_fit = "display-popup " .. t_flag .. "-E -w 108 -h 100% " .. sh_q
        local p_fit_tall = "display-popup " .. t_flag .. "-E -w 100% -h 34 " .. sh_q
        local p_fit_fit = "display-popup " .. t_flag .. "-E -w 100% -h 100% " .. sh_q
        local cmd = { "tmux", "if-shell" }
        if pane ~= "" then
            table.insert(cmd, "-t")
            table.insert(cmd, pane)
        end
        vim.list_extend(cmd, {
            "-F",
            "#{e|>=:#{client_width},108}",
            string.format(
                'if-shell %s-F "#{e|>=:#{client_height},34}" %s %s',
                t_flag,
                tmux_dquote(p_wide_tall),
                tmux_dquote(p_wide_fit)
            ),
            string.format(
                'if-shell %s-F "#{e|>=:#{client_height},34}" %s %s',
                t_flag,
                tmux_dquote(p_fit_tall),
                tmux_dquote(p_fit_fit)
            ),
        })
        vim.fn.jobstart(cmd, { detach = true })
        return
    end

    -- Floating Neovim terminal fallback (`--backend wt` or standalone editor)
    local buf = vim.api.nvim_create_buf(false, true)
    local w = math.min(96, math.max(60, vim.o.columns - 6))
    local h = math.min(32, math.max(16, vim.o.lines - 4))
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = w,
        height = h,
        row = math.max(0, math.floor((vim.o.lines - h) / 2)),
        col = math.max(0, math.floor((vim.o.columns - w) / 2)),
        style = "minimal",
        border = "rounded",
        title = " IDE Keybindings (press q or Esc to close) ",
        title_pos = "center",
    })
    vim.fn.termopen({ ide_bin, "keys" })
    vim.keymap.set({ "n", "t" }, "q", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, silent = true })
    vim.keymap.set({ "n", "t" }, "<Esc>", function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, { buffer = buf, silent = true })
end

local function count_real_modified_buffers()
    local cnt = 0
    for _, b in ipairs(vim.fn.getbufinfo({ bufmodified = 1 })) do
        local bt = vim.bo[b.bufnr].buftype
        if bt == "" then
            if b.name and b.name ~= "" then
                cnt = cnt + 1
            else
                local lines = vim.api.nvim_buf_get_lines(b.bufnr, 0, -1, false)
                local text = table.concat(lines, ""):gsub("%s+", "")
                if text ~= "" then
                    cnt = cnt + 1
                end
            end
        end
    end
    return cnt
end

local function try_ide_quit(force)
    if not force then
        local modified = count_real_modified_buffers()
        if modified > 0 then
            vim.schedule(function()
                local msg = string.format("E37: %d unsaved buffer(s) (:wa to save or Alt+Shift+Q to force)", modified)
                local max_w = math.max(16, (vim.o.columns or 80) - 14)
                if #msg > max_w then
                    msg = msg:sub(1, max_w - 1) .. "…"
                end
                vim.api.nvim_echo({ { msg, "ErrorMsg" } }, false, {})
            end)
            return modified
        end
    end
    vim.schedule(function()
        vim.cmd("qa!")
    end)
    return 0
end

local function quit_ide_or_nvim(force, target_sessions)
    local targets = target_sessions or {}
    local ide_bin = resolve_ide_bin()
    if M.in_ide_workspace() and ide_bin ~= "" then
        local cur_sess = vim.env.IDE_SESSION or ""
        local checks_local = (#targets == 0)
        if not checks_local and cur_sess ~= "" then
            for _, t in ipairs(targets) do
                if t == cur_sess then
                    checks_local = true
                    break
                end
            end
        end
        if not force and checks_local then
            local modified = count_real_modified_buffers()
            if modified > 0 then
                vim.api.nvim_echo({
                    {
                        "E37: No write since last change in "
                            .. modified
                            .. " buffer(s) (save with :wa or press Alt+Shift+Q / :Q! to force)",
                        "ErrorMsg",
                    },
                }, true, {})
                return
            end
        end
        if #targets == 0 then
            vim.schedule(function()
                vim.cmd("qa!")
            end)
            M.ide_job("quit", "--force")
        else
            local cmd = { ide_bin, "quit" }
            if force then
                table.insert(cmd, "--force")
            end
            for _, t in ipairs(targets) do
                table.insert(cmd, t)
            end
            vim.fn.jobstart(cmd, { detach = true })
            if checks_local and (vim.env.TMUX or "") == "" and (vim.env.ZELLIJ or "") == "" then
                vim.schedule(function()
                    vim.cmd("qa!")
                end)
            end
        end
    else
        vim.cmd(force and "qa!" or "confirm qa")
    end
end

local function complete_ide_sessions(arg_lead)
    local ide_bin = resolve_ide_bin()
    if ide_bin == "" then
        return {}
    end
    local lines = vim.fn.systemlist({ ide_bin, "list", "--plain" })
    if vim.v.shell_error ~= 0 then
        return {}
    end
    local matches = {}
    for _, s in ipairs(lines) do
        local trimmed = vim.trim(s)
        if trimmed ~= "" and trimmed:find(arg_lead, 1, true) == 1 then
            table.insert(matches, trimmed)
        end
    end
    return matches
end

local function run_ide_cd(opts)
    local target = vim.trim(opts.args or "")
    local resolved
    if target == "" then
        local buf_dir = vim.fn.expand("%:p:h")
        if buf_dir ~= "" and vim.fn.isdirectory(buf_dir) == 1 then
            resolved = buf_dir
        else
            resolved = vim.fn.getcwd()
        end
    elseif target == "~" or target == "--reset" then
        resolved = vim.env.IDE_INITIAL_ROOT or vim.fn.getcwd()
    else
        resolved = vim.fn.fnamemodify(vim.fn.expand(target), ":p"):gsub("[/\\]+$", "")
        if resolved:match("^%a:$") then
            resolved = resolved .. (is_win32 and "\\" or "/")
        end
    end
    if resolved == "" then
        resolved = is_win32 and ((vim.env.SystemDrive or "C:") .. "\\") or "/"
    end
    if vim.fn.isdirectory(resolved) ~= 1 then
        vim.notify("IdeCd: not a directory: " .. tostring(target), vim.log.levels.WARN)
        return
    end
    pcall(vim.cmd, "cd " .. vim.fn.fnameescape(resolved))
    if M.in_ide_workspace() then
        M.ide_job("cd", resolved)
    end
end

local function run_ide_send(opts)
    local mode_flag = opts.bang and "--switch" or "--no-focus"
    local l1 = math.min(opts.line1 or vim.fn.line("."), opts.line2 or vim.fn.line("."))
    local l2 = math.max(opts.line1 or vim.fn.line("."), opts.line2 or vim.fn.line("."))
    local has_range = (opts.range or 0) > 0
    local buf_name = vim.api.nvim_buf_get_name(0)
    if vim.bo.buftype == "" and buf_name ~= "" then
        local buf_path = vim.fn.fnamemodify(buf_name, ":p")
        local ref = has_range and string.format("%s:%d-%d", buf_path, l1, l2) or string.format("%s:%d", buf_path, l1)
        send_to_ai_pane("ref", ref, {
            target = opts.args,
            mode_flag = mode_flag,
            fallback_msg = "Copied reference to clipboard: " .. ref,
        })
    else
        local lines = vim.api.nvim_buf_get_lines(0, math.max(0, l1 - 1), l2, false)
        local text = table.concat(lines, "\n")
        if text == "" then
            return
        end
        send_to_ai_pane("text", text, {
            target = opts.args,
            mode_flag = mode_flag,
            fallback_msg = "Copied selection to clipboard",
        })
    end
end

-- Self-healing Named Pipe / RPC socket binding (`SolarizedIdeSocket`):
-- When Neovim is restarted manually inside the IDE Editor pane (`nvim`, `vim`, `vi`),
-- verify non-nested Editor pane identity (`IDE_ROLE == "editor"` + optional `.pane-editor` sidecar)
-- and asynchronously probe `NVIM_IDE_SOCKET` via libuv `new_pipe(false):connect` before calling
-- `serverstart` — NEVER calling `fs_unlink` on `\\.\pipe\...` Named Pipes.
M._socket_probe_state = "idle"

local function is_named_pipe_path(p)
    if type(p) ~= "string" then
        return false
    end
    return p:match("^\\\\%.\\pipe\\") ~= nil or p:match("^//%./pipe/") ~= nil
end

local function same_server_addr(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then
        return false
    end
    if is_win32 or is_named_pipe_path(a) or is_named_pipe_path(b) then
        return a:gsub("/", "\\"):lower() == b:gsub("/", "\\"):lower()
    end
    return a == b
end

local function normalize_zellij_pane_id(raw)
    local s = vim.trim(tostring(raw or "")):lower()
    s = s:gsub("^terminal_", "")
    return s
end

local function find_editor_pane_sidecar(ide_sess)
    if not ide_sess or ide_sess == "" then
        return nil
    end
    local home_dir = vim.env.HOME or vim.env.USERPROFILE or vim.fn.expand("~")
    local candidates = {}
    if vim.env.XDG_CACHE_HOME and vim.env.XDG_CACHE_HOME ~= "" then
        table.insert(candidates, vim.env.XDG_CACHE_HOME .. "/windows-settings/ide/" .. ide_sess .. ".pane-editor")
    end
    if home_dir and home_dir ~= "" then
        table.insert(candidates, home_dir .. "/.cache/windows-settings/ide/" .. ide_sess .. ".pane-editor")
    end
    for _, cand in ipairs(candidates) do
        if vim.fn.filereadable(cand) == 1 then
            return cand
        end
    end
    return nil
end

local function is_listening_on_socket(sock, uv)
    local named_pipe = is_named_pipe_path(sock)
    for _, srv in ipairs(vim.fn.serverlist()) do
        if same_server_addr(srv, sock) then
            if named_pipe or not uv or uv.fs_stat(sock) then
                return true
            end
            pcall(vim.fn.serverstop, srv)
            break
        end
    end
    return false
end

local function maybe_bind_editor_ide_socket()
    if #vim.api.nvim_list_uis() == 0 then
        M._socket_probe_state = "skipped_headless"
        return
    end
    if (vim.env.NVIM or "") ~= "" then
        M._socket_probe_state = "skipped_nested_env"
        return
    end
    if (vim.env.IDE_ROLE or "") ~= "editor" then
        M._socket_probe_state = "skipped_non_editor"
        return
    end
    local env_sock = vim.trim(vim.env.NVIM_IDE_SOCKET or "")
    if env_sock == "" then
        M._socket_probe_state = "skipped_no_sock"
        return
    end

    local zj_pane = vim.trim(vim.env.ZELLIJ_PANE_ID or "")
    local ide_sess = vim.trim(vim.env.IDE_SESSION or "")
    if zj_pane ~= "" and ide_sess ~= "" then
        local sidecar = find_editor_pane_sidecar(ide_sess)
        if sidecar then
            local lines = vim.fn.readfile(sidecar, "", 1)
            local expected = normalize_zellij_pane_id(lines and lines[1] or "")
            if expected ~= "" and normalize_zellij_pane_id(zj_pane) ~= expected then
                M._socket_probe_state = "skipped_pane_mismatch"
                return
            end
        end
    end

    local uv = vim.uv or vim.loop
    if is_listening_on_socket(env_sock, uv) then
        M._socket_probe_state = "already_listening"
        return
    end

    if not (uv and uv.new_pipe) then
        M._socket_probe_state = "skipped_no_pipe"
        return
    end

    local pipe = uv.new_pipe(false)
    if not pipe then
        M._socket_probe_state = "skipped_no_pipe"
        return
    end

    M._socket_probe_state = "running"
    pipe:connect(env_sock, function(err)
        pcall(function()
            if not pipe:is_closing() then
                pipe:close()
            end
        end)
        if err then
            vim.schedule(function()
                if vim.v.exiting ~= vim.NIL then
                    M._socket_probe_state = "exiting"
                    return
                end
                if is_listening_on_socket(env_sock, uv) then
                    M._socket_probe_state = "already_listening"
                    return
                end
                if not is_named_pipe_path(env_sock) then
                    local parent = vim.fn.fnamemodify(env_sock, ":h")
                    if parent ~= "" and vim.fn.isdirectory(parent) == 0 then
                        pcall(vim.fn.mkdir, parent, "p", "0700")
                    end
                    if uv.fs_stat and uv.fs_stat(env_sock) and uv.fs_unlink then
                        pcall(uv.fs_unlink, env_sock)
                    end
                end
                local ok, started = pcall(vim.fn.serverstart, env_sock)
                if ok and type(started) == "string" and started ~= "" then
                    vim.env.NVIM_IDE_SOCKET = started
                    M._socket_probe_state = "bound"
                else
                    M._socket_probe_state = "bind_failed"
                end
            end)
        else
            M._socket_probe_state = "live_peer"
        end
    end)
end

M.maybe_bind_editor_ide_socket = maybe_bind_editor_ide_socket

function M.setup(ctx)
    resolve_cli_bin_fn = ctx and ctx.resolve_cli_bin or nil
    _G.count_ide_modified_buffers = count_real_modified_buffers
    _G.try_ide_quit = try_ide_quit

    local map = vim.keymap.set
    local sock_group = vim.api.nvim_create_augroup("SolarizedIdeSocket", { clear = true })
    if vim.v.vim_did_enter == 1 then
        maybe_bind_editor_ide_socket()
    else
        vim.api.nvim_create_autocmd("VimEnter", {
            group = sock_group,
            once = true,
            callback = maybe_bind_editor_ide_socket,
        })
    end

    -- Role focus, visibility parking, directional swaps, fleet switcher, and context dispatch
    map("n", "<leader>a", ide_action("_internal", "toggle"), { desc = "Toggle Focus: Editor <-> AI Agent" })
    map("n", "<leader>t", ide_action("_internal", "focus", "term"), { desc = "Toggle Focus: Editor <-> Shell" })
    map("x", "<leader>a", function()
        send_visual_to_ai(false)
    end, { desc = "Send Visual Selection Reference to AI Agent" })
    map("x", "<leader>A", function()
        send_visual_to_ai(true)
    end, { desc = "Stage Visual Selection Reference in AI Prompt (Keep Focus)" })
    map("n", "<leader>il", send_line_to_ai, { desc = "Send Current Line Reference to AI Agent" })
    map("n", "<leader>if", function()
        send_file_to_ai(false)
    end, { desc = "Send Current File Reference to AI Agent" })
    map("n", "<leader>ia", function()
        send_file_to_ai(true)
    end, { desc = "Stage Current File Reference in AI Prompt (Keep Focus)" })
    map("n", "<leader>id", send_diagnostics_to_ai, { desc = "Send Buffer Diagnostics to AI Agent" })

    map({ "n", "i", "v", "t" }, "<M-a>", ide_action("_internal", "toggle"), { desc = "Toggle Focus: Editor <-> AI Agent" })
    map({ "n", "i", "v", "t" }, "<M-e>", ide_action("_internal", "focus", "editor"), { desc = "Focus Editor Pane (or bounce back)" })
    map({ "n", "i", "v", "t" }, "<M-t>", ide_action("_internal", "focus", "term"), { desc = "Toggle Focus: Shell <-> Editor Pane" })
    map({ "n", "i", "v", "t" }, "<M-A>", ide_action("_internal", "park", "ai"), { desc = "Toggle AI Agent Pane Visibility" })
    map({ "n", "i", "v", "t" }, "<M-E>", ide_action("_internal", "park", "editor"), { desc = "Toggle Editor Pane Visibility" })
    map({ "n", "i", "v", "t" }, "<M-T>", ide_action("_internal", "park", "term"), { desc = "Toggle Shell Pane Visibility" })

    map({ "n", "i", "v", "t" }, "<M-H>", ide_action("_internal", "swap", "left"), { desc = "Swap Active Pane Left" })
    map({ "n", "i", "v", "t" }, "<M-J>", ide_action("_internal", "swap", "down"), { desc = "Swap Active Pane Down" })
    map({ "n", "i", "v", "t" }, "<M-K>", ide_action("_internal", "swap", "up"), { desc = "Swap Active Pane Up" })
    map({ "n", "i", "v", "t" }, "<M-L>", ide_action("_internal", "swap", "right"), { desc = "Swap Active Pane Right" })

    local open_ide_sessions_popup = ide_modal_launcher("sessions", "switch")
    local open_ide_new_popup = ide_modal_launcher("new", "new")
    local open_ide_dir_popup = ide_modal_launcher("dir", "dir")
    map("n", "<leader>s", open_ide_sessions_popup, { desc = "Switch IDE Workspace Session" })
    map({ "n", "i", "v", "t" }, "<M-s>", open_ide_sessions_popup, { desc = "Switch IDE Workspace Session" })
    map("n", "<leader>n", open_ide_new_popup, { desc = "Create New IDE Workspace" })
    map({ "n", "i", "v", "t" }, "<M-n>", open_ide_new_popup, { desc = "Create New IDE Workspace" })
    map("n", "<leader>o", open_ide_dir_popup, { desc = "Open Existing Workspace Directory" })
    map({ "n", "i", "v", "t" }, "<M-o>", open_ide_dir_popup, { desc = "Open Existing Workspace Directory" })
    map({ "n", "i", "v", "t" }, "<M-S>", ide_action("next"), { desc = "Jump to Next Attention AI Agent" })

    map("n", "<leader>?", open_ide_keys_popup, { desc = "Open IDE Keybinding Cheatsheet" })
    map({ "n", "i", "v", "t" }, "<M-?>", open_ide_keys_popup, { desc = "Open IDE Keybinding Cheatsheet" })

    -- One-command workspace termination while keeping native :q/:wq/:qa/:wqa untouched
    map("n", "<leader>q", function()
        quit_ide_or_nvim(false)
    end, { desc = "Quit Entire IDE Workspace" })
    map({ "n", "i", "v", "t" }, "<M-q>", function()
        quit_ide_or_nvim(false)
    end, { desc = "Quit Entire IDE Workspace" })
    map({ "n", "i", "v", "t" }, "<M-Q>", function()
        quit_ide_or_nvim(true)
    end, { desc = "Force-Quit Entire IDE Workspace" })

    vim.api.nvim_create_user_command("Q", function(opts)
        quit_ide_or_nvim(opts.bang, opts.fargs)
    end, { bang = true, nargs = "*", complete = complete_ide_sessions, desc = "Quit Entire IDE Workspace" })
    vim.api.nvim_create_user_command("Quit", function(opts)
        quit_ide_or_nvim(opts.bang, opts.fargs)
    end, { bang = true, nargs = "*", complete = complete_ide_sessions, desc = "Quit Entire IDE Workspace" })

    vim.api.nvim_create_user_command("IdeCd", run_ide_cd, {
        nargs = "?",
        complete = "dir",
        desc = "Dive IDE Workspace (Editor & Shell) to directory",
    })
    map("n", "<leader>cd", "<cmd>IdeCd<CR>", { desc = "Dive IDE Workspace to Current Buffer Directory" })

    vim.api.nvim_create_user_command("IdeSend", run_ide_send, {
        bang = true,
        range = true,
        nargs = "?",
        complete = complete_ide_sessions,
        desc = "Stage line or visual range into target IDE session AI prompt",
    })
end

return M
