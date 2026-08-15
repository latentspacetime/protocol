-- fzf.vim's sink and action contracts use Vimscript function references, so
-- the integration remains in one Vimscript block instead of wrapping each
-- callback in Lua.
local workspace = require("workspace")

local exclude_globs = {
    "node_modules", ".git", "site-packages", "__pycache__", ".venv", "venv",
    "*.pyc", ".DS_Store", "dist", ".next",
}
local rg_common_flags = "--follow"
for _, glob in ipairs(exclude_globs) do
    rg_common_flags = rg_common_flags .. " --glob " .. vim.fn.shellescape("!" .. glob)
end
vim.g.fzf_file_walker = "rg --files " .. rg_common_flags

vim.cmd([[
function! ProtocolFzfClearMessage(timer)
    echo ""
    redraw
endfunction

function! ProtocolFzfEchoDelayed(timer)
    redraw
    echohl TabLineSel
    echon g:protocol_fzf_copy_message
    echohl None
    call timer_start(2500, 'ProtocolFzfClearMessage')
endfunction

function! ProtocolFzfCopyPath(lines)
    let l:path = split(a:lines[0], ':')[0]
    let l:absolute_path = fnamemodify(l:path, ':p')
    let @+ = l:absolute_path
    let @* = l:absolute_path
    let l:max_length = &columns - 25
    let l:display_path = len(l:absolute_path) > l:max_length
        \ ? strpart(l:absolute_path, 0, l:max_length - 3) . '...'
        \ : l:absolute_path
    let g:protocol_fzf_copy_message = 'Copied path: ' . l:display_path
    call timer_start(100, 'ProtocolFzfEchoDelayed')
endfunction

function! ProtocolFzfOpen(lines)
    if len(a:lines) < 2
        return
    endif
    let l:key = a:lines[0]
    let l:line = a:lines[1]
    if l:key == 'tab'
        call ProtocolFzfCopyPath([l:line])
        return
    endif

    let l:command = 'tabedit'
    if tabpagenr() != 1
        if l:key == 'ctrl-x'
            let l:command = 'split'
        elseif l:key == 'ctrl-v'
            let l:command = 'vsplit'
        endif
    endif

    let l:grep_data = matchlist(l:line, '^\(.\{-}\):\(\d\+\):\(\d\+\):')
    if !empty(l:grep_data)
        execute l:command . ' +' . l:grep_data[2] . ' ' . fnameescape(l:grep_data[1])
        call cursor(l:grep_data[2], l:grep_data[3])
        normal! zz
    else
        execute l:command . ' ' . fnameescape(l:line)
    endif
    set number norelativenumber
endfunction

function! StartGlobalFzf(path)
    call fzf#vim#files(a:path, {
        \ 'source': g:fzf_file_walker,
        \ 'sink*': function('ProtocolFzfOpen'),
        \ 'options': '--expect=tab,ctrl-x,ctrl-v,ctrl-t'
        \ }, 0)
endfunction

function! StartGlobalRg(command)
    let l:spec = {
        \ 'sink*': function('ProtocolFzfOpen'),
        \ 'options': ['--prompt', 'Workspace> ', '--expect=tab,ctrl-x,ctrl-v,ctrl-t']
        \ }
    call fzf#vim#grep(a:command, 1, fzf#vim#with_preview(l:spec), 0)
endfunction

let g:fzf_layout = { 'window': { 'width': 0.9, 'height': 0.9, 'relative': 'editor' } }
let g:fzf_action = {
    \ 'ctrl-t': 'tabedit',
    \ 'ctrl-x': 'split',
    \ 'ctrl-v': 'vsplit',
    \ 'tab': function('ProtocolFzfCopyPath')
    \ }
]])

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        pcall(vim.api.nvim_del_user_command, "Rg")
        _G.protocol_rg_search = function(args)
            if vim.fn.tabpagenr() ~= 1 and vim.bo.buftype == "" then
                vim.cmd("BLines " .. args)
                return
            end
            local command = "rg --column --line-number --no-heading --color=always --smart-case "
                .. rg_common_flags .. " -- " .. vim.fn.shellescape(args) .. " "
                .. vim.fn.shellescape(workspace.code_root)
            vim.fn.StartGlobalRg(command)
        end
        vim.cmd("command! -bang -nargs=* Rg lua _G.protocol_rg_search(<q-args>)")
    end,
})
