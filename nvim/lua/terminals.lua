-- Embedded terminals and the CORE workspace layout (tree + T1–T4).
local workspace = require("workspace")

-- Expose the host terminal device so child processes (ghostty-theme) can
-- send OSC sequences that bypass nvim's terminal emulator.
if not vim.env.NVIM_HOST_TTY then
    local ps_out = vim.fn.system("ps -o tty= -p " .. vim.fn.getpid())
    local tty_name = vim.trim(ps_out)
    if tty_name ~= "" and tty_name ~= "??" then
        vim.env.NVIM_HOST_TTY = "/dev/" .. tty_name
    end
end

-- Statusline renderer for terminal windows. Must stay on _G: each terminal
-- window's statusline evaluates it through v:lua on redraw.
function _G.my_term_status(winid, label)
    local is_active = (winid == vim.api.nvim_get_current_win())
    local branch = _G.get_git_branch(vim.fn.getcwd())
    if branch ~= "" then branch = " [" .. branch .. "]" end
    if is_active then
        return " " .. label .. branch .. "%=" .. _G.get_mode_info()
    else
        return " " .. label .. branch
    end
end

-- Floating terminal used by the git aliases (glo, gd, ...). Must stay on _G:
-- interceptor.lua invokes it over RPC from nested editor processes.
function _G.open_floating_term(cmd, cwd)
    local buf = vim.api.nvim_create_buf(false, true)
    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * 0.9)
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)
    vim.api.nvim_open_win(buf, true, {
        relative = "editor", width = width, height = height, col = col, row = row, style = "minimal", border = "rounded"
    })
    local shell = os.getenv("SHELL") or "/bin/bash"

    -- Ensure CWD is valid, fallback to nvim's global CWD if not
    if not cwd or cwd == "" or vim.fn.isdirectory(cwd) == 0 then
        cwd = vim.fn.getcwd()
    end

    vim.fn.termopen({shell, "-ic", cmd}, {
        cwd = cwd,
        on_exit = function(job_id, code, event)
            -- If clean exit (0) or fzf canceled (130), cleanly auto-close the window
            if code == 0 or code == 130 then
                pcall(vim.cmd, "bdelete! " .. buf)
            else
                -- If it fails (e.g. not a git repo), keep the window open so the user can read the error!
                vim.schedule(function()
                    vim.cmd("stopinsert")
                    -- Map 'q' and 'Esc' so the user can quickly dismiss the error screen
                    vim.keymap.set('n', 'q', '<cmd>bdelete!<CR>', { buffer = buf, silent = true, nowait = true })
                    vim.keymap.set('n', '<Esc>', '<cmd>bdelete!<CR>', { buffer = buf, silent = true, nowait = true })
                end)
            end
        end
    })
    vim.cmd("startinsert")
end

-- Opens one workspace terminal: a login-like shell whose environment routes
-- editors back into this instance (see interceptor.lua) and wraps the git
-- aliases so they open in a floating terminal.
local function open_sync_terminal(label)
    local shell = os.getenv("SHELL") or "/bin/bash"
    local tmp_bin = vim.fn.stdpath("data") .. "/term_bin"
    local tmp_env = vim.fn.stdpath("data") .. "/term_env"
    vim.fn.mkdir(tmp_bin, "p")
    vim.fn.mkdir(tmp_env, "p")

    os.execute("ln -sf '" .. vim.v.progpath .. "' '" .. tmp_bin .. "/vim'")
    os.execute("ln -sf '" .. vim.v.progpath .. "' '" .. tmp_bin .. "/vi'")
    os.execute("ln -sf '" .. vim.v.progpath .. "' '" .. tmp_bin .. "/nvim'")

    local overrides = [[
        function _f() { NVIM_FLOAT_CWD="$PWD" NVIM_FLOAT_CMD="$*" nvim; }
        alias glo="_f glo" grl="_f grl" gd="_f gd" gso="_f gso" ga="_f ga" grh="_f grh" gi="_f gi" gat="_f gat" gcf="_f gcf" gcff="_f gcff" gcb="_f gcb" gsw="_f gsw" gbd="_f gbd" gct="_f gct" gco="_f gco" grc="_f grc" gclean="_f gclean" gss="_f gss" gsp="_f gsp" gcp="_f gcp" grb="_f grb" gbl="_f gbl" gfu="_f gfu" gsq="_f gsq" grw="_f grw" gwt="_f gwt" gwa="_f gwa" gwd="_f gwd" forgit="_f forgit"
        if [ -f uv.lock ]; then echo "Auto-syncing uv..."; uv sync; fi
    ]]

    local is_zsh = shell:match("zsh$") ~= nil
    local is_bash = shell:match("bash$") ~= nil
    local run_cmd = shell

    if is_zsh then
        local zshrc = tmp_env .. "/.zshrc"
        local zsh_content = 'if [ -f "$HOME/.zshenv" ]; then source "$HOME/.zshenv"; fi\n' ..
                            'if [ -f "$HOME/.zprofile" ]; then source "$HOME/.zprofile"; fi\n' ..
                            'if [ -f "$HOME/.zshrc" ]; then source "$HOME/.zshrc"; fi\n' ..
                            'if [ -f "$HOME/.zlogin" ]; then source "$HOME/.zlogin"; fi\n' ..
                            'export ZDOTDIR="$HOME"\n' ..
                            overrides
        vim.fn.writefile(vim.split(zsh_content, "\n"), zshrc)
        run_cmd = "env ZDOTDIR='" .. tmp_env .. "' " .. shell
    elseif is_bash then
        local bashrc = tmp_env .. "/.bashrc"
        local bash_content = 'if [ -f "$HOME/.bashrc" ]; then source "$HOME/.bashrc"; fi\n' .. overrides
        vim.fn.writefile(vim.split(bash_content, "\n"), bashrc)
        run_cmd = shell .. ' --rcfile "' .. bashrc .. '"'
    else
        run_cmd = shell
    end

    local export_cmds = string.format('export PATH="%s:$PATH"; export EDITOR=nvim; export VISUAL=nvim; export GIT_EDITOR=nvim; export FCEDIT=nvim; ', tmp_bin)

    vim.cmd("terminal " .. export_cmds .. run_cmd)

    local winid = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.statusline = "%!v:lua.my_term_status(" .. winid .. ", '" .. label .. "')"
    local opts = { buffer = buf, silent = true }
    if label == "T1" then
        vim.keymap.set('n', 'K', '<C-w>l', opts); vim.keymap.set('n', 'k', '<C-w>l', opts)
    else
        vim.keymap.set('n', 'j', '<C-w>h', opts); vim.keymap.set('n', 'k', '<C-w>l', opts)
        vim.keymap.set('n', 'J', '<C-w>h', opts); vim.keymap.set('n', 'K', '<C-w>l', opts)
    end
end

vim.api.nvim_create_autocmd({"BufEnter", "WinEnter", "TermOpen"}, {
    callback = function()
        if vim.bo.buftype == "terminal" then
            vim.wo.number = false
            vim.wo.relativenumber = false
        end
    end
})

-- CORE layout: nvim-tree on the left, four terminals (T1–T4) side by side.
local function setup_workspace()
    local api = require("nvim-tree.api")
    api.tree.open({ path = workspace.code_root })
    if #vim.api.nvim_list_wins() == 1 then vim.cmd("vnew") else vim.cmd("wincmd p") end
    vim.cmd("vsplit"); vim.cmd("vsplit"); vim.cmd("vsplit")
    vim.cmd("wincmd h"); vim.cmd("wincmd h"); vim.cmd("wincmd h"); open_sync_terminal("T1")
    vim.cmd("wincmd l"); open_sync_terminal("T2")
    vim.cmd("wincmd l"); open_sync_terminal("T3")
    vim.cmd("wincmd l"); open_sync_terminal("T4")
    vim.cmd("wincmd =")
    vim.cmd("wincmd h"); vim.cmd("wincmd h"); vim.cmd("wincmd h")
end
vim.api.nvim_create_user_command("Workspace", setup_workspace, {})
vim.api.nvim_create_autocmd("VimEnter", { callback = function() if vim.fn.argc() == 0 then setup_workspace() end end })
vim.api.nvim_create_autocmd("DirChanged", { callback = function() vim.cmd("redrawstatus!") end })
vim.api.nvim_create_autocmd("VimResized", { pattern = "*", command = "wincmd =" })
