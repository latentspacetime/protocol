-- Single source of truth for the machine-specific workspace paths.
-- Everything that scopes to "my code" — fzf file search, :Rg, the CORE
-- workspace layout, OTemp snapshots — reads code_root. Set CODE_WORKSPACE
-- in the shell (the same variable the shell module exports) instead of
-- editing this file per machine. vault_root is the Obsidian vault :oo
-- raises; set PROTOCOL_VAULT or keep the default under $HOME/Notes.
local code_root = os.getenv("CODE_WORKSPACE") or (vim.env.HOME .. "/Code")

if vim.fn.isdirectory(code_root) == 0 then
    vim.notify("CODE_WORKSPACE is not a directory: " .. code_root, vim.log.levels.WARN)
end

return {
    code_root = code_root,
    -- Where OTemp (<Leader>o) writes saved snapshots. Inside the code root on
    -- purpose: saved notes stay findable by :Rg and <Leader>p like any file.
    otemp_dir = code_root .. "/temptext",
    vault_root = os.getenv("PROTOCOL_VAULT") or (vim.env.HOME .. "/Notes"),
}
