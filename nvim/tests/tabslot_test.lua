-- Headless behavior test for instance slot allocation (lua/tabslot.lua).
--
-- Run (the file argument avoids the full CORE workspace on VimEnter):
--   env -u NVIM nvim --headless ~/.config/nvim/init.lua \
--     -c "luafile ~/.config/nvim/tests/tabslot_test.lua"
-- env -u NVIM matters: inside an embedded nvim terminal the interceptor
-- would route this invocation into the host editor instead.
--
-- Prints one PASS/FAIL line per check; exits non-zero if any check fails.
-- Claims run against temp directories, never the real slot dir.

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

local tabslot = require("tabslot")
local dir_count = 0
local function fresh_dir()
    dir_count = dir_count + 1
    local dir = vim.fn.tempname() .. "-tab-slots-" .. dir_count
    vim.fn.mkdir(dir, "p")
    return dir
end

local function plant(dir, slot, content)
    local f = assert(io.open(dir .. "/" .. slot, "w"))
    f:write(content)
    f:close()
end

local function slurp(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- Empty dir: lowest slot wins and the Neovim server address is recorded.
local dir = fresh_dir()
local slot, identity = tabslot.claim(dir)
check("empty dir claims slot 0", slot == 0)
check("slot file records server identity",
    identity ~= nil and slurp(dir .. "/0") == identity
    and identity == vim.v.servername)

-- A slot owned by another live Neovim server is skipped.
dir = fresh_dir()
local live_server = vim.fn.serverstart()
plant(dir, 0, live_server)
check("live-owned slot is skipped", tabslot.claim(dir) == 1)
vim.fn.serverstop(live_server)

-- Legacy PID-only files cannot identify a live server and are reclaimed.
dir = fresh_dir()
plant(dir, 0, tostring(vim.uv.os_getppid()))
check("PID-only stale slot is reclaimed", tabslot.claim(dir) == 0)

-- A stopped server cannot keep its slot.
dir = fresh_dir()
local dead_server = vim.fn.serverstart()
vim.fn.serverstop(dead_server)
plant(dir, 0, dead_server)
slot, identity = tabslot.claim(dir)
check("dead-server slot is reclaimed", slot == 0)
check("reclaimed slot records new owner", slurp(dir .. "/0") == identity)

-- Re-sourcing in the same Neovim reclaims its existing identity.
dir = fresh_dir()
slot, identity = tabslot.claim(dir)
check("own-server slot is reclaimed", tabslot.claim(dir) == 0)

-- Garbage content has no live owner.
dir = fresh_dir()
plant(dir, 0, "not-a-pid")
check("garbage slot file is reclaimed", tabslot.claim(dir) == 0)

-- Release removes the file and tolerates a missing one.
dir = fresh_dir()
slot, identity = tabslot.claim(dir)
tabslot.release(dir, slot, identity)
check("release removes the slot file", slurp(dir .. "/" .. slot) == nil)
check("release of a freed slot is a no-op",
    (pcall(tabslot.release, dir, slot, identity)))

-- A late release cannot delete a slot that has changed owners.
dir = fresh_dir()
slot, identity = tabslot.claim(dir)
local path = dir .. "/" .. slot
plant(dir, slot, "replacement owner")
tabslot.release(dir, slot, identity)
check("release preserves a replacement owner", slurp(path) == "replacement owner")

-- Real concurrent claimants must receive distinct contiguous slots. Each
-- child holds its claim long enough for every sibling to allocate.
dir = fresh_dir()
local worker = vim.fn.tempname() .. "-tabslot-worker.lua"
vim.fn.writefile({
    'package.path = vim.fn.stdpath("config") .. "/lua/?.lua;" .. package.path',
    'local tabslot = require("tabslot")',
    'local slot, identity = tabslot.claim(arg[1])',
    'if slot == nil then vim.cmd("cq") end',
    'io.stdout:write(tostring(slot) .. "\\n")',
    'vim.uv.sleep(500)',
    'tabslot.release(arg[1], slot, identity)',
}, worker)
local jobs = {}
for _ = 1, 4 do
    table.insert(jobs, vim.system({
        "nvim", "--headless", "-u", "NONE", "-l", worker, dir,
    }, { text = true }))
end
local claimed = {}
local workers_ok = true
for _, job in ipairs(jobs) do
    local result = job:wait(5000)
    local claimed_slot = tonumber(vim.trim(result.stdout or ""))
    workers_ok = workers_ok and result.code == 0 and claimed_slot ~= nil
    table.insert(claimed, claimed_slot)
end
os.remove(worker)
table.sort(claimed)
check("concurrent claimants receive unique contiguous slots",
    workers_ok and table.concat(claimed, ",") == "0,1,2,3")

-- appearance.lua wired the claimed slot into the terminal title. The label
-- starts bracketed because a launching instance holds focus.
local instance = vim.o.titlestring:match("^%[ NVIM (%d+) %]$")
check("titlestring shows the bracketed NVIM label", instance ~= nil)

-- appearance.lua renders tab 1 as the CORE chip in the instance color,
-- numbered with the instance rather than the tab index.
local tabline = _G.my_tabline()
check("tab 1 renders the CORE chip in the instance color",
    tabline:find("%#TabCoreSel#", 1, true) ~= nil
    and tabline:find("CORE", 1, true) ~= nil)
check("CORE chip carries the instance number",
    instance ~= nil and tabline:find(" " .. instance .. " CORE", 1, true) ~= nil)

-- The brackets track focus: off when another window takes over, back on
-- when this instance regains it.
vim.api.nvim_exec_autocmds("FocusLost", {})
check("FocusLost drops the brackets", vim.o.titlestring == "NVIM " .. (instance or ""))
vim.api.nvim_exec_autocmds("FocusGained", {})
check("FocusGained restores the brackets",
    vim.o.titlestring == "[ NVIM " .. (instance or "") .. " ]")

finish()
