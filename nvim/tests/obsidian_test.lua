-- Headless behavior test for :Obsidian (lua/obsidian.lua).
--
-- Run (the file argument avoids the full CORE workspace on VimEnter):
--   env -u NVIM nvim --headless nvim/init.lua \
--     -c "luafile nvim/tests/obsidian_test.lua"
-- env -u NVIM matters: inside an embedded nvim terminal the interceptor
-- would route this invocation into the host editor instead.
--
-- Prints one PASS/FAIL line per check; exits non-zero if any check fails.
-- The real Obsidian app is never launched: the opener is injected.

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

vim.notify = function() end

local workspace = require("workspace")
local obsidian = require("obsidian")

local vault = vim.fn.tempname() .. "-vault"
vim.fn.mkdir(vault, "p")
vim.fn.mkdir(vault .. "/Context", "p")
local note = vault .. "/Context/a note.md"
vim.fn.writefile({ "hello" }, note)
workspace.vault_root = vault

local opened = {}
obsidian._open = function(uri) table.insert(opened, uri) end
obsidian.app_path = vault
obsidian._handoff_enabled = false

check(":Obsidian command exists", vim.fn.exists(":Obsidian") == 2)

local note_uri = obsidian.uri_for(note)
local encoded = note_uri:match("path=(.*)$") or ""
check("vault file uses path URI", note_uri:find("^obsidian://open%?path=") == 1)
check("path URI encodes spaces and slashes",
    encoded:find("a%20note.md", 1, true) ~= nil
    and encoded:find("%2F", 1, true) ~= nil
    and encoded:find("/", 1, true) == nil)

local outside = vim.fn.tempname() .. "-outside.md"
check("outside file opens the vault by folder name",
    obsidian.uri_for(outside) == "obsidian://open?vault=" .. vim.fn.fnamemodify(vault, ":t"))
check("empty path opens the vault",
    obsidian.uri_for("") == "obsidian://open?vault=" .. vim.fn.fnamemodify(vault, ":t"))

check("open succeeds when the app path exists", obsidian.open(note) == true)
check("injected opener received the note URI", opened[1] == note_uri)

opened = {}
vim.cmd.edit(vim.fn.fnameescape(note))
vim.fn.feedkeys(":oo\n", "xt")
check(":oo expands to :Obsidian", opened[1] == note_uri)

obsidian.app_path = vault
obsidian._handoff_enabled = true
local handoff_note = obsidian.uri_for(note)
local handoff_vault = obsidian.uri_for("")
check("handoff URI uses the nvim action",
    handoff_note:find("^obsidian://nvim%?vault=", 1) == 1)
check("handoff URI carries a vault-relative file",
    handoff_note:find("file=Context%2Fa%20note.md", 1, true) ~= nil)
check("handoff vault-only URI has no file param",
    handoff_vault == "obsidian://nvim?vault=" .. vim.fn.fnamemodify(vault, ":t"))

obsidian.app_path = vault .. "-missing-app"
opened = {}
check("missing app fails instead of launching", obsidian.open(note) == false)
check("missing app does not call the opener", #opened == 0)

finish()
