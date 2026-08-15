-- Input recovery plus an opt-in diagnostic snapshot for intermittent terminal
-- state failures. The log stays in Neovim's local state directory.
local KEYLOG_SIZE = 100
local LOG_PATH = vim.fn.stdpath("state") .. "/input-diagnostics.log"
local keylog = {}
local keylog_next = 1

vim.on_key(function(_, typed)
    if typed == nil or typed == "" then return end
    keylog[keylog_next] = { vim.loop.hrtime() / 1e6, typed }
    keylog_next = (keylog_next % KEYLOG_SIZE) + 1
end)

local function describe_keys(raw)
    local ok, translated = pcall(vim.fn.keytrans, raw)
    if ok and translated ~= "" then return translated end
    return (raw:gsub(".", function(char)
        return string.format("<0x%02x>", char:byte())
    end))
end

local function keylog_lines()
    local lines = {}
    local previous_ms = nil
    for offset = 0, KEYLOG_SIZE - 1 do
        local entry = keylog[((keylog_next - 1 + offset) % KEYLOG_SIZE) + 1]
        if entry then
            local gap = previous_ms and string.format("+%dms", entry[1] - previous_ms) or "start"
            table.insert(lines, string.format("  %8s  %s", gap, describe_keys(entry[2])))
            previous_ms = entry[1]
        end
    end
    return lines
end

local function state_snapshot()
    local mode = vim.api.nvim_get_mode()
    local lines = {
        string.format("=== %s ===", os.date("%Y-%m-%d %H:%M:%S")),
        string.format(
            "mode=%s blocking=%s paste=%s buftype=%q filetype=%q tab=%d/%d",
            mode.mode,
            tostring(mode.blocking),
            tostring(vim.o.paste),
            vim.bo.buftype,
            vim.bo.filetype,
            vim.fn.tabpagenr(),
            vim.fn.tabpagenr("$")
        ),
        string.format(
            "timeoutlen=%d ttimeoutlen=%d typeahead_pending=%s",
            vim.o.timeoutlen,
            vim.o.ttimeoutlen,
            tostring(vim.fn.getchar(1) ~= 0)
        ),
        string.format("recent raw keys, oldest first (last %d):", KEYLOG_SIZE),
    }
    vim.list_extend(lines, keylog_lines())
    return lines
end

vim.api.nvim_create_user_command("Fix", function()
    vim.cmd("stopinsert")
    vim.o.paste = false
    vim.cmd("nohlsearch")
    vim.cmd("redraw!")
    print("Input state reset. Press CTRL-C first if input remains blocked.")
end, { desc = "Reset recoverable input state" })

vim.api.nvim_create_user_command("Diag", function()
    local file, error_message = io.open(LOG_PATH, "a")
    if not file then
        vim.notify("Cannot write diagnostic log: " .. tostring(error_message), vim.log.levels.ERROR)
        return
    end
    file:write(table.concat(state_snapshot(), "\n"), "\n\n")
    file:close()
    vim.cmd("tabedit " .. vim.fn.fnameescape(LOG_PATH))
    vim.cmd("normal! G")
end, { desc = "Append and open an input-state snapshot" })
