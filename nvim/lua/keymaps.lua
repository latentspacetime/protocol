local workspace = require("workspace")
local map = vim.keymap.set

map("n", "<Leader>1", "<cmd>1tabnext<CR>", { silent = true, desc = "Switch to workspace" })
for index = 2, 9 do
    map("n", "<Leader>" .. index, "<cmd>" .. index .. "tabnext<CR>", {
        silent = true,
        desc = "Switch to tab " .. index,
    })
end

map("n", "gt", function()
    vim.cmd((vim.v.count > 0 and vim.v.count or "") .. "tabnext")
end, { silent = true })
map("n", "gT", function()
    vim.cmd((vim.v.count > 0 and vim.v.count or "") .. "tabprevious")
end, { silent = true })

map("n", "<Leader>f", ":BLines<CR>", { silent = true, desc = "Search current file" })
map("n", "<Leader>F", ":Rg<CR>", { silent = true, desc = "Search workspace" })

map("n", "<CR>", function()
    if vim.v.hlsearch == 1 and vim.bo.buftype == "" then
        if not pcall(vim.cmd, "normal! nzz") then print("No match found") end
    else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
    end
end, { silent = true })
map("n", "<BS>", function()
    if vim.v.hlsearch == 1 and vim.bo.buftype == "" then
        if not pcall(vim.cmd, "normal! Nzz") then print("No match found") end
    else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<BS>", true, false, true), "n", false)
    end
end, { silent = true })
map("n", "<Esc>", function()
    vim.cmd("nohlsearch")
    vim.cmd("echo ''")
end, { silent = true })

map("n", "m", "<cmd>lua _G.file_buffer_menu()<CR>", { silent = true })
map("n", "<Leader>q", function()
    vim.cmd("1tabnext")
    if pcall(vim.cmd, "tabonly") then
        print("Closed all non-workspace tabs.")
    else
        print("Could not close tabs. Check for unsaved changes.")
    end
end, { silent = true, desc = "Close non-workspace tabs" })

map("n", "<C-l>", ":tabnext<CR>", { silent = true })
map("n", "<C-h>", ":tabprev<CR>", { silent = true })
map("n", "<F2>", ":NvimTreeToggle<CR>", { silent = true })
map({ "n", "v" }, "<Leader>p", function()
    vim.fn.StartGlobalFzf(workspace.code_root)
end, { silent = true })
map("t", "jk", "<C-\\><C-n>")
map("t", "JK", "<C-\\><C-n>")
map("t", "Jk", "<C-\\><C-n>")
map("t", "jK", "<C-\\><C-n>")
map("i", "jk", "<Esc>")
map("n", "<Leader>u", "<cmd>ClipFix<CR>", { silent = true, desc = "Unwrap clipboard" })
