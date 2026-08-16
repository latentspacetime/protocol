-- Statusline, tabline, terminal-tab title, and highlight groups.
-- The renderer functions must stay on _G: the 'statusline' and 'tabline'
-- option strings evaluate them through v:lua on every redraw.

-- Walks up from start_path looking for .git/HEAD; returns the branch name,
-- a short hash when detached, or "" outside a repo. Reads the file directly
-- instead of shelling out so statusline redraws stay cheap.
function _G.get_git_branch(start_path)
    local path = start_path or vim.fn.getcwd()
    if not path or path == "" then return "" end
    while path ~= "/" and path ~= "." do
        local git_head = path .. "/.git/HEAD"
        local f = io.open(git_head, "r")
        if f then
            local content = f:read("*all")
            f:close()
            if content then
                local branch = content:match("ref: refs/heads/(.+)")
                if branch then
                    return branch:gsub("%s+", "")
                else
                    return content:sub(1, 7)
                end
            end
        end
        local parent = vim.fn.fnamemodify(path, ":h")
        if parent == path then break end
        path = parent
    end
    return ""
end

function _G.get_status_branch_string()
    local dir = vim.fn.expand('%:p:h')
    local branch = _G.get_git_branch(dir)
    if branch ~= "" then return " [" .. branch .. "] " end
    return " "
end

function _G.get_mode_info()
    if vim.bo.filetype == "NvimTree" then return "" end
    local mode = vim.fn.mode()
    if mode == 't' or mode == 'i' or mode == 'ic' then
        return "%#ModeInsert# - INSERT - "
    else
        return "%#ModeNormal# - NORMAL - "
    end
end

vim.opt.statusline = "%f %m %{v:lua.get_status_branch_string()} %= %l:%c %{%v:lua.get_mode_info()%}"

-- Ghostty instance identity. Each live nvim claims a slot via tabslot.lua,
-- which gives it a stable NVIM N label shown in the terminal title. On
-- FocusGained the tabline briefly becomes a full-width colored banner with
-- the label, so switching windows shows which instance you landed in.
local tabslot = require("tabslot")

local pulse_duration_ms = 350
-- Keyed by slot, so instance 1 pulses cyan. Same palette as tab_colors
-- below, ordered independently so the instance cycle stays decoupled from
-- the tab cycle.
local pulse_colors = { 14, 11, 10, 13, 12, 9 }
local slot_dir = vim.fn.stdpath("state") .. "/tab-slots"
local augroup = vim.api.nvim_create_augroup("Appearance", { clear = true })

local tab_slot = tabslot.claim(slot_dir)
if not tab_slot then
    vim.notify("appearance: no instance slot claimed; NVIM number may repeat",
        vim.log.levels.WARN)
end
local instance_label = "NVIM " .. ((tab_slot or 0) + 1)
local pulse_active = false
local pulse_generation = 0
local pulse_banner = "%#InstancePulse#%= " .. instance_label .. " %="

vim.opt.title = true
vim.opt.titlestring = instance_label
vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
        if tab_slot then tabslot.release(slot_dir, tab_slot) end
    end,
})

vim.api.nvim_create_autocmd("FocusGained", {
    group = augroup,
    callback = function()
        pulse_generation = pulse_generation + 1
        local generation = pulse_generation

        pulse_active = true
        vim.opt.titlestring = "[ " .. instance_label .. " ]"
        vim.cmd("redrawtabline")

        vim.defer_fn(function()
            if generation ~= pulse_generation then return end
            pulse_active = false
            vim.opt.titlestring = instance_label
            vim.cmd("redrawtabline")
        end, pulse_duration_ms)
    end,
})

-- Tabline colors come straight from the terminal's bright ANSI palette, so
-- whatever theme Ghostty runs supplies the actual hues and the tabs always
-- harmonize with it. Cycled by tab index in my_tabline.
local tab_colors = { 9, 11, 10, 14, 12, 13 } -- red yellow green cyan blue magenta

-- Tab 1 is always the CORE workspace and wears the instance color
-- (TabCoreSel/TabCore), a standing identity beyond the focus pulse; other
-- tabs show their file name and cycle tab_colors: selected renders as a
-- solid chip, the rest as colored text.
function _G.my_tabline()
    if pulse_active then
        return pulse_banner
    end

    local s = ""
    for i = 1, vim.fn.tabpagenr('$') do
        local is_selected = (i == vim.fn.tabpagenr())
        if i == 1 then
            s = s .. "%#" .. (is_selected and "TabCoreSel" or "TabCore") .. "#"
        else
            local color_index = ((i - 1) % #tab_colors) + 1
            local group = is_selected and "TabRainbowSel" or "TabRainbow"
            s = s .. "%#" .. group .. color_index .. "#"
        end
        s = s .. " " .. i .. " "
        if i == 1 then
            s = s .. "CORE"
        else
            local winnr = vim.fn.tabpagewinnr(i)
            local buflist = vim.fn.tabpagebuflist(i)
            local bufnr = buflist[winnr]
            local bufname = vim.fn.bufname(bufnr)
            local filename = vim.fn.fnamemodify(bufname, ":t")
            if filename == "" then filename = "[No Name]" end
            s = s .. filename
        end
        s = s .. " "
    end
    s = s .. "%#TabLineFill#%T"
    return s
end
vim.opt.tabline = "%!v:lua.my_tabline()"

-- Applied at VimEnter so they land after anything else touches highlights
-- during startup. Transparent backgrounds let the terminal's own theme show.
vim.api.nvim_create_autocmd("VimEnter", {
    group = augroup,
    callback = function()
        local transparent_groups = {
            "Normal", "NonText", "LineNr", "SignColumn", "EndOfBuffer",
            "VertSplit", "TabLineFill",
            "NvimTreeNormal", "NvimTreeNormalNC", "NvimTreeVertSplit", "NvimTreeEndOfBuffer",
            "NvimTreeRootFolder", "NvimTreeEmptyFolderName"
        }
        for _, group in ipairs(transparent_groups) do
            vim.cmd("highlight " .. group .. " ctermbg=NONE guibg=NONE")
        end
        vim.cmd("highlight CursorLine ctermbg=NONE guibg=NONE")
        vim.cmd("highlight CursorLineNr cterm=none ctermfg=11")
        vim.cmd("highlight NvimTreeRootFolder ctermfg=NONE guifg=NONE ctermbg=NONE guibg=NONE")
        for i, color in ipairs(tab_colors) do
            vim.cmd(string.format(
                "highlight TabRainbow%d ctermbg=NONE guibg=NONE ctermfg=%d", i, color))
            vim.cmd(string.format(
                "highlight TabRainbowSel%d ctermbg=%d ctermfg=0 cterm=bold", i, color))
        end
        local pulse_color = pulse_colors[((tab_slot or 0) % #pulse_colors) + 1]
        vim.cmd(string.format(
            "highlight InstancePulse ctermbg=%d ctermfg=0 cterm=bold", pulse_color))
        vim.cmd(string.format(
            "highlight TabCoreSel ctermbg=%d ctermfg=0 cterm=bold", pulse_color))
        vim.cmd(string.format(
            "highlight TabCore ctermbg=NONE guibg=NONE ctermfg=%d", pulse_color))
        vim.cmd("highlight StatusLine cterm=NONE ctermbg=2 ctermfg=0")
        vim.cmd("highlight StatusLineNC cterm=NONE ctermbg=NONE ctermfg=10")
        vim.cmd("highlight ModeInsert ctermbg=0 ctermfg=15 cterm=bold")
        vim.cmd("highlight ModeNormal ctermbg=15 ctermfg=0 cterm=bold")
        -- Mode chips in the OTemp float title (otemp.lua float_title): green
        -- while typing, blue when the m/esc menu keys are live.
        vim.cmd("highlight OTempInsert ctermbg=10 ctermfg=0 cterm=bold")
        vim.cmd("highlight OTempNormal ctermbg=12 ctermfg=0 cterm=bold")
        vim.cmd("highlight NvimTreeFolderName ctermbg=NONE guibg=NONE ctermfg=Blue guifg=Blue")
        vim.cmd("highlight NvimTreeOpenedFolderName ctermbg=NONE guibg=NONE ctermfg=Blue guifg=Blue")
    end,
})
