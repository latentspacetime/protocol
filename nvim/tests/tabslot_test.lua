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
local my_pid = vim.fn.getpid()

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

-- Empty dir: lowest slot wins and the owner pid is recorded.
local dir = fresh_dir()
check("empty dir claims slot 0", tabslot.claim(dir) == 0)
check("slot file records owner pid", slurp(dir .. "/0") == tostring(my_pid))

-- A slot owned by a live process (the parent shell) is skipped.
dir = fresh_dir()
plant(dir, 0, tostring(vim.uv.os_getppid()))
check("live-owned slot is skipped", tabslot.claim(dir) == 1)

-- A slot owned by a dead process is reclaimed.
dir = fresh_dir()
local done = vim.system({ "true" })
done:wait()
plant(dir, 0, tostring(done.pid))
check("dead-owned slot is reclaimed", tabslot.claim(dir) == 0)
check("reclaimed slot records new owner", slurp(dir .. "/0") == tostring(my_pid))

-- A slot file holding our own pid is a recycled-PID leftover, so it's free.
dir = fresh_dir()
plant(dir, 0, tostring(my_pid))
check("own-pid slot is treated as stale", tabslot.claim(dir) == 0)

-- Garbage content has no live owner.
dir = fresh_dir()
plant(dir, 0, "not-a-pid")
check("garbage slot file is reclaimed", tabslot.claim(dir) == 0)

-- Release removes the file and tolerates a missing one.
dir = fresh_dir()
local slot = tabslot.claim(dir)
tabslot.release(dir, slot)
check("release removes the slot file", slurp(dir .. "/" .. slot) == nil)
check("release of a freed slot is a no-op", (pcall(tabslot.release, dir, slot)))

-- appearance.lua wired the claimed slot into the terminal title.
check("titlestring shows NVIM label", vim.o.titlestring:match("^NVIM %d+$") ~= nil)

-- appearance.lua renders tab 1 as the CORE chip in the instance color.
local tabline = _G.my_tabline()
check("tab 1 renders the CORE chip in the instance color",
    tabline:find("%#TabCoreSel#", 1, true) ~= nil
    and tabline:find("CORE", 1, true) ~= nil)

finish()
