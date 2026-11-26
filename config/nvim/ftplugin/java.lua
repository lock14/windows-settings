-- Java Filetype Plugin for Neovim (nvim-jdtls integration)
-- Runs on-demand ONLY when a .java file is opened.

local status_ok, jdtls = pcall(require, "jdtls")
if not status_ok then
    return
end

local is_win32 = vim.fn.has("win32") == 1

-- Detect Maven or Gradle build root; skip auto-starting jdtls in Bazel-only workspaces.
-- Walk upward one level at a time checking regular files (`type == "file"`) so we stop
-- immediately at a Bazel workspace boundary without probing outer mount parents or
-- matching synthesized directories (such as `mvnw/` or `gradlew/`).
local uv = vim.uv or vim.loop
local maven_gradle_markers = { "pom.xml", "build.gradle", "build.gradle.kts", "mvnw", "gradlew" }
local bazel_markers = { "WORKSPACE", "WORKSPACE.bazel", "MODULE.bazel" }
local buf_dir = vim.fn.expand("%:p:h")
local build_root = nil
local git_root = nil
if uv and buf_dir ~= "" then
    local cur = vim.fs.normalize(buf_dir)
    while cur and cur ~= "" do
        local sep = (cur:sub(-1) == "/") and "" or "/"
        for _, m in ipairs(maven_gradle_markers) do
            local st = uv.fs_stat(cur .. sep .. m)
            if st and st.type == "file" then
                build_root = cur
                break
            end
        end
        if build_root then
            break
        end
        for _, bm in ipairs(bazel_markers) do
            local bst = uv.fs_stat(cur .. sep .. bm)
            if bst and bst.type == "file" then
                return
            end
        end
        if not git_root and uv.fs_stat(cur .. sep .. ".git") then
            git_root = cur
        end
        local parent = vim.fs.dirname(cur)
        if not parent or parent == cur then
            break
        end
        cur = parent
    end
end
local root_dir = build_root or git_root or buf_dir

-- Compute SHA-256 hash-salted workspace directory under XDG_CACHE_HOME / ~/.cache to prevent OSGi lock collisions
local norm_root = vim.fs.normalize(vim.fn.fnamemodify(root_dir, ":p"))
if norm_root ~= "/" and not norm_root:match("^%a:/$") then
    norm_root = norm_root:gsub("/+$", "")
end
if norm_root == "" then
    norm_root = is_win32 and ((vim.env.SystemDrive or "C:") .. "/") or "/"
end
local project_name = vim.fn.fnamemodify(norm_root:gsub("/+$", ""), ":t")
if project_name == "" or project_name:match("^%a:$") then
    project_name = project_name:gsub(":", "")
    if project_name == "" then
        project_name = "root"
    end
end
local root_hash = vim.fn.sha256(is_win32 and norm_root:lower() or norm_root):sub(1, 8)
local home_dir = vim.env.HOME or vim.env.USERPROFILE
local xdg_cache = vim.env.XDG_CACHE_HOME
local cache_dir = (xdg_cache and xdg_cache ~= "") and xdg_cache
    or (home_dir and home_dir ~= "" and (home_dir .. "/.cache"))
    or vim.fn.stdpath("cache")
local workspace_dir = vim.fs.normalize(cache_dir) .. "/jdtls/workspaces/" .. project_name .. "-" .. root_hash

-- Locate jdtls binary (from Mason or system PATH, including Windows .cmd shims)
local mason_bin_base = vim.fn.stdpath("data") .. "/mason/bin/jdtls"
local mason_bin_cmd = mason_bin_base .. ".cmd"
local cmd = nil

if is_win32 and vim.fn.executable(mason_bin_cmd) == 1 then
    cmd = { mason_bin_cmd, "-data", workspace_dir }
elseif vim.fn.executable(mason_bin_base) == 1 then
    cmd = { mason_bin_base, "-data", workspace_dir }
elseif is_win32 and vim.fn.executable("jdtls.cmd") == 1 then
    cmd = { "jdtls.cmd", "-data", workspace_dir }
elseif vim.fn.executable("jdtls") == 1 then
    cmd = { "jdtls", "-data", workspace_dir }
else
    -- Search in Mason package directory if launcher script isn't linked yet
    local mason_pkg_dir = vim.fn.stdpath("data") .. "/mason/packages/jdtls"
    local launcher_matches = vim.fn.glob(mason_pkg_dir .. "/plugins/org.eclipse.equinox.launcher_*.jar", true, true)
    local launcher_jar = (type(launcher_matches) == "table" and launcher_matches[1]) or ""
    if launcher_jar ~= "" then
        local os_config = vim.fn.has("mac") == 1 and "config_mac" or (is_win32 and "config_win" or "config_linux")
        cmd = {
            "java",
            "-Declipse.application=org.eclipse.jdt.ls.core.id1",
            "-Dosgi.bundles.defaultStartLevel=4",
            "-Declipse.product=org.eclipse.jdt.ls.core.product",
            "-Dlog.level=ALL",
            "-Xms512m",
            "-Xmx1g",
            "-jar", launcher_jar,
            "-configuration", mason_pkg_dir .. "/" .. os_config,
            "-data", workspace_dir,
        }
    end
end

if not cmd then
    return
end

local config = {
    cmd = cmd,
    root_dir = root_dir,
    settings = {
        java = {
            signatureHelp = { enabled = true },
            contentProvider = { preferred = "fernflower" },
            completion = {
                favoriteStaticMembers = {
                    "org.junit.Assert.*",
                    "org.junit.Assume.*",
                    "org.junit.jupiter.api.Assertions.*",
                    "org.junit.jupiter.api.Assumptions.*",
                    "org.junit.jupiter.api.DynamicContainer.*",
                    "org.junit.jupiter.api.DynamicTest.*",
                    "org.mockito.Mockito.*",
                    "org.mockito.ArgumentMatchers.*",
                },
            },
            sources = {
                organizeImports = {
                    starThreshold = 9999,
                    staticStarThreshold = 9999,
                },
            },
        },
    },
    on_attach = function(client, bufnr)
        -- Disable LSP semantic token overrides so Treesitter handles syntax highlighting
        client.server_capabilities.semanticTokensProvider = nil
        -- Disable documentLinkProvider to eliminate rogue clickable hyperlink metadata and spurious link highlights
        client.server_capabilities.documentLinkProvider = nil

        local bufmap = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "Java LSP: " .. desc })
        end

        bufmap("<leader>jo", jdtls.organize_imports, "Organize Imports")
        bufmap("<leader>jv", jdtls.extract_variable, "Extract Variable")
        bufmap("<leader>jc", jdtls.extract_constant, "Extract Constant")
        bufmap("<leader>jm", jdtls.extract_method, "Extract Method")
    end,
}

jdtls.start_or_attach(config)
