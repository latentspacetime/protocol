-- These renderers are global because statusline and tabline expressions call
-- them through v:lua on every redraw.
function _G.get_git_branch(start_path)
    local path = start_path or vim.fn.getcwd()
    if not path or path == "" then return "" end

    while path ~= "/" and path ~= "." do
        local git_head = path .. "/.git/HEAD"
        local file = io.open(git_head, "r")
        if file then
            local content = file:read("*all")
            file:close()
            if content then
                local branch = content:match("ref: refs/heads/(.+)")
                if branch then return branch:gsub("%s+", "") end
                return content:sub(1, 7)
            end
        end
        local parent = vim.fn.fnamemodify(path, ":h")
        if parent == path then break end
        path = parent
    end
    return ""
end

function _G.get_status_branch_string()
    local branch = _G.get_git_branch(vim.fn.expand("%:p:h"))
    return branch ~= "" and " [" .. branch .. "] " or " "
end

function _G.get_mode_info()
    if vim.bo.filetype == "NvimTree" then return "" end
    local mode = vim.fn.mode()
    if mode == "t" or mode == "i" or mode == "ic" then
        return "%#ModeInsert# - INSERT - "
    end
    return "%#ModeNormal# - NORMAL - "
end

vim.opt.statusline = "%f %m %{v:lua.get_status_branch_string()} %= %l:%c %{%v:lua.get_mode_info()%}"

function _G.protocol_tabline()
    local output = ""
    for index = 1, vim.fn.tabpagenr("$") do
        output = output .. (index == vim.fn.tabpagenr() and "%#TabLineSel#" or "%#TabLine#")
        output = output .. " " .. index .. " "
        if index == 1 then
            output = output .. "WORKSPACE"
        else
            local window = vim.fn.tabpagewinnr(index)
            local buffer = vim.fn.tabpagebuflist(index)[window]
            local filename = vim.fn.fnamemodify(vim.fn.bufname(buffer), ":t")
            output = output .. (filename ~= "" and filename or "[No Name]")
        end
        output = output .. " "
    end
    return output .. "%#TabLineFill#%T"
end

vim.opt.tabline = "%!v:lua.protocol_tabline()"

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        local transparent_groups = {
            "Normal", "NonText", "LineNr", "SignColumn", "EndOfBuffer",
            "VertSplit", "TabLineFill", "NvimTreeNormal", "NvimTreeNormalNC",
            "NvimTreeVertSplit", "NvimTreeEndOfBuffer", "NvimTreeRootFolder",
            "NvimTreeEmptyFolderName",
        }
        for _, group in ipairs(transparent_groups) do
            vim.cmd("highlight " .. group .. " ctermbg=NONE guibg=NONE")
        end
        vim.cmd("highlight CursorLine ctermbg=NONE guibg=NONE")
        vim.cmd("highlight CursorLineNr cterm=none ctermfg=11")
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
