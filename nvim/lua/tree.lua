-- nvim-tree file explorer: node keymaps, scope toggling, and setup.
local menus = require("menus")

local function my_on_attach(bufnr)
    local api = require('nvim-tree.api')
    local function opts(desc)
        return { desc = 'nvim-tree: ' .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
    end
    api.config.mappings.default_on_attach(bufnr)
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.opt_local.statusline = "%#NvimTreeNormal# "
    vim.keymap.set('n', 'P', function()
        local node = api.tree.get_node_under_cursor()
        _G.copy_to_system_clipboard(node.absolute_path)
    end, opts('Copy Absolute Path'))

    vim.keymap.set('n', 'm', function()
        local node = api.tree.get_node_under_cursor()
        menus.tree_node_menu(node, api)
    end, opts('Node Menu'))

    -- '.' scopes nvim's cwd to the directory under the cursor; pressing it
    -- again on the same directory restores the previous cwd.
    vim.keymap.set('n', '.', function()
        local node = api.tree.get_node_under_cursor()
        if node.type ~= 'directory' then return end
        local current_cwd = vim.fn.getcwd()
        if _G.scope_restore_path and current_cwd == node.absolute_path then
            vim.cmd("cd " .. vim.fn.fnameescape(_G.scope_restore_path))
            print("Scope cleared.")
            _G.scope_restore_path = nil
        else
            if not _G.scope_restore_path then _G.scope_restore_path = current_cwd end
            vim.cmd("cd " .. vim.fn.fnameescape(node.absolute_path))
            print("Scope set to: " .. node.name)
        end
        vim.cmd("redrawstatus!")
    end, opts('Toggle Scope (CD)'))
    vim.keymap.set('n', '<CR>', function()
        local node = api.tree.get_node_under_cursor()
        if node.type == 'directory' then
            api.node.open.edit()
        else
            api.node.open.tab(node)
            vim.schedule(function()
                vim.wo.number = true
                vim.wo.relativenumber = false
            end)
        end
    end, opts('Smart Tab Edit'))
end

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter", "BufEnter" }, {
    pattern = "NvimTree",
    callback = function()
        vim.wo.number = false
        vim.wo.relativenumber = false
        vim.wo.statusline = "%#NvimTreeNormal# "
    end
})

require("nvim-tree").setup({
    on_attach = my_on_attach,
    disable_netrw = true,
    hijack_netrw = true,
    sync_root_with_cwd = false,
    git = { enable = true, ignore = false },
    view = { width = 14, side = "left", preserve_window_proportions = true },
    renderer = {
        group_empty = true,
        indent_markers = { enable = false },
        icons = {
            show = { git = false, folder = false, file = false, folder_arrow = false },
            glyphs = { folder = { arrow_closed = "+", arrow_open = "-", default = "", open = "", empty = "" } }
        }
    },
    filters = { dotfiles = false, custom = { "^.git$", "__pycache__", "\\.pyc$" } },
})
