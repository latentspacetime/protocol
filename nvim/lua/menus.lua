local function flash(message, duration_ms)
    print(message)
    vim.defer_fn(function()
        vim.cmd("echo ''")
        vim.cmd("redraw")
    end, duration_ms)
end

local function read_menu_char()
    local ok, char_code = pcall(vim.fn.getchar)
    vim.cmd("redraw")
    if not ok then return "" end
    if type(char_code) == "number" then return vim.fn.nr2char(char_code) end
    if type(char_code) == "string" then return char_code end
    return ""
end

function _G.copy_to_system_clipboard(value)
    vim.fn.setreg("+", value)
    vim.fn.setreg("*", value)
    local display_value = value
    local max_length = math.max(vim.o.columns - 10, 20)
    if #display_value > max_length then
        display_value = display_value:sub(1, max_length - 3) .. "..."
    end
    vim.cmd("redraw")
    flash("Copied: " .. display_value, 2500)
end

local function copy_buffer_content()
    local cursor = vim.fn.getpos(".")
    vim.cmd("keepjumps %y+")
    vim.cmd("keepjumps %y*")
    vim.fn.setpos(".", cursor)
    flash("Content copied to clipboard.", 2500)
end

local function duplicate_current_file()
    local source_path = vim.fn.expand("%:p")
    if source_path == "" then
        print("Cannot duplicate a buffer without a file path.")
        return
    end

    local directory = vim.fn.expand("%:p:h")
    local stem = vim.fn.expand("%:t:r")
    local extension = vim.fn.expand("%:e")
    if extension ~= "" then extension = "." .. extension end

    local suffix = 1
    local destination = directory .. "/" .. stem .. "_" .. suffix .. extension
    while vim.fn.filereadable(destination) == 1 do
        suffix = suffix + 1
        destination = directory .. "/" .. stem .. "_" .. suffix .. extension
    end

    local content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if vim.fn.writefile(content, destination) ~= 0 then
        print("Duplicate failed: could not write " .. destination)
        return
    end
    vim.cmd("tabedit " .. vim.fn.fnameescape(destination))
    print("Duplicated: " .. vim.fn.fnamemodify(destination, ":t"))
end

local function unwrap_clipboard()
    local text = vim.fn.getreg("+")
    if text == "" then
        flash("Clipboard is empty.", 1500)
        return
    end
    local cleaned = text:gsub("(%S) *\n  +", "%1 ")
    if cleaned == text then
        flash("No wrap artifacts found.", 1500)
        return
    end
    vim.fn.setreg("+", cleaned)
    vim.fn.setreg("*", cleaned)
    flash("Clipboard unwrapped.", 2500)
end

vim.api.nvim_create_user_command("ClipFix", unwrap_clipboard, {})

local M = {}

function M.rename_current_file()
    local source_path = vim.fn.expand("%:p")
    if source_path == "" then
        print("Cannot rename a buffer without a file path.")
        return
    end
    if vim.bo.modified then
        print("Save the buffer before renaming.")
        return
    end

    local old_name = vim.fn.fnamemodify(source_path, ":t")
    local new_name = vim.fn.input("Rename to: ", old_name)
    vim.cmd("redraw")
    if new_name == "" or new_name == old_name then
        flash("Rename cancelled.", 1000)
        return
    end
    if new_name:find("/", 1, true) then
        print("Rename failed: enter a file name, not a path.")
        return
    end

    local destination = vim.fn.fnamemodify(source_path, ":h") .. "/" .. new_name
    local case_only = destination:lower() == source_path:lower()
    if not case_only and (vim.fn.filereadable(destination) == 1 or vim.fn.isdirectory(destination) == 1) then
        print("Cannot rename: destination already exists.")
        return
    end

    local ok, error_message = vim.loop.fs_rename(source_path, destination)
    if not ok then
        print("Rename failed: " .. tostring(error_message))
        return
    end

    local old_buffer = vim.api.nvim_get_current_buf()
    vim.cmd("keepalt edit " .. vim.fn.fnameescape(destination))
    if vim.api.nvim_get_current_buf() ~= old_buffer then
        vim.api.nvim_buf_delete(old_buffer, { force = true })
    end
    flash("Renamed to " .. new_name, 2500)
end

function M.delete_current_file()
    local path = vim.fn.expand("%:p")
    if path == "" then
        print("Cannot delete a buffer without a file path.")
        return
    end
    if vim.bo.modified then
        print("Save or discard buffer changes before deleting.")
        return
    end

    local name = vim.fn.fnamemodify(path, ":t")
    print("Delete " .. name .. "? (y/n)")
    if read_menu_char():lower() ~= "y" then
        flash("Delete cancelled.", 1000)
        return
    end

    local ok, error_message = vim.loop.fs_unlink(path)
    if not ok then
        print("Delete failed: " .. tostring(error_message))
        return
    end

    local buffer = vim.api.nvim_get_current_buf()
    if vim.fn.tabpagenr() > 1 and vim.fn.winnr("$") == 1 then
        vim.cmd("tabclose")
    end
    if vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_delete(buffer, { force = true })
    end
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

function M.tree_node_menu(node, api)
    print("MENU: (a)create (d)delete (r)rename (p)copy-path (x)cut (v)paste")
    local char = read_menu_char():lower()
    if char == "a" then api.fs.create(node)
    elseif char == "d" then api.fs.remove(node)
    elseif char == "r" then api.fs.rename(node)
    elseif char == "p" then _G.copy_to_system_clipboard(node.absolute_path)
    elseif char == "x" then api.fs.cut(node)
    elseif char == "v" then api.fs.paste(node)
    else flash("Cancelled.", 1000) end
end

return M
