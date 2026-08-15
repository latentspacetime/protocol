-- fzf-powered file search (<Leader>p) and the smart :Rg text search.
--
-- The fzf integration is deliberately Vimscript: fzf.vim's sink*/g:fzf_action
-- contract expects Vimscript funcrefs, and the delayed-echo helpers are timer
-- callbacks that must be named Vimscript functions. Porting them to Lua buys
-- nothing and risks breaking the contract.
local workspace = require("workspace")

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
