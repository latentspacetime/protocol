-- A nested editor forwards files to the host Neovim process, then waits until
-- the host closes them. The sentinel keeps the wait local instead of polling
-- the host RPC channel while the user types.
local function exit_nested()
    pcall(vim.cmd, "qall!")
    os.exit(0)
end

local HOST_WAIT_REGISTRATION = [[
    local sentinel = ...
    local buffer = vim.api.nvim_get_current_buf()
    local group = vim.api.nvim_create_augroup(
        "NestedEditorWait_" .. sentinel:gsub("%W", "_"), { clear = true })
    vim.api.nvim_create_autocmd({ "WinClosed", "BufWinLeave", "BufDelete", "BufUnload" }, {
        group = group,
        callback = function()
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buffer) and #vim.fn.win_findbuf(buffer) > 0 then
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
    local channel = vim.fn.sockconnect("pipe", host_server, { rpc = true })
    if channel ~= 0 then
        local float_command = os.getenv("NVIM_FLOAT_CMD")
        if float_command and float_command ~= "" then
            local float_directory = os.getenv("NVIM_FLOAT_CWD") or ""
            vim.rpcrequest(
                channel,
                "nvim_exec_lua",
                "local command, directory = ...; _G.open_floating_term(command, directory)",
                { float_command, float_directory }
            )
            vim.fn.chanclose(channel)
            exit_nested()
        end

        local arguments = vim.fn.argv()
        if #arguments > 0 then
            for index, argument in ipairs(arguments) do
                local path = vim.fn.fnamemodify(argument, ":p")
                local command = index == 1 and "tabedit " or "vsplit "
                vim.rpcrequest(channel, "nvim_command", command .. vim.fn.fnameescape(path))
            end
            vim.rpcrequest(channel, "nvim_command", "stopinsert")

            local sentinel = vim.fn.tempname()
            vim.fn.writefile({}, sentinel)
            vim.rpcrequest(channel, "nvim_exec_lua", HOST_WAIT_REGISTRATION, { sentinel })
            while vim.loop.fs_stat(sentinel) do
                vim.cmd("sleep 200m")
            end
        else
            vim.rpcrequest(channel, "nvim_command", "tabnew")
            vim.rpcrequest(channel, "nvim_command", "stopinsert")
        end

        vim.fn.chanclose(channel)
        exit_nested()
    end
end
