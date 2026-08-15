local workspace = require("workspace")

function _G.protocol_terminal_status(window, label)
    local branch = _G.get_git_branch(vim.fn.getcwd())
    if branch ~= "" then branch = " [" .. branch .. "]" end
    if window == vim.api.nvim_get_current_win() then
        return " " .. label .. branch .. "%=" .. _G.get_mode_info()
    end
    return " " .. label .. branch
end

-- This host-side entry point is global because interceptor.lua invokes it over
-- RPC from a nested Neovim process.
function _G.open_floating_term(command, directory)
    if type(command) ~= "string" or command == "" then
        vim.notify("Floating terminal command is empty", vim.log.levels.ERROR)
        return
    end
    if not directory or directory == "" or vim.fn.isdirectory(directory) == 0 then
        directory = vim.fn.getcwd()
    end

    local buffer = vim.api.nvim_create_buf(false, true)
    local width = math.max(math.floor(vim.o.columns * 0.9), 20)
    local height = math.max(math.floor(vim.o.lines * 0.9), 5)
    vim.api.nvim_open_win(buffer, true, {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        style = "minimal",
        border = "rounded",
    })

    local shell = os.getenv("SHELL") or "/bin/sh"
    vim.fn.termopen({ shell, "-ic", command }, {
        cwd = directory,
        on_exit = function(_, exit_code)
            if exit_code == 0 or exit_code == 130 then
                vim.schedule(function()
                    if vim.api.nvim_buf_is_valid(buffer) then
                        vim.api.nvim_buf_delete(buffer, { force = true })
                    end
                end)
                return
            end
            vim.schedule(function()
                vim.cmd("stopinsert")
                vim.keymap.set("n", "q", "<cmd>bdelete!<CR>", { buffer = buffer, silent = true, nowait = true })
                vim.keymap.set("n", "<Esc>", "<cmd>bdelete!<CR>", { buffer = buffer, silent = true, nowait = true })
            end)
        end,
    })
    vim.cmd("startinsert")
end

local function open_workspace_terminal(label)
    local shell = os.getenv("SHELL") or "/bin/sh"
    local runtime_bin = vim.fn.stdpath("data") .. "/protocol-term-bin"
    local runtime_env = vim.fn.stdpath("data") .. "/protocol-term-env"
    vim.fn.mkdir(runtime_bin, "p")
    vim.fn.mkdir(runtime_env, "p")

    for _, editor in ipairs({ "vim", "vi", "nvim" }) do
        vim.loop.fs_unlink(runtime_bin .. "/" .. editor)
        local ok, error_message = vim.loop.fs_symlink(vim.v.progpath, runtime_bin .. "/" .. editor)
        if not ok then
            vim.notify("Cannot create editor link: " .. tostring(error_message), vim.log.levels.ERROR)
            return
        end
    end

    local run_command = shell
    if shell:match("zsh$") then
        local zshrc = runtime_env .. "/.zshrc"
        local lines = {
            '[[ -f "$HOME/.zshenv" ]] && source "$HOME/.zshenv"',
            '[[ -f "$HOME/.zprofile" ]] && source "$HOME/.zprofile"',
            '[[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"',
            '[[ -f "$HOME/.zlogin" ]] && source "$HOME/.zlogin"',
            'export ZDOTDIR="$HOME"',
        }
        if vim.fn.writefile(lines, zshrc) ~= 0 then
            vim.notify("Cannot prepare embedded zsh configuration", vim.log.levels.ERROR)
            return
        end
        run_command = "env ZDOTDIR=" .. vim.fn.shellescape(runtime_env) .. " " .. vim.fn.shellescape(shell)
    elseif shell:match("bash$") then
        local bashrc = runtime_env .. "/.bashrc"
        if vim.fn.writefile({ '[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"' }, bashrc) ~= 0 then
            vim.notify("Cannot prepare embedded bash configuration", vim.log.levels.ERROR)
            return
        end
        run_command = vim.fn.shellescape(shell) .. " --rcfile " .. vim.fn.shellescape(bashrc)
    end

    local exports = string.format(
        'export PATH=%s:"$PATH" EDITOR=nvim VISUAL=nvim GIT_EDITOR=nvim FCEDIT=nvim; ',
        vim.fn.shellescape(runtime_bin)
    )
    vim.cmd("terminal " .. exports .. run_command)

    local window = vim.api.nvim_get_current_win()
    local buffer = vim.api.nvim_get_current_buf()
    vim.wo.number = false
    vim.wo.relativenumber = false
    vim.wo.statusline = "%!v:lua.protocol_terminal_status(" .. window .. ", '" .. label .. "')"
    local options = { buffer = buffer, silent = true }
    if label == "T1" then
        vim.keymap.set("n", "K", "<C-w>l", options)
        vim.keymap.set("n", "k", "<C-w>l", options)
    else
        vim.keymap.set("n", "j", "<C-w>h", options)
        vim.keymap.set("n", "k", "<C-w>l", options)
        vim.keymap.set("n", "J", "<C-w>h", options)
        vim.keymap.set("n", "K", "<C-w>l", options)
    end
end

vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TermOpen" }, {
    callback = function()
        if vim.bo.buftype == "terminal" then
            vim.wo.number = false
            vim.wo.relativenumber = false
        end
    end,
})

local function setup_workspace()
    if vim.fn.isdirectory(workspace.code_root) == 0 then
        vim.notify("Workspace directory does not exist: " .. workspace.code_root, vim.log.levels.ERROR)
        return
    end

    require("nvim-tree.api").tree.open({ path = workspace.code_root })
    if #vim.api.nvim_list_wins() == 1 then vim.cmd("vnew") else vim.cmd("wincmd p") end
    vim.cmd("vsplit")
    vim.cmd("vsplit")
    vim.cmd("vsplit")
    vim.cmd("wincmd h")
    vim.cmd("wincmd h")
    vim.cmd("wincmd h")
    open_workspace_terminal("T1")
    vim.cmd("wincmd l")
    open_workspace_terminal("T2")
    vim.cmd("wincmd l")
    open_workspace_terminal("T3")
    vim.cmd("wincmd l")
    open_workspace_terminal("T4")
    vim.cmd("wincmd =")
    vim.cmd("wincmd h")
    vim.cmd("wincmd h")
    vim.cmd("wincmd h")
end

vim.api.nvim_create_user_command("Workspace", setup_workspace, {})
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        if vim.fn.argc() == 0 then setup_workspace() end
    end,
})
vim.api.nvim_create_autocmd("DirChanged", { callback = function() vim.cmd("redrawstatus!") end })
vim.api.nvim_create_autocmd("VimResized", { pattern = "*", command = "wincmd =" })
