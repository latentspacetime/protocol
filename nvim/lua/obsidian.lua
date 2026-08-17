-- :oo (and :Obsidian) raises the real Obsidian app. If the current file
-- is inside the configured vault, the URI opens that note; otherwise it
-- opens the vault. When the vault's nvim-handoff plugin is enabled, the
-- URI is obsidian://nvim so Obsidian can put graph view in a right split.
-- :o is already :edit, so the short form is :oo via a command-line
-- abbreviation. The actual UI cannot live inside nvim or a terminal
-- (Electron), so this is a handoff, not an embed.
local workspace = require("workspace")

local M = {}

M.app_path = "/Applications/Obsidian.app"

local function urlencode(s)
    return (tostring(s):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function normalized(path)
    return vim.fn.resolve(vim.fn.fnamemodify(path, ":p")):gsub("/+$", "")
end

local function is_under(path, root)
    path = normalized(path)
    root = normalized(root)
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function vault_relative(path, vault)
    path = normalized(path)
    vault = normalized(vault)
    if path == vault then return "" end
    local prefix = vault .. "/"
    if path:sub(1, #prefix) == prefix then
        return path:sub(#prefix + 1)
    end
    return ""
end

function M.handoff_enabled()
    if M._handoff_enabled ~= nil then return M._handoff_enabled end
    local vault = workspace.vault_root
    local list_path = vault .. "/.obsidian/community-plugins.json"
    if vim.fn.filereadable(list_path) == 0 then return false end
    if vim.fn.filereadable(vault .. "/.obsidian/plugins/nvim-handoff/main.js") == 0 then
        return false
    end
    local ok, data = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(list_path), "\n"))
    if not ok or type(data) ~= "table" then return false end
    for _, id in ipairs(data) do
        if id == "nvim-handoff" then return true end
    end
    return false
end

function M.uri_for(path)
    local vault = workspace.vault_root
    local vault_name = vim.fn.fnamemodify(vault, ":t")
    if M.handoff_enabled() then
        local uri = "obsidian://nvim?vault=" .. urlencode(vault_name)
        if path and path ~= "" and is_under(path, vault) then
            local rel = vault_relative(path, vault)
            if rel ~= "" then
                uri = uri .. "&file=" .. urlencode(rel)
            end
        end
        return uri
    end
    if path and path ~= "" and is_under(path, vault) then
        return "obsidian://open?path=" .. urlencode(normalized(path))
    end
    return "obsidian://open?vault=" .. urlencode(vault_name)
end

function M.open(path)
    if vim.fn.isdirectory(M.app_path) == 0 then
        vim.notify("Obsidian.app is not installed at " .. M.app_path, vim.log.levels.ERROR)
        return false
    end
    local uri = M.uri_for(path)
    if M._open then
        M._open(uri)
        return true
    end
    if vim.fn.executable("open") ~= 1 then
        vim.notify(":Obsidian needs macOS open(1) to launch the app", vim.log.levels.ERROR)
        return false
    end
    local result = vim.system({ "open", uri }, { text = true, timeout = 5000 }):wait()
    if result.code ~= 0 then
        local detail = vim.trim(result.stderr or result.stdout or "")
        if detail == "" then detail = "exit " .. tostring(result.code) end
        vim.notify("open failed: " .. detail, vim.log.levels.ERROR)
        return false
    end
    return true
end

vim.api.nvim_create_user_command("Obsidian", function()
    local path = vim.api.nvim_buf_get_name(0)
    if vim.bo.modified and vim.bo.buftype == "" and path ~= "" then
        vim.cmd("update")
    end
    M.open(path)
end, {
    desc = "Open the current vault note, or the vault, in Obsidian",
})

-- User commands must start with an uppercase letter, so :oo is an abbrev
-- that expands only when it is the entire command line.
vim.cmd([[cnoreabbrev <expr> oo (getcmdtype() == ':' && getcmdline() == 'oo') ? 'Obsidian' : 'oo']])

return M
