-- Single-keystroke action menus and the clipboard helpers behind them.
-- Three surfaces share the pattern: 'm' in a file tab (file_buffer_menu,
-- mapped in keymaps.lua), 'm' on a tree node (tree_node_menu, wired in
-- tree.lua), and 'm' in the OTemp scratch pad (otemp.lua, built from the
-- primitives this module exports so every menu behaves identically).
-- copy_to_system_clipboard and file_buffer_menu stay on _G: they are invoked
-- from keymap command strings and from tree.lua.

-- Print a message, then clear the echo area after duration_ms.
local function flash(message, duration_ms)
    print(message)
    vim.defer_fn(function() vim.cmd("echo ''"); vim.cmd("redraw") end, duration_ms)
end

-- Reads one key as a menu choice; "" means cancelled (interrupt or a
-- special key that has no single-character form).
local function read_menu_char()
    local ok, char_code = pcall(vim.fn.getchar)
    vim.cmd("redraw")
    if not ok then return "" end
    if type(char_code) == "number" then return vim.fn.nr2char(char_code) end
    if type(char_code) == "string" then return char_code end
    return ""
end

function _G.copy_to_system_clipboard(path)
    vim.fn.setreg("+", path)
    vim.fn.setreg("*", path)
    local display_path = path
    if #display_path > (vim.o.columns - 10) then
        display_path = string.sub(display_path, 1, vim.o.columns - 13) .. "..."
    end
    vim.cmd("redraw")
    flash("Copied: " .. display_path, 2500)
end

local function copy_buffer_content()
    local save_cursor = vim.fn.getpos(".")
    vim.cmd("keepjumps %y+")
    vim.cmd("keepjumps %y*")
    vim.fn.setpos(".", save_cursor)
    flash("✓ Content copied to clipboard.", 2500)
end

local function duplicate_current_file()
    local src_path = vim.fn.expand("%:p")
    if src_path == "" then
        print("Cannot duplicate: Buffer has no file path.")
        return
    end
    local dir = vim.fn.expand("%:p:h")
    local name = vim.fn.expand("%:t:r")
    local ext = vim.fn.expand("%:e")
    if ext ~= "" then ext = "." .. ext end
    local dest = dir .. "/" .. name .. "_1" .. ext
    local i = 1
    while vim.fn.filereadable(dest) == 1 do
        i = i + 1
        dest = dir .. "/" .. name .. "_" .. i .. ext
    end
    local content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    vim.fn.writefile(content, dest)
    vim.cmd("tabedit " .. vim.fn.fnameescape(dest))
    vim.wo.number = true
    vim.wo.relativenumber = false
    print("Duplicated: " .. vim.fn.fnamemodify(dest, ":t"))
end

local function unwrap_clipboard()
    local text = vim.fn.getreg('+')
    if text == '' then
        flash("Clipboard is empty.", 1500)
        return
    end
    local cleaned = text:gsub('(%S) *\n  +', '%1 ')
    if cleaned == text then
        flash("No wrap artifacts found.", 1500)
        return
    end
    vim.fn.setreg('+', cleaned)
    vim.fn.setreg('*', cleaned)
    flash("Clipboard unwrapped.", 2500)
end

vim.api.nvim_create_user_command("ClipFix", unwrap_clipboard, {})

local M = {}

-- Menu primitives, exported so other menu surfaces (otemp.lua) share one
-- mechanism for prompting, confirmation flashes, and whole-buffer copy.
M.flash = flash
M.read_menu_char = read_menu_char
M.copy_buffer_content = copy_buffer_content

function M.rename_current_file()
    local src = vim.fn.expand("%:p")
    if src == "" then
        print("Cannot rename: Buffer has no file path.")
        return
    end
    if vim.bo.modified then
        print("Save the buffer before renaming.")
        return
    end
    local old_name = vim.fn.fnamemodify(src, ":t")
    local new_name = vim.fn.input("Rename to: ", old_name)
    vim.cmd("redraw")
    if new_name == "" or new_name == old_name then
        flash("Rename cancelled.", 1000)
        return
    end
    local dest = vim.fn.fnamemodify(src, ":h") .. "/" .. new_name
    -- The lowercase comparison permits case-only renames on APFS, where the
    -- destination "already exists" as the source itself.
    local case_only = dest:lower() == src:lower()
    if not case_only and (vim.fn.filereadable(dest) == 1 or vim.fn.isdirectory(dest) == 1) then
        print("Cannot rename: " .. new_name .. " already exists.")
        return
    end
    local ok, err = vim.loop.fs_rename(src, dest)
    if not ok then
        print("Rename failed: " .. tostring(err))
        return
    end
    local old_buf = vim.api.nvim_get_current_buf()
    vim.cmd("keepalt edit " .. vim.fn.fnameescape(dest))
    if vim.api.nvim_get_current_buf() ~= old_buf then
        vim.api.nvim_buf_delete(old_buf, { force = true })
    end
    flash("Renamed to " .. new_name, 2500)
end

function M.delete_current_file()
    local path = vim.fn.expand("%:p")
    if path == "" then
        print("Cannot delete: Buffer has no file path.")
        return
    end
    local name = vim.fn.fnamemodify(path, ":t")
    print("Delete " .. name .. "? (y/n)")
    if read_menu_char():lower() ~= "y" then
        flash("Delete cancelled.", 1000)
        return
    end
    local ok, err = vim.loop.fs_unlink(path)
    if not ok then
        print("Delete failed: " .. tostring(err))
        return
    end
    local buf = vim.api.nvim_get_current_buf()
    -- A deleted file's tab has no reason to stay open; CORE (tab 1) and
    -- split layouts keep their window and just drop the buffer.
    if vim.fn.tabpagenr() > 1 and vim.fn.winnr("$") == 1 then
        vim.cmd("tabclose")
    end
    vim.api.nvim_buf_delete(buf, { force = true })
    flash("Deleted " .. name, 2500)
end

function _G.file_buffer_menu()
    vim.schedule(function()
        print("MENU: (c)opy-content (p)ath (d)uplicate (r)ename (x)delete")
        local char = read_menu_char():lower()
        if char == "c" then
            copy_buffer_content()
        elseif char == "p" then
            _G.copy_to_system_clipboard(vim.fn.expand("%:p"))
        elseif char == "d" then
            duplicate_current_file()
        elseif char == "r" then
            M.rename_current_file()
        elseif char == "x" then
            M.delete_current_file()
        else
            flash("Cancelled.", 1000)
        end
    end)
end

-- Instant menu for the tree node under the cursor; api is nvim-tree's api module.
function M.tree_node_menu(node, api)
    print("MENU: (a)Create (d)Delete (r)Rename (p)CopyPath (x)Cut (v)Paste")
    local char = read_menu_char()
    if char == "a" then api.fs.create(node)
    elseif char == "d" then api.fs.remove(node)
    elseif char == "r" then api.fs.rename(node)
    elseif char == "p" then _G.copy_to_system_clipboard(node.absolute_path)
    elseif char == "x" then api.fs.cut(node)
    elseif char == "v" then api.fs.paste(node)
    else print("Cancelled") end
end

return M
