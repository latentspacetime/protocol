-- Instance slot allocation for the Ghostty identity label (appearance.lua).
-- Instances claim the lowest free slot in a shared directory. A slot file
-- holds its owner's PID; the slot is free when the file is missing or that
-- process is dead, so a crashed instance can't strand a number.
-- Requires Neovim 0.10+ (vim.uv).

local M = {}

local MAX_SLOTS = 64

-- Claims the lowest free slot in dir and records pid as its owner.
-- Returns the slot number, or nil when no slot could be claimed (unwritable
-- dir, or every slot live). pid defaults to this process; it is a parameter
-- so tests can simulate other instances.
function M.claim(dir, pid)
    pid = pid or vim.fn.getpid()
    vim.fn.mkdir(dir, "p")
    for slot = 0, MAX_SLOTS - 1 do
        local path = dir .. "/" .. slot
        local file = io.open(path, "r")
        local owner = file and tonumber(file:read("*a")) or nil
        if file then file:close() end
        -- owner == pid means a stale file from a recycled PID, not a live
        -- claim; treat it as free.
        local taken = owner and owner ~= pid and vim.uv.kill(owner, 0) == 0
        if not taken then
            if file then os.remove(path) end
            -- "wx" fails if the file already exists, so when two instances
            -- start simultaneously (e.g. a Ghostty session restore) the
            -- filesystem picks exactly one winner for each slot; the loser
            -- falls through to the next slot.
            local fd = vim.uv.fs_open(path, "wx", 384) -- 0600
            if fd then
                vim.uv.fs_write(fd, tostring(pid))
                vim.uv.fs_close(fd)
                return slot
            end
        end
    end
    return nil
end

-- Frees a previously claimed slot. Safe to call for a slot whose file is
-- already gone.
function M.release(dir, slot)
    os.remove(dir .. "/" .. slot)
end

return M
