-- Nested-editor interceptor.
-- When an editor command (vi, nvim, git commit) runs inside one of the
-- embedded terminals, $NVIM points at the host instance. This module forwards
-- the request over RPC — files open as host tabs, floating-terminal commands
-- run in a host float — then exits the nested process.
--
-- Must be required before everything else: on the nested path it never
-- returns. Its host-side entry point is _G.open_floating_term (terminals.lua).

-- Exit through the normal teardown path so the nested TUI restores the
-- embedded terminal it drew on (alt screen, bracketed paste, kitty keyboard
-- flags). os.exit() skips that teardown and leaks half-initialized terminal
-- state into the shell that resumes in the pane — a prime suspect for the
-- intermittent "keys stop responding until the pane is cleared" bug.
local function exit_nested()
    pcall(vim.cmd, "qall!")
    os.exit(0) -- reached only if qall! failed; skips teardown but still exits
end

-- Host-side code, sent over one nvim_exec_lua call: when the just-opened
-- buffer leaves its last window, delete the nested process's sentinel file.
-- The nested process then waits on the local filesystem only — the previous
-- design polled the host with an RPC request every 200ms for as long as the
-- tab stayed open, forcing the host to service RPC mid-keystroke.
local HOST_WAIT_REGISTRATION = [[
    local sentinel = ...
    local buf = vim.api.nvim_get_current_buf()
    local group = vim.api.nvim_create_augroup(
        "NestedEditorWait_" .. sentinel:gsub("%W", "_"), { clear = true })
    vim.api.nvim_create_autocmd({ "WinClosed", "BufWinLeave", "BufDelete", "BufUnload" }, {
        group = group,
        callback = function()
            -- Deferred: at WinClosed time the closing window is still listed.
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) > 0 then
                    return
                end
                vim.loop.fs_unlink(sentinel)
                pcall(vim.api.nvim_del_augroup_by_id, group)
            end)
        end,
    })
]]

local host_server = os.getenv("NVIM")
if host_server and host_server ~= "" and host_server ~= vim.v.servername then
    local chan = vim.fn.sockconnect("pipe", host_server, { rpc = true })
    if chan ~= 0 then
        -- Floating Terminal Intercept with CWD forwarding
        local float_cmd = os.getenv("NVIM_FLOAT_CMD")
        if float_cmd and float_cmd ~= "" then
            local float_cwd = os.getenv("NVIM_FLOAT_CWD") or ""
            -- Safely pass parameters through RPC to avoid string escaping issues
            vim.rpcrequest(chan, "nvim_exec_lua", "local cmd, cwd = ...; _G.open_floating_term(cmd, cwd)", { float_cmd, float_cwd })
            vim.fn.chanclose(chan)
            exit_nested()
        end

        local args = vim.fn.argv()
        if #args > 0 then
            for i, arg in ipairs(args) do
                local file = vim.fn.fnamemodify(arg, ":p")
                local cmd = (i == 1) and "tabedit " or "vsplit "
                vim.rpcrequest(chan, "nvim_command", cmd .. vim.fn.fnameescape(file))
            end
            -- The tabedit executes while the host is still in terminal-mode,
            -- which can carry insert mode into the new file tab. Force normal
            -- mode so every tab opened this way starts in a known state.
            vim.rpcrequest(chan, "nvim_command", "stopinsert")

            -- Block until the host closes the tab, so `git commit` and friends
            -- see their editor "exit" only when editing is actually done.
            local sentinel = vim.fn.tempname()
            vim.fn.writefile({}, sentinel)
            vim.rpcrequest(chan, "nvim_exec_lua", HOST_WAIT_REGISTRATION, { sentinel })
            while vim.loop.fs_stat(sentinel) do
                vim.cmd("sleep 200m")
            end
        else
            vim.rpcrequest(chan, "nvim_command", "tabnew")
            vim.rpcrequest(chan, "nvim_command", "stopinsert")
        end
        vim.fn.chanclose(chan)
        exit_nested()
    end
end
