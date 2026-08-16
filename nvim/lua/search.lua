-- fzf-powered file search (<Leader>p), repository picker (<Leader>r in a
-- CORE terminal), and the smart :Rg text search.
--
-- The fzf integration is deliberately Vimscript: fzf.vim's sink*/g:fzf_action
-- contract expects Vimscript funcrefs, and the delayed-echo helpers are timer
-- callbacks that must be named Vimscript functions. Porting them to Lua buys
-- nothing and risks breaking the contract.
local workspace = require("workspace")
local M = {}

function M.list_workspace_directories(root)
    local scan = vim.uv.fs_scandir(root)
    if not scan then return {} end

    local directories = {}
    while true do
        local name = vim.uv.fs_scandir_next(scan)
        if not name then break end
        if not name:find("[\r\n\t\27]") then
            local stat = vim.uv.fs_stat(root .. "/" .. name)
            if stat and stat.type == "directory" then
                table.insert(directories, name)
            end
        end
    end
    table.sort(directories, function(a, b)
        local lower_a, lower_b = a:lower(), b:lower()
        if lower_a == lower_b then return a < b end
        return lower_a < lower_b
    end)
    return directories
end

function M.color_workspace_directories(directories)
    local protocol_root = vim.env.PROTOCOL_ROOT
    if not protocol_root or protocol_root == "" then
        return nil, "PROTOCOL_ROOT is unavailable; start Neovim from a protocol shell."
    end
    local resolver = protocol_root .. "/shell/protocol.zsh"
    local stat = vim.uv.fs_stat(resolver)
    if not stat or stat.type ~= "file" then
        return nil, "Repository color resolver is unavailable: " .. resolver
    end

    local command = { "/bin/zsh", resolver, "--repo-colors" }
    vim.list_extend(command, directories)
    local ok, result = pcall(function()
        return vim.system(command, { text = true }):wait(1000)
    end)
    if not ok or result.code ~= 0 then
        local detail = ok and vim.trim(result.stderr or "") or ""
        return nil, detail ~= "" and detail or "Repository color resolver failed."
    end

    local colors = vim.split(result.stdout or "", "\n", { plain = true, trimempty = true })
    if #colors ~= #directories then
        return nil, "Repository color resolver returned an incomplete result."
    end
    local entries = {}
    for index, directory in ipairs(directories) do
        local color = tonumber(colors[index])
        if not color or color % 1 ~= 0 or color < 0 or color > 255 then
            return nil, "Repository color resolver returned an invalid color."
        end
        entries[index] = string.format("\27[38;5;%dm%s\27[0m", color, directory)
    end
    return entries
end

local function selected_workspace_directory(name)
    for _, directory in ipairs(M.list_workspace_directories(workspace.code_root)) do
        if directory == name then return workspace.code_root .. "/" .. name end
    end
    return nil
end

local function terminal_target_is_live(target)
    if not vim.api.nvim_win_is_valid(target.winid)
        or not vim.api.nvim_buf_is_valid(target.bufnr)
        or vim.api.nvim_win_get_buf(target.winid) ~= target.bufnr
        or vim.bo[target.bufnr].buftype ~= "terminal"
        or vim.bo[target.bufnr].channel ~= target.channel then
        return false
    end
    local ok, statuses = pcall(vim.fn.jobwait, { target.channel }, 0)
    return ok and statuses[1] == -1
end

function M.handle_repository_selection(target, lines)
    if #lines < 2 or (lines[1] ~= "" and lines[1] ~= "tab") then return false end
    local name = lines[2]:gsub("\27%[[0-9;]*m", "")
    local path = selected_workspace_directory(name)
    if not path then
        vim.notify("Selected workspace directory is no longer available.", vim.log.levels.WARN)
        return false
    end

    if lines[1] == "tab" then
        _G.copy_to_system_clipboard(path)
        return true
    end
    if not terminal_target_is_live(target) then
        vim.notify("The terminal that opened the repository picker is no longer available.", vim.log.levels.WARN)
        return false
    end

    local ok = pcall(vim.api.nvim_chan_send, target.channel, "cd -- " .. vim.fn.shellescape(path) .. "\n")
    if not ok then
        vim.notify("Could not change the terminal directory.", vim.log.levels.ERROR)
        return false
    end
    return true
end

function M.restore_repository_picker_target(target)
    vim.schedule(function()
        if not vim.api.nvim_win_is_valid(target.winid)
            or not vim.api.nvim_buf_is_valid(target.bufnr)
            or vim.api.nvim_win_get_buf(target.winid) ~= target.bufnr then
            return
        end
        vim.api.nvim_set_current_win(target.winid)
        if target.resume_insert and vim.bo[target.bufnr].buftype == "terminal" then
            vim.cmd("startinsert")
        end
    end)
end

function M.open_repository_picker(target)
    local directories = M.list_workspace_directories(workspace.code_root)
    if #directories == 0 then
        vim.notify("No directories found in " .. workspace.code_root, vim.log.levels.INFO)
        return
    end
    local entries, color_error = M.color_workspace_directories(directories)
    if not entries then
        vim.notify(color_error, vim.log.levels.ERROR)
        return
    end
    vim.fn.StartRepositoryFzf(
        entries,
        target.winid,
        target.bufnr,
        target.channel,
        target.resume_insert
    )
end

function M.attach_repository_picker(bufnr)
    for _, variant in ipairs({ 'r', 'R' }) do
        vim.keymap.set({ 'n', 't' }, '<Leader>' .. variant, function()
            local current_buf = vim.api.nvim_get_current_buf()
            M.open_repository_picker({
                winid = vim.api.nvim_get_current_win(),
                bufnr = current_buf,
                channel = vim.bo[current_buf].channel,
                resume_insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "t",
            })
        end, { buffer = bufnr, silent = true, desc = "Pick workspace repository" })
    end
end

-- Called by fzf's Vimscript funcrefs below.
function _G.repository_picker_handle(winid, bufnr, channel, resume_insert, lines)
    return M.handle_repository_selection({
        winid = winid,
        bufnr = bufnr,
        channel = channel,
        resume_insert = resume_insert,
    }, lines)
end

function _G.repository_picker_restore(winid, bufnr, channel, resume_insert)
    M.restore_repository_picker_target({
        winid = winid,
        bufnr = bufnr,
        channel = channel,
        resume_insert = resume_insert,
    })
end

-- Every search must follow symlinks: directories that sit in the code root
-- only as symlinks are skipped by rg by default — which made exact matches
-- inside them invisible to :Rg until --follow was added. The globs keep
-- generated/vendored trees (python venvs, node_modules) from drowning real
-- results. One flag string feeds both :Rg and the <Leader>p file walker.
local exclude_globs = {
    "node_modules", ".git", "site-packages", "__pycache__",
    ".venv", "venv", "*.pyc", ".DS_Store", "dist", ".next",
}
local rg_common_flags = "--follow"
for _, glob in ipairs(exclude_globs) do
    rg_common_flags = rg_common_flags .. " --glob " .. vim.fn.shellescape("!" .. glob)
end
-- Read by StartGlobalFzf below; runs inside the fzf 'dir' so results stay
-- relative, exactly like the default walker it replaces.
vim.g.fzf_file_walker = "rg --files " .. rg_common_flags

vim.cmd([[
function! FzfClearMsg(timer)
    echo ""
    redraw
endfunction
function! FzfEchoDelayed(timer)
    redraw
    echohl TabLineSel
    echon g:fzf_copy_msg
    echohl None
    call timer_start(2500, 'FzfClearMsg')
endfunction
function! FzfCopyPath(lines)
    let l:line = a:lines[0]
    let l:path = split(l:line, ':')[0]
    let l:abspath = fnamemodify(l:path, ':p')
    let @+ = l:abspath
    let @* = l:abspath
    let l:display_path = l:abspath
    let l:max_len = &columns - 25
    if len(l:display_path) > l:max_len
        let l:display_path = strpart(l:display_path, 0, l:max_len - 3) . "..."
    endif
    let g:fzf_copy_msg = "✓ Copied path: " . l:display_path
    call timer_start(100, 'FzfEchoDelayed')
endfunction
function! FzfSmartHandler(lines)
    if len(a:lines) < 2
        return
    endif
    let l:key = a:lines[0]
    let l:line = a:lines[1]
    if l:key == 'tab'
        call FzfCopyPath([l:line])
        return
    endif
    let l:force_tab = (tabpagenr() == 1)
    let l:cmd = 'tabedit'
    if !l:force_tab
        if l:key == 'ctrl-x'
            let l:cmd = 'split'
        elseif l:key == 'ctrl-v'
            let l:cmd = 'vsplit'
        elseif l:key == 'ctrl-t'
            let l:cmd = 'tabedit'
        endif
    endif
    let l:grep_data = matchlist(l:line, '^\(.\{-}\):\(\d\+\):\(\d\+\):')
    if !empty(l:grep_data)
        let l:file = l:grep_data[1]
        let l:lnum = l:grep_data[2]
        let l:col = l:grep_data[3]
        execute l:cmd . ' +' . l:lnum . ' ' . fnameescape(l:file)
        call cursor(l:lnum, l:col)
        normal! zz
    else
        execute l:cmd . ' ' . fnameescape(l:line)
    endif
    set number norelativenumber
endfunction
function! StartGlobalFzf(path)
    call fzf#vim#files(a:path, {
    \ 'source': g:fzf_file_walker,
    \ 'sink*': function('FzfSmartHandler'),
    \ 'options': '--expect=tab,ctrl-x,ctrl-v,ctrl-t'
    \ }, 0)
endfunction
function! StartGlobalRg(grep_cmd)
    let l:spec = {
    \ 'sink*': function('FzfSmartHandler'),
    \ 'options': ['--prompt', 'Global> ', '--expect=tab,ctrl-x,ctrl-v,ctrl-t']
    \ }
    call fzf#vim#grep(a:grep_cmd, 1, fzf#vim#with_preview(l:spec), 0)
endfunction
function! RepositoryPickerHandler(winid, bufnr, channel, resume_insert, lines)
    call v:lua.repository_picker_handle(a:winid, a:bufnr, a:channel, a:resume_insert, a:lines)
endfunction
function! RepositoryPickerExit(winid, bufnr, channel, resume_insert, status)
    call v:lua.repository_picker_restore(a:winid, a:bufnr, a:channel, a:resume_insert)
endfunction
function! StartRepositoryFzf(directories, winid, bufnr, channel, resume_insert)
    let l:spec = {
    \ 'source': a:directories,
    \ 'sink*': function('RepositoryPickerHandler', [a:winid, a:bufnr, a:channel, a:resume_insert]),
    \ 'exit': function('RepositoryPickerExit', [a:winid, a:bufnr, a:channel, a:resume_insert]),
    \ 'options': ['--ansi', '--prompt', 'Repos> ', '--expect=tab', '--no-multi']
    \ }
    call fzf#run(fzf#wrap('workspace-directories', l:spec, 0))
endfunction
let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.9, 'relative': 'editor' } }
let g:fzf_action = { 'ctrl-t': 'tabedit', 'ctrl-x': 'split', 'ctrl-v': 'vsplit', 'tab': function('FzfCopyPath') }
]])

-- :Rg — BLines inside a file tab, ripgrep across the whole code workspace
-- from CORE. Registered at VimEnter to replace fzf.vim's own :Rg command.
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        pcall(vim.api.nvim_del_user_command, "Rg")
        _G.smart_rg_search = function(args)
            local is_core = (vim.fn.tabpagenr() == 1)
            if not is_core and vim.bo.buftype == "" then
                vim.cmd("BLines " .. args)
            else
                local grep_cmd = "rg --column --line-number --no-heading --color=always --smart-case "
                    .. rg_common_flags .. " -- " .. vim.fn.shellescape(args) .. " " .. vim.fn.shellescape(workspace.code_root)
                vim.fn.StartGlobalRg(grep_cmd)
            end
        end
        vim.cmd("command! -bang -nargs=* Rg lua _G.smart_rg_search(<q-args>)")
    end
})

return M
