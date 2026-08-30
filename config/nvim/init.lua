-- =============================================================
-- Modern Lua Neovim Configuration (init.lua)
-- Windows Developer Workstation Configuration
-- =============================================================

-- Set Leader Key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- -------------------------------------------------------------
-- 1. Core Options & Editor Hygiene
-- -------------------------------------------------------------
local opt = vim.opt

-- Line Numbers
opt.number = true
opt.relativenumber = true

-- Tabs & Indentation
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = true
opt.smartindent = true
opt.autoindent = true

-- Appearance & Solarized UI
opt.termguicolors = true
opt.cursorline = true
opt.signcolumn = "yes"
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false

-- Search Settings
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- Backup & State Files
opt.backup = false
opt.writebackup = false
opt.swapfile = false
opt.undofile = true

-- Performance & Responsiveness
opt.updatetime = 250
opt.timeoutlen = 300

-- System Clipboard Integration (Windows unnamedplus)
opt.clipboard = "unnamedplus"

-- Split Windows
opt.splitright = true
opt.splitbelow = true

-- -------------------------------------------------------------
-- 2. General Keymaps
-- -------------------------------------------------------------
local map = vim.keymap.set

-- Clear search highlight
map("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Fast Save & Quit
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>q<CR>", { desc = "Quit buffer" })

-- Better Window Navigation (Ctrl + hjkl)
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Stay in indent mode when shifting
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- Move text up and down in visual mode
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move text down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move text up" })

-- File Explorer Toggle (Netrw fallback)
map("n", "<leader>e", "<cmd>Explore<CR>", { desc = "Open File Explorer" })

-- -------------------------------------------------------------
-- 3. Bootstrap Lazy.nvim Plugin Manager
-- -------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- -------------------------------------------------------------
-- 4. Plugin Ecosystem
-- -------------------------------------------------------------
local status_ok, lazy = pcall(require, "lazy")
if not status_ok then
    -- Fallback Solarized colors if offline/lazy not present
    vim.cmd([[
        highlight Normal guibg=#002B36 guifg=#839496
        highlight CursorLine guibg=#073642
        highlight Comment guifg=#586E75 gui=italic
    ]])
    return
end

lazy.setup({
    -- Solarized Theme
    {
        "craftzdog/solarized-osaka.nvim",
        lazy = false,
        priority = 1000,
        opts = {
            transparent = false,
            terminal_colors = true,
            styles = {
                comments = { italic = true },
                keywords = { italic = false },
            },
        },
        config = function(_, opts)
            require("solarized-osaka").setup(opts)
            vim.cmd.colorscheme("solarized-osaka")
        end,
    },

    -- Tree-sitter AST Syntax Highlighting
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
            local ts_ok, ts = pcall(require, "nvim-treesitter.configs")
            if ts_ok then
                ts.setup({
                    ensure_installed = { "go", "python", "terraform", "yaml", "json", "toml", "bash", "lua", "markdown" },
                    highlight = { enable = true },
                    indent = { enable = true },
                })
            end
        end,
    },

    -- Telescope Fuzzy Finder
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find Files" },
            { "<leader>fg", "<cmd>Telescope live_grep<CR>",  desc = "Live Grep" },
            { "<leader>fb", "<cmd>Telescope buffers<CR>",    desc = "Find Buffers" },
        },
        opts = {
            defaults = {
                layout_strategy = "horizontal",
            },
        },
    },

    -- Mason & Language Server Protocol (LSP)
    {
        "williamboman/mason.nvim",
        opts = {},
    },
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
        opts = {
            ensure_installed = { "gopls", "terraformls", "pyright", "yamlls" },
            automatic_installation = true,
        },
        config = function(_, opts)
            require("mason-lspconfig").setup(opts)
            local lspconfig = require("lspconfig")
            local on_attach = function(_, bufnr)
                local bufmap = function(keys, func, desc)
                    vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "LSP: " .. desc })
                end
                bufmap("gd", vim.lsp.buf.definition, "Goto Definition")
                bufmap("gr", vim.lsp.buf.references, "Goto References")
                bufmap("K", vim.lsp.buf.hover, "Hover Documentation")
                bufmap("<leader>rn", vim.lsp.buf.rename, "Rename Symbol")
                bufmap("<leader>ca", vim.lsp.buf.code_action, "Code Action")
                bufmap("<leader>d", vim.diagnostic.open_float, "Line Diagnostics")
            end

            -- Configure default servers
            local servers = { "gopls", "terraformls", "pyright", "yamlls" }
            for _, s in ipairs(servers) do
                lspconfig[s].setup({ on_attach = on_attach })
            end
        end,
    },

    -- Lightweight Editor Utilities (Mini.nvim)
    {
        "echasnovski/mini.nvim",
        version = false,
        config = function()
            require("mini.pairs").setup()
            require("mini.comment").setup()
            require("mini.surround").setup()
        end,
    },
})
