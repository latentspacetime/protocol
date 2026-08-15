-- Headless behavior test for input recovery (lua/recover.lua) and the jk
-- escape-hatch maps (lua/keymaps.lua).
--
-- Run (XDG_STATE_HOME redirection is mandatory — :Diag appends to the state
-- dir, and a test run must never write into the real diagnostics log):
--   env -u NVIM XDG_STATE_HOME=$(mktemp -d) nvim --headless ~/.config/nvim/init.lua \
--     -c "luafile ~/.config/nvim/tests/recover_test.lua"
-- env -u NVIM matters: inside an embedded nvim terminal the interceptor
-- would route this invocation into the host editor instead.
--
-- Prints one PASS/FAIL line per check; exits non-zero if any check fails.

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

vim.defer_fn(function()
    -- Caps lock inverts letter case, so the escape hatch must exist in every
    -- capitalization in both modes (regression: i-mode had only lowercase jk).
    for _, jk_variant in ipairs({ "jk", "JK", "Jk", "jK" }) do
        check("terminal-mode escape " .. jk_variant,
            vim.fn.maparg(jk_variant, "t") ~= "")
        check("insert-mode escape " .. jk_variant,
            vim.fn.maparg(jk_variant, "i") ~= "")
    end

    check(":Fix command exists", vim.fn.exists(":Fix") == 2)
    check(":Diag command exists", vim.fn.exists(":Diag") == 2)

    local log_path = vim.fn.stdpath("state") .. "/input-diagnostics.log"
    if log_path:find(vim.env.HOME .. "/.local/state", 1, true) == 1 then
        check("refusing to run :Diag against the real state dir "
            .. "(set XDG_STATE_HOME to a temp dir)", false)
        return finish()
    end

    vim.cmd("Diag")
    local log = table.concat(vim.fn.readfile(log_path), "\n")
    check(":Diag opens the log it wrote",
        vim.fn.expand("%:p") == vim.fn.fnamemodify(log_path, ":p"))
    check("snapshot records mode line", log:find("mode=", 1, true) ~= nil)
    check("snapshot records a definite capslock state",
        log:match("capslock=(%a+)") == "on" or log:match("capslock=(%a+)") == "off")
    finish()
end, 700)
