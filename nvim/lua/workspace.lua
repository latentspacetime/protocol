local code_root = os.getenv("CODE_WORKSPACE") or (vim.env.HOME .. "/Code")

if vim.fn.isdirectory(code_root) == 0 then
    vim.notify("CODE_WORKSPACE is not a directory: " .. code_root, vim.log.levels.WARN)
end

return { code_root = code_root }
