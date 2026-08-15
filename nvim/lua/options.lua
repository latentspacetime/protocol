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
opt.ttimeoutlen = 10
opt.showtabline = 2
opt.showmode = false
opt.hlsearch = true
opt.incsearch = true
opt.swapfile = false
opt.autoread = true

vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter", "WinEnter", "FileType", "TabEnter" }, {
    callback = function()
        vim.schedule(function()
            if vim.bo.buftype == "" and vim.bo.filetype ~= "NvimTree" then
                vim.wo.number = true
                vim.wo.relativenumber = false
            end
        end)
    end,
})
