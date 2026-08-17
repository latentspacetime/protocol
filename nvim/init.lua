-- Neovim configuration entry point (~/.config/nvim/init.lua).
-- Each module under lua/ owns one feature.
--
-- Load order is a contract:
--   1. mapleader must be set before lazy.nvim loads and before any keymap.
--   2. interceptor must run before everything else — inside a nested editor
--      it forwards the command to the host instance and never returns.
--   3. plugins must load before tree (which requires nvim-tree).
--   4. appearance -> search -> terminals must keep this order: their VimEnter
--      autocmds fire in registration order (highlights, :Rg, workspace layout).
vim.g.mapleader = " "

require("interceptor")
require("plugins")
require("options")
require("recover")
require("menus")
require("otemp")
require("friction")
require("obsidian")
require("warp")
require("appearance")
require("search")
require("tree")
require("terminals")
require("keymaps")
