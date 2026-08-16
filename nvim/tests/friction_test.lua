-- Headless behavior test for :Ugh (lua/friction.lua).
--
-- Run (the file argument avoids the full CORE workspace on VimEnter):
--   env -u NVIM nvim --headless ~/.config/nvim/init.lua \
--     -c "luafile ~/.config/nvim/tests/friction_test.lua"
-- env -u NVIM matters: inside an embedded nvim terminal the interceptor
-- would route this invocation into the host editor instead.
--
-- Prints one PASS/FAIL line per check; exits non-zero if any check fails.
-- The friction log is redirected to a temp file via PROTOCOL_FRICTION_LOG,
-- which both the zshrc export and the protocol shell module respect, so runs
-- never write into the real log.

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

local log_path = vim.fn.tempname() .. "-friction-log.md"
vim.env.PROTOCOL_FRICTION_LOG = log_path

check(":Ugh command exists", vim.fn.exists(":Ugh") == 2)

local friction = require("friction")
local done = false

friction.log("headless test entry", function(code, text)
    if done then return end
    done = true
    check("ugh exits zero", code == 0)
    check("reports the new entry count", text:find("logged", 1, true) ~= nil)
    local f = io.open(log_path)
    local content = f and f:read("*a") or ""
    if f then f:close() end
    check("entry lands in the redirected log",
        content:find("headless test entry", 1, true) ~= nil)
    finish()
end)

-- The shell round trip normally takes well under a second; a hang means the
-- interactive zsh failed to expose ugh, commonly through source resolution.
vim.defer_fn(function()
    if not done then
        done = true
        check("ugh completed within 8s", false)
        finish()
    end
end, 8000)
