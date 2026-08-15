-- Statusline, tabline, and highlight groups.
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

-- Tab 1 is always the CORE workspace; other tabs show their file name.
function _G.my_tabline()
    local s = ""
    for i = 1, vim.fn.tabpagenr('$') do
        local is_selected = (i == vim.fn.tabpagenr())
        if is_selected then s = s .. "%#TabLineSel#" else s = s .. "%#TabLine#" end
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
        vim.cmd("highlight TabLineSel ctermbg=NONE guibg=NONE ctermfg=10 guifg=Green cterm=bold gui=bold")
        vim.cmd("highlight TabLine ctermbg=NONE guibg=NONE ctermfg=Gray guifg=Gray")
        vim.cmd("highlight StatusLine cterm=NONE ctermbg=2 ctermfg=0")
        vim.cmd("highlight StatusLineNC cterm=NONE ctermbg=NONE ctermfg=10")
        vim.cmd("highlight ModeInsert ctermbg=0 ctermfg=15 cterm=bold")
        vim.cmd("highlight ModeNormal ctermbg=15 ctermfg=0 cterm=bold")
        vim.cmd("highlight NvimTreeFolderName ctermbg=NONE guibg=NONE ctermfg=Blue guifg=Blue")
        vim.cmd("highlight NvimTreeOpenedFolderName ctermbg=NONE guibg=NONE ctermfg=Blue guifg=Blue")
    end,
})
