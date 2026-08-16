-- Friction logging from any buffer: :Ugh <message> appends an entry to the
-- shared friction log; :Ugh with no arguments shows the most recent entries.
-- Delegates to the shell's ugh function (loaded by an interactive zsh) so the
-- log format and location keep exactly one owner, the protocol shell module.
local M = {}

-- Directory whose context (path + git branch) the entry records: the current
-- file's directory when the buffer has one, otherwise nvim's working dir.
local function context_dir()
    local dir = vim.fn.expand("%:p:h")
    if dir == "" or vim.fn.isdirectory(dir) == 0 then
        dir = vim.fn.getcwd()
    end
    return dir
end

function M.log(message, on_done)
    local argv
    if message and message ~= "" then
        -- The message travels as one argv element; ugh joins "$@" itself, so
        -- quotes, pipes, and dollar signs survive verbatim.
        argv = { "zsh", "-ic", 'ugh "$@"', "ugh", message }
    else
        argv = { "zsh", "-ic", "ugh" }
    end

    local out, err = {}, {}
    local function collect(list)
        return function(_, data)
            for _, line in ipairs(data or {}) do
                if line ~= "" then table.insert(list, line) end
            end
        end
    end

    local job = vim.fn.jobstart(argv, {
        cwd = context_dir(),
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = collect(out),
        on_stderr = collect(err),
        on_exit = function(_, code)
            local text = table.concat(out, "\n")
            if code ~= 0 then
                text = ("ugh failed (exit %d): %s"):format(
                    code, table.concat(err, " "))
                vim.notify(text, vim.log.levels.ERROR)
            elseif text ~= "" then
                vim.notify(text)
            end
            if on_done then on_done(code, text) end
        end,
    })
    if job <= 0 then
        vim.notify("ugh: could not start zsh", vim.log.levels.ERROR)
        if on_done then on_done(-1, "") end
    end
    return job
end

vim.api.nvim_create_user_command("Ugh", function(opts)
    M.log(opts.args)
end, {
    nargs = "*",
    desc = "Append a friction-log entry, or list recent entries with no args",
})

return M
