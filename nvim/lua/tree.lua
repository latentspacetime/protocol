local menus = require("menus")

local function on_attach(buffer)
    local api = require("nvim-tree.api")
    local function options(description)
        return {
            desc = "nvim-tree: " .. description,
            buffer = buffer,
            noremap = true,
            silent = true,
            nowait = true,
        }
    end

    api.config.mappings.default_on_attach(buffer)
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.opt_local.statusline = "%#NvimTreeNormal# "

    vim.keymap.set("n", "P", function()
        local node = api.tree.get_node_under_cursor()
        _G.copy_to_system_clipboard(node.absolute_path)
    end, options("Copy absolute path"))

    vim.keymap.set("n", "m", function()
        menus.tree_node_menu(api.tree.get_node_under_cursor(), api)
    end, options("Node menu"))

    vim.keymap.set("n", ".", function()
        local node = api.tree.get_node_under_cursor()
        if node.type ~= "directory" then return end
        local current_directory = vim.fn.getcwd()
        if _G.protocol_scope_restore and current_directory == node.absolute_path then
            vim.cmd("cd " .. vim.fn.fnameescape(_G.protocol_scope_restore))
            _G.protocol_scope_restore = nil
            print("Scope cleared.")
        else
            if not _G.protocol_scope_restore then
                _G.protocol_scope_restore = current_directory
            end
            vim.cmd("cd " .. vim.fn.fnameescape(node.absolute_path))
            print("Scope set to: " .. node.name)
        end
        vim.cmd("redrawstatus!")
    end, options("Toggle directory scope"))

    vim.keymap.set("n", "<CR>", function()
        local node = api.tree.get_node_under_cursor()
        if node.type == "directory" then
            api.node.open.edit()
        else
            api.node.open.tab(node)
            vim.schedule(function()
                vim.wo.number = true
                vim.wo.relativenumber = false
            end)
        end
    end, options("Open in tab"))
end

vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter", "BufEnter" }, {
    pattern = "NvimTree",
    callback = function()
        vim.wo.number = false
        vim.wo.relativenumber = false
        vim.wo.statusline = "%#NvimTreeNormal# "
    end,
})

require("nvim-tree").setup({
    on_attach = on_attach,
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
            glyphs = { folder = { arrow_closed = "+", arrow_open = "-", default = "", open = "", empty = "" } },
        },
    },
    filters = { dotfiles = false, custom = { "^.git$", "__pycache__", "\\.pyc$" } },
})
