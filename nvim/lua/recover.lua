-- Input-state recovery and diagnostics for the intermittent "keys stop
-- working / mode toggling breaks" class of bug.
--
-- A ring buffer records the raw keys nvim actually received, with timing, so
-- the next occurrence produces evidence instead of theories:
--   :Fix   — force every recoverable input state back to a known baseline.
--   :Diag  — append a state snapshot (mode, options, recent raw keys) to the
--            log below and open it. Run it right after the bug strikes or
--            right after it self-heals; the key log shows what nvim received.
--
-- The always-works panic key is native, not configured here: CTRL-C aborts
-- pending mappings, flushes typeahead, and leaves insert mode even when
-- mappings are disabled (e.g. 'paste' is set) — then :Fix cleans up the rest.

local KEYLOG_SIZE = 100
local LOG_PATH = vim.fn.stdpath("state") .. "/input-diagnostics.log"

local keylog = {} -- ring buffer of { ms_since_start, raw_bytes }
local keylog_next = 1

vim.on_key(function(_, typed)
    if typed == nil or typed == "" then return end
    keylog[keylog_next] = { vim.loop.hrtime() / 1e6, typed }
    keylog_next = (keylog_next % KEYLOG_SIZE) + 1
end)

-- Renders raw key bytes readably: keytrans for what it understands ("<Esc>",
-- "j"), hex for anything it can't ("<0x9b>") — malformed sequences are
-- exactly what this log exists to catch.
local function describe_keys(raw)
    local ok, translated = pcall(vim.fn.keytrans, raw)
    if ok and translated ~= "" then return translated end
    return (raw:gsub(".", function(c) return string.format("<0x%02x>", c:byte()) end))
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

-- Caps lock never appears in the key log — the toggle emits no terminal
-- input — yet it inverts every letter's case, silently unmapping every
-- case-sensitive mapping at once (2026-08-15 incidents: jk arrived as "JK",
-- ":Dia" as ":dIA"). Recording the OS's own caps state lets a snapshot
-- distinguish "caps is really on" (accidental press / hardware) from "the
-- terminal is uppercasing on its own" (a Ghostty bug worth reporting).
-- 1 = kCGEventSourceStateHIDSystemState, 0x10000 = kCGEventFlagMaskAlphaShift
-- (CGEventSource.h); the JXA bridge resolves functions but not constants.
local CAPSLOCK_PROBE = "ObjC.import('Cocoa');"
    .. " ($.CGEventSourceFlagsState(1) & 0x10000) != 0 ? 'on' : 'off'"

local function capslock_state()
    if vim.fn.executable("osascript") ~= 1 then return "unavailable" end
    local probe = vim.system(
        { "osascript", "-l", "JavaScript", "-e", CAPSLOCK_PROBE },
        { text = true, timeout = 1000 }):wait()
    local answer = probe.code == 0 and vim.trim(probe.stdout or "") or ""
    if answer ~= "on" and answer ~= "off" then return "unavailable" end
    return answer
end

local function state_snapshot()
    local mode = vim.api.nvim_get_mode()
    local lines = {
        string.format("=== %s ===", os.date("%Y-%m-%d %H:%M:%S")),
        string.format("mode=%s blocking=%s paste=%s buftype=%q filetype=%q tab=%d/%d",
            mode.mode, tostring(mode.blocking), tostring(vim.o.paste),
            vim.bo.buftype, vim.bo.filetype, vim.fn.tabpagenr(), vim.fn.tabpagenr("$")),
        string.format("timeoutlen=%d ttimeoutlen=%d typeahead_pending=%s capslock=%s",
            vim.o.timeoutlen, vim.o.ttimeoutlen, tostring(vim.fn.getchar(1) ~= 0),
            capslock_state()),
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
    print("Input state reset. If keys are still stuck, press CTRL-C first, then :Fix.")
end, { desc = "Reset recoverable input state (mode, paste, search highlight, redraw)" })

vim.api.nvim_create_user_command("Diag", function()
    local snapshot = state_snapshot()
    local file = io.open(LOG_PATH, "a")
    if not file then
        print("Diag failed: cannot write " .. LOG_PATH)
        return
    end
    file:write(table.concat(snapshot, "\n"), "\n\n")
    file:close()
    vim.cmd("tabedit " .. vim.fn.fnameescape(LOG_PATH))
    vim.cmd("normal! G")
end, { desc = "Append input-state snapshot to the diagnostics log and open it" })
