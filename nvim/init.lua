-- Neovim configuration entry point.
-- Load order is intentional: nested-editor interception comes first, plugins
-- load before consumers, and VimEnter callbacks register in display order.
vim.g.mapleader = " "

require("interceptor")
require("plugins")
require("options")
require("recover")
require("menus")
require("appearance")
require("search")
require("tree")
require("terminals")
require("keymaps")
