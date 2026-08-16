-- Headless behavior test for OTemp (lua/otemp.lua).
--
-- Run (the file argument can be any file; without one, VimEnter builds the
-- full CORE workspace, which a headless test doesn't want):
--   env -u NVIM nvim --headless ~/.config/nvim/init.lua \
--     -c "luafile ~/.config/nvim/tests/otemp_test.lua"
-- env -u NVIM matters: inside an embedded nvim terminal the interceptor
-- would route this invocation into the host editor instead.
--
-- Prints one PASS/FAIL line per check; exits non-zero if any check fails.
-- Snapshots are redirected to a temp directory so runs never write into the
-- real code root.

local results = {}
local function check(name, cond)
    table.insert(results, (cond and "PASS  " or "FAIL  ") .. name)
end
local function finish()
    io.stdout:write(table.concat(results, "\n") .. "\n")
    for _, line in ipairs(results) do
        if line:find("^FAIL") then vim.cmd("cq") end
    end
    vim.cmd("qa!")
end

local otemp = require("otemp")
local workspace = require("workspace")
workspace.otemp_dir = vim.fn.tempname() .. "-otemp-saves"

local function float_title_chunks()
    return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).title or {}
end

local function float_title_text()
    local text = ""
    for _, chunk in ipairs(float_title_chunks()) do text = text .. chunk[1] end
    return text
end

local function float_title_hl(substr)
    for _, chunk in ipairs(float_title_chunks()) do
        if chunk[1]:find(substr, 1, true) then return chunk[2] end
    end
    return nil
end

local step2, step3, step4, step5

vim.defer_fn(function()
    otemp.toggle()
    local cfg = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
    check("opens a floating window", cfg.relative == "editor")
    check("scratch buffer is markdown/nofile/unlisted",
        vim.bo.filetype == "markdown" and vim.bo.buftype == "nofile" and not vim.bo.buflisted)
    check("buffer-local m menu map exists", vim.fn.maparg("m", "n", false, true).buffer == 1)
    check("buffer-local Esc close map exists", vim.fn.maparg("<Esc>", "n", false, true).buffer == 1)
    vim.defer_fn(step2, 50) -- startinsert applies after returning to the main loop
end, 700)

step2 = function()
    check("starts in insert mode when empty", vim.api.nvim_get_mode().mode == "i")
    check("insert-mode title shows escape path",
        float_title_text():find("INSERT", 1, true) ~= nil)
    check("insert chip uses OTempInsert color", float_title_hl("INSERT") == "OTempInsert")
    vim.cmd("stopinsert")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line one", "line two", "line three" })
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    otemp.toggle()
    check("toggle closes the float",
        vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative == "")
    otemp.toggle()
    check("content persists across toggles",
        table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") == "line one\nline two\nline three")
    local cur = vim.api.nvim_win_get_cursor(0)
    check("cursor position restored", cur[1] == 2 and cur[2] == 3)
    vim.defer_fn(step3, 50)
end

step3 = function()
    check("reopen with content stays in normal mode", vim.api.nvim_get_mode().mode == "n")
    check("normal-mode title shows menu hint",
        float_title_text():find("NORMAL", 1, true) ~= nil
        and float_title_text():find("m: menu", 1, true) ~= nil
        and not float_title_text():find("INSERT", 1, true))
    check("normal chip uses OTempNormal color", float_title_hl("NORMAL") == "OTempNormal")
    otemp.save_snapshot()
    local saved = vim.fn.glob(workspace.otemp_dir .. "/temptext-*.md", 0, 1)
    check("save writes one snapshot file", #saved == 1)
    check("snapshot content matches buffer",
        #saved == 1 and table.concat(vim.fn.readfile(saved[1]), "\n") == "line one\nline two\nline three")
    otemp.save_snapshot()
    saved = vim.fn.glob(workspace.otemp_dir .. "/temptext-*.md", 0, 1)
    check("second save creates a second file (no clobber)", #saved == 2)

    vim.cmd("tabnew")
    otemp.toggle()
    local cfg = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
    check("toggle from another tab moves the float here",
        cfg.relative == "editor"
        and vim.api.nvim_win_get_tabpage(0) == vim.api.nvim_get_current_tabpage())

    vim.api.nvim_feedkeys("n", "t", false)
    otemp.clear()
    check("clear is cancelled on n", vim.api.nvim_buf_line_count(0) == 3)
    vim.api.nvim_feedkeys("y", "t", false)
    otemp.clear()
    check("clear wipes on y", vim.api.nvim_buf_line_count(0) == 1
        and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "")

    otemp.save_snapshot()
    saved = vim.fn.glob(workspace.otemp_dir .. "/temptext-*.md", 0, 1)
    check("empty pad save is refused", #saved == 2)

    otemp.close()
    check("close() hides the float",
        vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative == "")
    otemp.toggle() -- pad is empty after the clear, so this reopens in insert
    vim.defer_fn(step4, 50)
end

step4 = function()
    vim.cmd("stopinsert")
    vim.defer_fn(step5, 50)
end

step5 = function()
    -- The float was already open when the mode flipped, so only the
    -- ModeChanged autocmd can have retitled it.
    check("title flips to normal hints on mode change",
        float_title_text():find("NORMAL", 1, true) ~= nil
        and not float_title_text():find("INSERT", 1, true))
    finish()
end
