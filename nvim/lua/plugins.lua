local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    local result = vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
    })
    if vim.v.shell_error ~= 0 then
        error("lazy.nvim bootstrap failed: " .. result)
    end
end

vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
    "nvim-tree/nvim-tree.lua",
    { "junegunn/fzf", build = "./install --all" },
    "junegunn/fzf.vim",
})
