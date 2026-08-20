-- OTemp: a floating scratch pad for prompts and quick notes (<Leader>o).
--
-- One scratch buffer lives for the whole nvim session. Closing the float only
-- hides it — the text survives until :qa or an explicit (x)clear — and nothing
-- touches the filesystem unless (s)ave is chosen, which snapshots the text to
-- workspace.otemp_dir as temptext-<timestamp>.md. It is a real markdown
-- buffer, so editing, search, and paste are all native; the only keys the pad
-- adds are buffer-local: 'm' (menu, same convention as file tabs and tree
-- nodes) and <Esc> in normal mode (close — from insert, Esc Esc exits).
-- The float title tracks the mode with a colored INSERT/NORMAL chip; the
-- insert variant spells out the path to the menu, since m/esc only act as
-- hinted in normal mode.
local workspace = require("workspace")
local menus = require("menus")

local M = {}

local augroup = vim.api.nvim_create_augroup("OTemp", { clear = true })

local scratch_buf = nil  -- session-lifetime scratch buffer, created lazily
local float_win = nil    -- current float window, nil while hidden
local saved_cursor = nil -- cursor position carried across hide/show

local function unwrap_text(text)
    return text:gsub('(%S) *\n\n?  +', '%1 ')
end

local orig_paste = vim.paste
vim.paste = function(lines, phase)
    if scratch_buf and vim.api.nvim_buf_is_valid(scratch_buf)
        and vim.api.nvim_get_current_buf() == scratch_buf then
        local text = table.concat(lines, '\n')
        local cleaned = unwrap_text(text)
        if cleaned ~= text then
            lines = vim.split(cleaned, '\n', { plain = true })
        end
    end
    return orig_paste(lines, phase)
end

local function scratch_is_empty()
    if not (scratch_buf and vim.api.nvim_buf_is_valid(scratch_buf)) then
        return true
    end
    return vim.api.nvim_buf_line_count(scratch_buf) == 1
        and vim.api.nvim_buf_get_lines(scratch_buf, 0, 1, false)[1] == ""
end

function M.close()
    if not (float_win and vim.api.nvim_win_is_valid(float_win)) then
        float_win = nil
        return
    end
    saved_cursor = vim.api.nvim_win_get_cursor(float_win)
    -- The global <Esc> map (nohlsearch) is shadowed inside the pad, so clear
    -- the highlight here to keep close-by-Esc consistent with plain Esc.
    vim.cmd("nohlsearch")
    -- force=false loses nothing: the scratch buffer is bufhidden=hide. It can
    -- only fail if a modified file buffer was opened into the float window,
    -- and refusing to discard that is the honest outcome.
    local ok, err = pcall(vim.api.nvim_win_close, float_win, false)
    if not ok then
        print("OTemp close failed: " .. tostring(err))
        return
    end
    float_win = nil
end

function M.save_snapshot()
    if scratch_is_empty() then
        menus.flash("Nothing to save.", 1500)
        return
    end
    if not pcall(vim.fn.mkdir, workspace.otemp_dir, "p") then
        print("Save failed: cannot create " .. workspace.otemp_dir)
        return
    end
    local stamp = os.date("%Y-%m-%d-%H%M%S")
    local path = workspace.otemp_dir .. "/temptext-" .. stamp .. ".md"
    local counter = 1
    while vim.fn.filereadable(path) == 1 do
        counter = counter + 1
        path = workspace.otemp_dir .. "/temptext-" .. stamp .. "-" .. counter .. ".md"
    end
    local lines = vim.api.nvim_buf_get_lines(scratch_buf, 0, -1, false)
    local ok, result = pcall(vim.fn.writefile, lines, path)
    if not ok or result ~= 0 then
        print("Save failed: " .. path)
        return
    end
    menus.flash("Saved: " .. vim.fn.fnamemodify(path, ":~"), 3000)
end

function M.clear()
    if scratch_is_empty() then
        menus.flash("Nothing to clear.", 1500)
        return
    end
    print("Clear all OTemp text? (y/n)")
    if menus.read_menu_char():lower() ~= "y" then
        menus.flash("Clear cancelled.", 1000)
        return
    end
    vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, {})
    saved_cursor = nil
    menus.flash("Cleared.", 1500)
    if float_win and vim.api.nvim_win_is_valid(float_win)
        and vim.api.nvim_get_current_win() == float_win then
        vim.cmd("startinsert")
    end
end

local function otemp_menu()
    vim.schedule(function()
        print("OTEMP: (c)opy-all (s)ave (x)clear")
        local char = menus.read_menu_char():lower()
        if char == "c" then
            menus.copy_buffer_content()
        elseif char == "s" then
            M.save_snapshot()
        elseif char == "x" then
            M.clear()
        else
            menus.flash("Cancelled.", 1000)
        end
    end)
end

local function ensure_scratch_buf()
    if scratch_buf and vim.api.nvim_buf_is_valid(scratch_buf) then
        return scratch_buf
    end
    -- (unlisted, scratch): buftype=nofile, bufhidden=hide, no swapfile —
    -- hidden from :ls, survives hiding, and :w fails honestly (menu (s)ave is
    -- the one save mechanism).
    scratch_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[scratch_buf].filetype = "markdown"
    local opts = { buffer = scratch_buf, silent = true, nowait = true }
    vim.keymap.set("n", "m", otemp_menu, opts)
    vim.keymap.set("n", "<Esc>", M.close, opts)
    for _, key in ipairs({ "p", "P" }) do
        vim.keymap.set("n", key, function()
            local reg = vim.v.register
            local content = vim.fn.getreg(reg)
            local cleaned = unwrap_text(content)
            if cleaned ~= content then
                vim.fn.setreg(reg, cleaned, vim.fn.getregtype(reg))
            end
            return '"' .. reg .. key
        end, { buffer = scratch_buf, expr = true, silent = true, nowait = true })
    end
    return scratch_buf
end

-- Title as [text, highlight] chunks; the chip groups OTempInsert/OTempNormal
-- are defined with the rest of the palette in appearance.lua.
local function float_title(mode)
    if mode:find("^i") then
        return {
            { " OTemp ", "FloatTitle" },
            { " INSERT ", "OTempInsert" },
            { " esc, then m: menu ", "FloatTitle" },
        }
    end
    return {
        { " OTemp ", "FloatTitle" },
        { " NORMAL ", "OTempNormal" },
        { " m: menu · esc: close ", "FloatTitle" },
    }
end

vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    callback = function()
        if not (float_win and vim.api.nvim_win_is_valid(float_win)) then return end
        if vim.api.nvim_get_current_win() ~= float_win then return end
        vim.api.nvim_win_set_config(float_win, {
            title = float_title(vim.v.event.new_mode),
            title_pos = "center",
        })
    end,
})

local function open_float()
    local buf = ensure_scratch_buf()
    local width = math.floor(vim.o.columns * 0.7)
    local height = math.floor(vim.o.lines * 0.7)
    float_win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        border = "rounded",
        -- startinsert below lands after this function returns; setting the
        -- matching title here avoids a one-frame normal-mode title.
        title = float_title(scratch_is_empty() and "i" or "n"),
        title_pos = "center",
    })
    vim.wo[float_win].linebreak = true
    if scratch_is_empty() then
        vim.cmd("startinsert")
    elseif saved_cursor then
        pcall(vim.api.nvim_win_set_cursor, float_win, saved_cursor)
    end
end

function M.toggle()
    if float_win and vim.api.nvim_win_is_valid(float_win) then
        local was_in_current_tab =
            (vim.api.nvim_win_get_tabpage(float_win) == vim.api.nvim_get_current_tabpage())
        M.close()
        if float_win ~= nil then return end -- close failed and said why
        if was_in_current_tab then return end
        -- The float was left open in another tab; fall through to reopen here.
    end
    open_float()
end

return M
