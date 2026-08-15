-- Global keymaps. Buffer-local maps live with their features
-- (tree.lua node maps, terminals.lua window-hop maps).
local workspace = require("workspace")
local map = vim.keymap.set

-- Dynamic Tab Switching (Space + 1-9)
map('n', '<Leader>1', '<cmd>1tabnext<CR>', { silent = true, desc = "Switch to CORE" })
for i = 2, 9 do
    map('n', '<Leader>' .. i, '<cmd>' .. i .. 'tabnext<CR>', { silent = true, desc = "Switch to Tab " .. i })
end

-- Override native gt/gT to use pure Ex commands
map('n', 'gt', function()
    if vim.v.count > 0 then
        vim.cmd(vim.v.count .. "tabnext")
    else
        vim.cmd("tabnext")
    end
end, { silent = true })

map('n', 'gT', function()
    if vim.v.count > 0 then
        vim.cmd(vim.v.count .. "tabprevious")
    else
        vim.cmd("tabprevious")
    end
end, { silent = true })

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

map('n', '<Leader>q', function()
    vim.cmd("1tabnext")
    local ok, _ = pcall(vim.cmd, "tabonly")
    if ok then
        print("✓ Closed all non-core tabs.")
    else
        print("Could not close tabs. Unsaved changes?")
    end
end, { silent = true, desc = "Quit all non-core tabs" })
map('n', '<C-l>', ':tabnext<CR>', { silent = true })
map('n', '<C-h>', ':tabprev<CR>', { silent = true })
map('n', '<F2>', ':NvimTreeToggle<CR>', { silent = true })
map({ 'n', 'v' }, '<Leader>p', function()
    vim.fn.StartGlobalFzf(workspace.code_root)
end, { silent = true })
-- The jk escape hatch works in every capitalization, in both modes that need
-- escaping. Caps lock inverts letter case at the terminal (2026-08-15
-- input-diagnostics.log: jk arrived as "JK"), and the one mapping that gets
-- you out of a bad state is exactly the one that must not be case-sensitive.
-- Other maps (m, gt, <Leader>p) stay lowercase-only: they fail loudly under
-- caps lock, which is recoverable; a dead escape hatch is not.
for _, jk_variant in ipairs({ 'jk', 'JK', 'Jk', 'jK' }) do
    map('t', jk_variant, '<C-\\><C-n>')
    map('i', jk_variant, '<Esc>')
end

map('n', '<Leader>u', '<cmd>ClipFix<CR>', { silent = true, desc = "Unwrap clipboard (strip agent wrap artifacts)" })

map('n', '<Leader>o', function() require("otemp").toggle() end, { silent = true, desc = "Toggle OTemp scratch pad" })
