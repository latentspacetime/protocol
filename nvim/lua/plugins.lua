-- Plugin manager bootstrap (lazy.nvim) and the plugin list.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({ "git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath })
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
    "nvim-tree/nvim-tree.lua",
    { "junegunn/fzf", build = "./install --all" },
    "junegunn/fzf.vim",
    {
        "latentspacetime/warp.nvim",
        config = function()
            require("warp").setup()
        end,
    },
})
