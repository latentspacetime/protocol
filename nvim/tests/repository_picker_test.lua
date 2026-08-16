-- Headless behavior test for the CORE terminal repository picker.
-- Run with ./tests/nvim_test.zsh from the repository root.

local results = {}
local function check(name, condition)
    table.insert(results, (condition and "PASS  " or "FAIL  ") .. name)
end
local function finish()
    io.stdout:write(table.concat(results, "\n") .. "\n")
    for _, line in ipairs(results) do
        if line:find("^FAIL") then vim.cmd("cq") end
    end
    vim.cmd("qa!")
end

local search = require("search")
local workspace = require("workspace")
local root = vim.fn.tempname() .. "-repository-picker"
local color_config = vim.fn.tempname() .. "-repo-colors.conf"
vim.fn.writefile({ "special-repo=68" }, color_config)
vim.env.PROTOCOL_REPO_COLOR_CONFIG = color_config
vim.fn.mkdir(root .. "/alpha/nested", "p")
vim.fn.mkdir(root .. "/.hidden", "p")
vim.fn.mkdir(root .. "/Space Repo", "p")
vim.fn.mkdir(root .. "/special-repo", "p")
vim.fn.mkdir(root .. "/tab\tname", "p")
vim.fn.mkdir(root .. "/escape\27[31mname", "p")
vim.fn.mkdir(root .. "/quote's repo", "p")
vim.fn.writefile({ "ordinary file" }, root .. "/notes.txt")
vim.uv.fs_symlink(root .. "/alpha", root .. "/linked repo")
vim.uv.fs_symlink(root .. "/missing", root .. "/broken link")
workspace.code_root = root

local directories = search.list_workspace_directories(root)
check("lists sorted immediate child directories and valid directory symlinks",
    vim.deep_equal(directories,
        { ".hidden", "alpha", "linked repo", "quote's repo", "Space Repo", "special-repo" }))
check("omits files, grandchildren, and broken symlinks",
    not vim.tbl_contains(directories, "notes.txt")
    and not vim.tbl_contains(directories, "nested")
    and not vim.tbl_contains(directories, "broken link"))
check("omits names that cannot round-trip through the ANSI picker",
    not vim.tbl_contains(directories, "tab\tname")
    and not vim.tbl_contains(directories, "escape\27[31mname"))
check("invalid roots produce an empty list",
    vim.deep_equal(search.list_workspace_directories(root .. "/missing"), {}))

local colored_directories, color_error = search.color_workspace_directories(directories)
check("shared resolver colors every workspace directory",
    not color_error and #colored_directories == #directories)
check("picker uses the exact machine-local repository color override",
    vim.tbl_contains(colored_directories, "\27[38;5;68mspecial-repo\27[0m"))
vim.fn.writefile({ "special-repo=invalid" }, color_config)
local invalid_entries, invalid_color_error = search.color_workspace_directories(directories)
check("malformed shared color configuration fails clearly",
    not invalid_entries and invalid_color_error:find("invalid repository color", 1, true) ~= nil)
vim.fn.writefile({ "special-repo=68" }, color_config)

check("Vimscript fzf bridge accepts Tab for an available directory",
    vim.fn.RepositoryPickerHandler(
        0, 0, 0, { "tab", "\27[38;5;110mSpace Repo\27[0m" }
    ) == 0)
check("Tab copies the absolute path to both clipboard registers",
    vim.fn.getreg("+") == root .. "/Space Repo" and vim.fn.getreg("*") == root .. "/Space Repo")
check("malformed picker output does nothing",
    not search.handle_repository_selection({}, {})
    and not search.handle_repository_selection({}, { "ctrl-x", "alpha" }))

local function open_terminal(cwd)
    vim.cmd("new")
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()
    local channel = vim.fn.termopen({ "/bin/sh" }, { cwd = cwd })
    return { winid = winid, bufnr = bufnr, channel = channel }
end

local terminal_one = open_terminal(root)
local terminal_two = open_terminal(root .. "/.hidden")
vim.wait(1000, function()
    return vim.fn.jobwait({ terminal_one.channel, terminal_two.channel }, 0)[1] == -1
end, 10)

search.attach_repository_picker(terminal_one.bufnr)
vim.api.nvim_set_current_win(terminal_one.winid)
check("repository picker has buffer-local normal-mode case-proof maps",
    vim.fn.maparg("<Space>r", "n", false, true).buffer == 1
    and vim.fn.maparg("<Space>R", "n", false, true).buffer == 1)
-- Regression guard: a terminal-job-mode mapping starting with the space
-- leader makes every space typed into a terminal wait out 'timeoutlen'.
local function space_prefixed_terminal_maps(bufnr)
    local offenders = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "t")) do
        if map.lhs:sub(1, 1) == " " then table.insert(offenders, map.lhs) end
    end
    return offenders
end
check("no terminal-job-mode mapping starts with the space leader",
    #space_prefixed_terminal_maps(terminal_one.bufnr) == 0)

local original_open_picker = search.open_repository_picker
local mapped_target
search.open_repository_picker = function(target) mapped_target = target end
vim.cmd("new")
local moved_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(moved_win, terminal_one.bufnr)
vim.api.nvim_feedkeys(vim.keycode("<Space>r"), "x", false)
check("mapping captures the terminal window where it is invoked",
    mapped_target
    and mapped_target.winid == moved_win
    and mapped_target.bufnr == terminal_one.bufnr
    and mapped_target.channel == terminal_one.channel)
search.open_repository_picker = original_open_picker
vim.api.nvim_win_close(moved_win, true)
vim.api.nvim_set_current_win(terminal_one.winid)

local function terminal_pwd(terminal, output)
    vim.api.nvim_chan_send(terminal.channel, "pwd > " .. vim.fn.shellescape(output) .. "\n")
    return vim.wait(2000, function() return vim.fn.filereadable(output) == 1 end, 10)
        and vim.trim(table.concat(vim.fn.readfile(output), "\n"))
end

local function same_directory(actual, expected)
    return actual and vim.uv.fs_realpath(actual) == vim.uv.fs_realpath(expected)
end

check("Enter changes the invoking terminal",
    search.handle_repository_selection(terminal_one, { "", "Space Repo" }))
check("invoking shell changed to the selected directory",
    same_directory(terminal_pwd(terminal_one, root .. "/terminal-one-pwd"), root .. "/Space Repo"))
check("another CORE shell keeps its directory",
    same_directory(terminal_pwd(terminal_two, root .. "/terminal-two-pwd"), root .. "/.hidden"))

vim.api.nvim_set_current_win(terminal_two.winid)
vim.fn.RepositoryPickerExit(
    terminal_one.winid, terminal_one.bufnr, terminal_one.channel, 130
)
check("fzf cancellation restores the invoking terminal window",
    vim.wait(1000, function() return vim.api.nvim_get_current_win() == terminal_one.winid end, 10))

check("single quotes are shell-escaped safely",
    search.handle_repository_selection(terminal_one, { "", "quote's repo" }))
check("shell reaches a directory containing a single quote",
    same_directory(terminal_pwd(terminal_one, root .. "/quoted-pwd"), root .. "/quote's repo"))

vim.api.nvim_win_set_buf(terminal_one.winid, vim.api.nvim_create_buf(false, true))
check("a window that replaced its terminal is rejected",
    not search.handle_repository_selection(terminal_one, { "", "alpha" }))
vim.api.nvim_win_set_buf(terminal_one.winid, terminal_one.bufnr)
vim.fn.jobstop(terminal_one.channel)
vim.wait(1000, function() return vim.fn.jobwait({ terminal_one.channel }, 0)[1] ~= -1 end, 10)
check("a stopped invoking terminal is rejected",
    not search.handle_repository_selection(terminal_one, { "", "alpha" }))

vim.fn.delete(root .. "/alpha", "rf")
check("a directory removed after opening is rejected",
    not search.handle_repository_selection(terminal_two, { "", "alpha" }))

vim.fn.jobstop(terminal_two.channel)
vim.fn.delete(root, "rf")
vim.fn.delete(color_config)
finish()
