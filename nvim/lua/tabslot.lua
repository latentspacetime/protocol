-- Instance slot allocation for the Ghostty identity label (appearance.lua).
-- Each slot records its owner's unique Neovim server address. Allocation and
-- release share an advisory lock, which the OS releases if a process crashes.
-- Requires macOS and a LuaJIT build of Neovim 0.10+.

local M = {}

local MAX_SLOTS = 64
local LOCK_TIMEOUT_NS = 1000000000
local LOCK_EX_NB = 6 -- LOCK_EX | LOCK_NB on macOS
local LOCK_UN = 8

local has_ffi, ffi = pcall(require, "ffi")
if has_ffi then
    ffi.cdef([[int flock(int fd, int operation);]])
end

local function read_record(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local record = file:read("*a")
    file:close()
    return record
end

local function with_lock(dir, callback)
    if not has_ffi then return nil end

    vim.fn.mkdir(dir, "p")
    local fd = vim.uv.fs_open(dir .. "/.allocation.lock", "a", 384) -- 0600
    if not fd then return nil end

    local deadline = vim.uv.hrtime() + LOCK_TIMEOUT_NS
    while ffi.C.flock(fd, LOCK_EX_NB) ~= 0 do
        if vim.uv.hrtime() >= deadline then
            vim.uv.fs_close(fd)
            return nil
        end
        vim.uv.sleep(10)
    end

    local ok, first, second = pcall(callback)
    ffi.C.flock(fd, LOCK_UN)
    vim.uv.fs_close(fd)
    if not ok then error(first) end
    return first, second
end

local function server_identity()
    if vim.v.servername ~= "" then return vim.v.servername end
    local ok, address = pcall(vim.fn.serverstart)
    if ok and address ~= "" then return address end
    return nil
end

local function server_is_live(address)
    if not address or address == "" or address:find("\n", 1, true) then
        return false
    end
    local ok, channel = pcall(vim.fn.sockconnect, "pipe", address, { rpc = false })
    if not ok or channel <= 0 then return false end
    vim.fn.chanclose(channel)
    return true
end

-- Claims the lowest free slot. The second return value is the ownership token
-- required by release. Returns nil when the lock or a server cannot be made.
function M.claim(dir)
    local identity = server_identity()
    if not identity then return nil end

    return with_lock(dir, function()
        for slot = 0, MAX_SLOTS - 1 do
            local path = dir .. "/" .. slot
            local owner = read_record(path)
            local taken = owner ~= identity and server_is_live(owner)
            if not taken then
                if owner then os.remove(path) end
                local fd = vim.uv.fs_open(path, "wx", 384) -- 0600
                if fd then
                    local written = vim.uv.fs_write(fd, identity)
                    vim.uv.fs_close(fd)
                    if written == #identity then return slot, identity end
                    os.remove(path)
                end
            end
        end
        return nil
    end)
end

-- Frees a slot while it still has the same owner. The shared lock makes the
-- read-and-remove operation atomic with respect to claims and other releases.
function M.release(dir, slot, identity)
    return with_lock(dir, function()
        local path = dir .. "/" .. slot
        if identity and read_record(path) == identity then os.remove(path) end
        return true
    end)
end

return M
