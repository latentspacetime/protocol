-- Core editor settings and the line-number policy.
-- The statusline and tabline option strings live in appearance.lua, next to
-- the functions that render them.
local opt = vim.opt
opt.termguicolors = false
opt.number = true
opt.cursorline = true
opt.splitright = true
opt.splitbelow = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true
opt.clipboard = "unnamedplus"
opt.timeoutlen = 1000
opt.ttimeoutlen = 10 -- FIX: Closes the Terminal PTY race condition window
opt.showtabline = 2
opt.showmode = false
opt.hlsearch = true
opt.incsearch = true
opt.swapfile = false -- FIX: Prevents read-only lockups across nested environments
opt.autoread = true  -- FIX: Auto-loads external changes (like git checkouts) immediately

-- Absolute line numbers in every real file buffer. Tree and terminal windows
-- opt out in their own modules (tree.lua, terminals.lua).
vim.api.nvim_create_autocmd({"BufWinEnter", "BufEnter", "WinEnter", "FileType", "TabEnter"}, {
    callback = function()
        vim.schedule(function()
            local bt = vim.bo.buftype
            local ft = vim.bo.filetype
            if bt == "" and ft ~= "NvimTree" then
                vim.wo.number = true
                vim.wo.relativenumber = false
            end
        end)
    end
})
