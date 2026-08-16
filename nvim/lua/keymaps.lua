-- Global keymaps. Buffer-local maps live with their features
-- (tree.lua node maps, terminals.lua window-hop maps).
local workspace = require("workspace")
local map = vim.keymap.set

-- Dynamic Tab Switching (Space + 1-9)
map('n', '<Leader>1', '<cmd>1tabnext<CR>', { silent = true, desc = "Switch to CORE" })
for i = 2, 9 do
    map('n', '<Leader>' .. i, '<cmd>' .. i .. 'tabnext<CR>', { silent = true, desc = "Switch to Tab " .. i })
end

map('n', '<Leader>f', ':BLines<CR>', { silent = true, desc = "Search Current File" })
map('n', '<Leader>F', ':Rg<CR>', { silent = true, desc = "Search Global Project" })

-- With an active search highlight, Enter/Backspace step through matches;
-- otherwise they keep their native behavior.
map('n', '<CR>', function()
    if vim.v.hlsearch == 1 and vim.bo.buftype == "" then
        local ok, _ = pcall(vim.cmd, "normal! nzz")
        if not ok then vim.cmd("echo 'No match found'") end
    else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
    end
end, { silent = true })
map('n', '<BS>', function()
    if vim.v.hlsearch == 1 and vim.bo.buftype == "" then
        local ok, _ = pcall(vim.cmd, "normal! Nzz")
        if not ok then vim.cmd("echo 'No match found'") end
    else
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<BS>', true, false, true), 'n', false)
    end
end, { silent = true })
map('n', '<Esc>', function()
    vim.cmd("nohlsearch")
    vim.cmd("echo ''")
end, { silent = true })

-- 'm' opens the file action menu — deliberately shadows vim's set-mark key.
map('n', 'm', '<cmd>lua _G.file_buffer_menu()<CR>', { silent = true })

for _, q_variant in ipairs({ 'q', 'Q' }) do
    map('n', '<Leader>' .. q_variant, function()
        vim.cmd("1tabnext")
        local ok, _ = pcall(vim.cmd, "tabonly")
        if ok then
            print("✓ Closed all non-core tabs.")
        else
            print("Could not close tabs. Unsaved changes?")
        end
    end, { silent = true, desc = "Quit all non-core tabs" })
end
map('n', '<C-l>', ':tabnext<CR>', { silent = true })
map('n', '<C-h>', ':tabprev<CR>', { silent = true })
map('n', '<F2>', ':NvimTreeToggle<CR>', { silent = true })
for _, p_variant in ipairs({ 'p', 'P' }) do
    map({ 'n', 'v' }, '<Leader>' .. p_variant, function()
        vim.fn.StartGlobalFzf(workspace.code_root)
    end, { silent = true })
end
-- The jk escape hatch works in every capitalization, in both modes that need
-- escaping. Caps lock inverts letter case at the terminal (2026-08-15
-- input-diagnostics.log: jk arrived as "JK"), and the one mapping that gets
-- you out of a bad state is exactly the one that must not be case-sensitive.
-- Other maps (m, gt) stay lowercase-only: they fail loudly under caps lock,
-- which is recoverable; a dead escape hatch is not.
for _, jk_variant in ipairs({ 'jk', 'JK', 'Jk', 'jK' }) do
    map('t', jk_variant, '<C-\\><C-n>')
    map('i', jk_variant, '<Esc>')
end

for _, u_variant in ipairs({ 'u', 'U' }) do
    map('n', '<Leader>' .. u_variant, '<cmd>ClipFix<CR>', { silent = true, desc = "Unwrap clipboard (strip agent wrap artifacts)" })
end

for _, o_variant in ipairs({ 'o', 'O' }) do
    map('n', '<Leader>' .. o_variant, function() require("otemp").toggle() end, { silent = true, desc = "Toggle OTemp scratch pad" })
end
