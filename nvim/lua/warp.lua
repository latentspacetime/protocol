-- Warp: quick LLM query popup (<Leader>k).
--
-- Opens a small floating window. Type a question, hit <CR> to submit.
-- The response streams in below a divider with a tinted background and
-- treesitter-rendered markdown. Continue the conversation by typing
-- another message and pressing <CR> again. Press s to cycle models,
-- m for menu, b to copy a code block.
local menus = require("menus")

local M = {}

-- ── Models ────────────────────────────────────────────────────────────
M.models = {
    {
        id = "openai/gpt-oss-safeguard-20b",
        name = "OSS",
        provider = { only = { "Groq" } },
    },
    {
        id = "openai/gpt-5.6-luna",
        name = "Luna",
        reasoning = { effort = "medium" },
    },
}
M.active_model = 1
M.system_prompt = "Provide straightforward responses and commands quickly. Do not mention Ghostty or Neovim unless the user asks."
-- ───────────────────────────────────────────────────────────────────────

local augroup = vim.api.nvim_create_augroup("Warp", { clear = true })
local ns = vim.api.nvim_create_namespace("warp")
local float_win = nil
local warp_buf = nil
local active_job = nil
local current_phase = "input"
local messages = {}
local input_start_line = 0
local session_cost = 0
local code_block_label_ids = {}

-- ── Diagnostics ───────────────────────────────────────────────────────
local LOG_PATH = vim.fn.stdpath("data") .. "/warp.log"
local log_lines = {}

local function log(msg)
    table.insert(log_lines, msg)
end

local function flush_log()
    if #log_lines == 0 then return end
    local file = io.open(LOG_PATH, "a")
    if not file then return end
    file:write(table.concat(log_lines, "\n"), "\n")
    file:close()
    log_lines = {}
end

vim.api.nvim_create_user_command("WarpLog", function()
    flush_log()
    if vim.fn.filereadable(LOG_PATH) == 0 then
        print("No Warp log yet.")
        return
    end
    vim.cmd("tabedit " .. vim.fn.fnameescape(LOG_PATH))
    vim.cmd("normal! G")
end, { desc = "Open the Warp diagnostics log" })

local function current_model()
    return M.models[M.active_model]
end

local function buf_valid()
    return warp_buf and vim.api.nvim_buf_is_valid(warp_buf)
end

local function win_valid()
    return float_win and vim.api.nvim_win_is_valid(float_win)
end

local function set_buf_modifiable(modifiable)
    if buf_valid() then vim.bo[warp_buf].modifiable = modifiable end
end

local function cancel_job()
    if active_job then
        pcall(vim.fn.jobstop, active_job)
        active_job = nil
    end
end

local function cost_label()
    if session_cost <= 0 then return "" end
    if session_cost < 0.01 then
        return string.format(" $%.6f ", session_cost)
    end
    return string.format(" $%.4f ", session_cost)
end

function M.close()
    cancel_job()
    if not win_valid() then
        float_win = nil
        return
    end
    vim.cmd("nohlsearch")
    pcall(vim.api.nvim_win_close, float_win, true)
    float_win = nil
    if buf_valid() then
        pcall(vim.api.nvim_buf_delete, warp_buf, { force = true })
    end
    warp_buf = nil
    current_phase = "input"
    messages = {}
    input_start_line = 0
    session_cost = 0
    code_block_label_ids = {}
end

local function mode_chip(mode)
    if mode and mode:find("^i") then
        return { " INSERT ", "WarpInsert" }
    end
    return { " NORMAL ", "WarpNormal" }
end

local function float_title(phase, mode)
    local model_name = current_model().name
    local cost = cost_label()
    local cost_chip = cost ~= "" and { cost, "WarpCost" } or nil

    local title = { { " WARP ", "WarpTitle" } }
    if phase == "waiting" then
        table.insert(title, { " thinking… ", "WarpWaiting" })
        table.insert(title, { " esc: cancel ", "FloatTitle" })
    else
        table.insert(title, mode_chip(mode))
        table.insert(title, { " " .. model_name .. " ", "WarpModel" })
        if cost_chip then table.insert(title, cost_chip) end
        if phase == "input" then
            table.insert(title, { " enter: send · esc: close ", "FloatTitle" })
        else
            table.insert(title, { " m: menu · esc: close ", "FloatTitle" })
        end
    end
    return title
end

local function update_title(phase)
    current_phase = phase
    if not win_valid() then return end
    vim.api.nvim_win_set_config(float_win, {
        title = float_title(phase, vim.fn.mode()),
        title_pos = "center",
    })
end

vim.api.nvim_create_autocmd("ModeChanged", {
    group = augroup,
    callback = function()
        if not win_valid() then return end
        if vim.api.nvim_get_current_win() ~= float_win then return end
        if current_phase == "waiting" then return end
        vim.api.nvim_win_set_config(float_win, {
            title = float_title(current_phase, vim.v.event.new_mode),
            title_pos = "center",
        })
    end,
})

local function get_current_input()
    if not buf_valid() then return "" end
    local lines = vim.api.nvim_buf_get_lines(warp_buf, input_start_line, -1, false)
    return table.concat(lines, "\n")
end

local function get_last_response()
    for i = #messages, 1, -1 do
        if messages[i].role == "assistant" then
            return messages[i].content
        end
    end
    return ""
end

-- ── Visual: response background tint ──────────────────────────────────
local function tint_response_lines(start_0, end_0)
    if not buf_valid() then return end
    for i = start_0, end_0 do
        vim.api.nvim_buf_set_extmark(warp_buf, ns, i, 0, {
            hl_group = "WarpResponse",
            hl_eol = true,
        })
    end
end

-- ── Visual: dim submitted query ───────────────────────────────────────
local function dim_query_lines(start_0, end_0)
    if not buf_valid() then return end
    for i = start_0, end_0 do
        vim.api.nvim_buf_set_extmark(warp_buf, ns, i, 0, {
            hl_group = "WarpDimmed",
            end_row = i + 1,
            end_col = 0,
            priority = 200,
        })
    end
end


-- ── Visual: code block labels ─────────────────────────────────────────
local function find_code_blocks()
    if not buf_valid() then return {} end
    local lines = vim.api.nvim_buf_get_lines(warp_buf, 0, -1, false)
    local blocks = {}
    local in_block = false
    local block_start, block_lang
    for i, line in ipairs(lines) do
        if not in_block and line:match("^```") then
            in_block = true
            block_start = i
            block_lang = line:match("^```(%S+)") or ""
        elseif in_block and line:match("^```%s*$") then
            in_block = false
            local content_lines = vim.api.nvim_buf_get_lines(
                warp_buf, block_start, i - 1, false)
            table.insert(blocks, {
                start_line = block_start,
                end_line = i,
                lang = block_lang,
                content = table.concat(content_lines, "\n"),
            })
        end
    end
    return blocks
end

local function label_code_blocks()
    if not buf_valid() then return end
    for _, id in ipairs(code_block_label_ids) do
        pcall(vim.api.nvim_buf_del_extmark, warp_buf, ns, id)
    end
    code_block_label_ids = {}
    local blocks = find_code_blocks()
    for idx, block in ipairs(blocks) do
        local id = vim.api.nvim_buf_set_extmark(warp_buf, ns, block.start_line - 1, 0, {
            virt_text = { { " [" .. idx .. "] ", "WarpBlockLabel" } },
            virt_text_pos = "eol",
        })
        table.insert(code_block_label_ids, id)
    end
end

local function copy_code_block()
    local blocks = find_code_blocks()
    if #blocks == 0 then
        menus.flash("No code blocks.", 1500)
        return
    end
    if not win_valid() then return end
    local cursor_line = vim.api.nvim_win_get_cursor(float_win)[1]
    local best = blocks[#blocks]
    for _, block in ipairs(blocks) do
        if cursor_line >= block.start_line and cursor_line <= block.end_line then
            best = block
            break
        end
    end
    vim.fn.setreg("+", best.content)
    vim.fn.setreg("*", best.content)
    local label = best.lang ~= "" and best.lang or "Code"
    menus.flash(label .. " block copied.", 1500)
end

-- ── Buffer operations ─────────────────────────────────────────────────
local function append_text(text, is_response)
    if not buf_valid() then return end
    set_buf_modifiable(true)
    local line_count = vim.api.nvim_buf_line_count(warp_buf)
    local last_line = vim.api.nvim_buf_get_lines(warp_buf, line_count - 1, line_count, false)[1] or ""
    local new_lines = vim.split(text, "\n", { plain = true })
    new_lines[1] = last_line .. new_lines[1]
    vim.api.nvim_buf_set_lines(warp_buf, line_count - 1, line_count, false, new_lines)
    if is_response then
        tint_response_lines(line_count - 1, line_count - 1 + #new_lines - 1)
    end
    set_buf_modifiable(false)
    if win_valid() then
        local new_count = vim.api.nvim_buf_line_count(warp_buf)
        pcall(vim.api.nvim_win_set_cursor, float_win, { new_count, 0 })
    end
end

local function show_error(msg)
    if not buf_valid() then return end
    set_buf_modifiable(true)
    local line_count = vim.api.nvim_buf_line_count(warp_buf)
    vim.api.nvim_buf_set_lines(warp_buf, line_count, line_count, false, { "", "Error: " .. msg })
    set_buf_modifiable(false)
    update_title("done")
end

local function resize_float()
    if not win_valid() or not buf_valid() then return end
    local width = math.floor(vim.o.columns * 0.27)
    local max_height = math.floor(vim.o.lines * 0.9)
    local visual_lines = 0
    local lines = vim.api.nvim_buf_get_lines(warp_buf, 0, -1, false)
    for _, line in ipairs(lines) do
        local display_width = vim.fn.strdisplaywidth(line)
        visual_lines = visual_lines + math.max(1, math.ceil(display_width / width))
    end
    local new_height = math.min(math.max(visual_lines + 2, 4), max_height)
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - new_height) / 2)
    vim.api.nvim_win_set_config(float_win, {
        relative = "editor",
        width = width,
        height = new_height,
        col = col,
        row = row,
    })
end

local function clamp_cursor_to_input()
    if not win_valid() or not buf_valid() then return end
    if vim.api.nvim_get_current_win() ~= float_win then return end
    if input_start_line == 0 then return end
    local cursor = vim.api.nvim_win_get_cursor(float_win)
    if cursor[1] <= input_start_line then
        pcall(vim.api.nvim_win_set_cursor, float_win, { input_start_line + 1, 0 })
    end
end

local function open_input_area()
    if not buf_valid() then return end
    set_buf_modifiable(true)
    local line_count = vim.api.nvim_buf_line_count(warp_buf)
    vim.api.nvim_buf_set_lines(warp_buf, line_count, line_count, false, { "───", "" })

    input_start_line = line_count + 1
    if win_valid() then
        local new_count = vim.api.nvim_buf_line_count(warp_buf)
        pcall(vim.api.nvim_win_set_cursor, float_win, { new_count, 0 })
    end
    label_code_blocks()
    resize_float()
    update_title("input")
    vim.cmd("startinsert!")
end

function M.submit()
    if active_job then return end
    if not buf_valid() then return end

    local api_key = vim.env.OPENROUTER_API_KEY
    if not api_key or api_key == "" then
        show_error("OPENROUTER_API_KEY not set.")
        return
    end

    local input = get_current_input()
    if vim.trim(input) == "" then
        menus.flash("Nothing to send.", 1500)
        return
    end

    table.insert(messages, { role = "user", content = input })

    local query_end = vim.api.nvim_buf_line_count(warp_buf) - 1
    dim_query_lines(input_start_line, query_end)

    set_buf_modifiable(true)
    local line_count = vim.api.nvim_buf_line_count(warp_buf)
    vim.api.nvim_buf_set_lines(warp_buf, line_count, line_count, false, { "───", "" })

    set_buf_modifiable(false)

    update_title("waiting")
    resize_float()

    local mdl = current_model()
    local api_messages = {}
    if M.system_prompt and M.system_prompt ~= "" then
        table.insert(api_messages, { role = "system", content = M.system_prompt })
    end
    for _, msg in ipairs(messages) do
        table.insert(api_messages, { role = msg.role, content = msg.content })
    end

    local request = {
        model = mdl.id,
        messages = api_messages,
        stream = true,
    }
    if mdl.reasoning then request.reasoning = mdl.reasoning end
    if mdl.provider then request.provider = mdl.provider end

    local body = vim.json.encode(request)

    log("════════════════════════════════════════")
    log("REQUEST  " .. os.date("%Y-%m-%d %H:%M:%S"))
    log("model:   " .. mdl.id .. " (" .. mdl.name .. ")")
    log("input:   " .. input:sub(1, 200))
    log("msgs:    " .. #messages .. " in history")
    log("────────────────────────────────────────")

    local response_chunks = {}
    local partial_line = ""
    local chunk_count = 0
    local stderr_parts = {}

    local function process_line(line)
        if line:match("^data: %[DONE%]") then
            log("SSE      [DONE]")
            return
        end
        if not line:match("^data: ") then
            if line ~= "" then log("SSE-skip " .. line:sub(1, 80)) end
            return
        end
        chunk_count = chunk_count + 1
        local json_str = line:sub(7):gsub("%s+$", "")
        local ok, parsed = pcall(vim.json.decode, json_str)
        if not ok or not parsed then
            log("SSE-ERR  parse failed: " .. json_str:sub(1, 120))
            return
        end

        if parsed.usage and parsed.usage.cost then
            local cost = tonumber(parsed.usage.cost) or 0
            log("SSE-cost " .. tostring(cost))
            if cost > 0 then
                session_cost = session_cost + cost
                vim.schedule(function() update_title("done") end)
            end
        end

        if parsed.choices and parsed.choices[1] then
            local delta = parsed.choices[1].delta
            if not delta then
                log("SSE-" .. chunk_count .. "  no delta")
                return
            end
            local ct = type(delta.content) == "string" and delta.content or ""
            local rt = type(delta.reasoning) == "string" and delta.reasoning or ""
            local fr = parsed.choices[1].finish_reason
            if ct ~= "" or rt ~= "" or fr then
                log(string.format("SSE-%-4d content=%-20s reasoning=%-20s finish=%s",
                    chunk_count, vim.inspect(ct):sub(1, 20), vim.inspect(rt):sub(1, 20), tostring(fr)))
            end
            if type(delta.content) == "string" and delta.content ~= "" then
                table.insert(response_chunks, delta.content)
                vim.schedule(function()
                    append_text(delta.content, true)
                    resize_float()
                end)
            end
        end
    end

    local function on_stdout(_, data, _)
        if not data then return end
        data[1] = partial_line .. data[1]
        partial_line = data[#data]
        for i = 1, #data - 1 do
            process_line(data[i])
        end
    end

    local function on_stderr(_, data, _)
        if data then
            for _, line in ipairs(data) do
                if line ~= "" then table.insert(stderr_parts, line) end
            end
        end
    end

    local function on_exit(_, exit_code, _)
        vim.schedule(function()
            active_job = nil
            local raw_partial = partial_line
            if partial_line ~= "" then
                log("FLUSH    partial_line: " .. partial_line:sub(1, 200))
                process_line(partial_line)
                partial_line = ""
            end
            if #stderr_parts > 0 then
                log("STDERR   " .. table.concat(stderr_parts, " "):sub(1, 200))
            end
            local full_response = table.concat(response_chunks, "")
            log("────────────────────────────────────────")
            log(string.format("EXIT     code=%d chunks=%d content_len=%d",
                exit_code, chunk_count, #full_response))
            if vim.trim(full_response) ~= "" then
                log("RESULT   ok — " .. full_response:sub(1, 120))
                table.insert(messages, { role = "assistant", content = full_response })
            elseif exit_code ~= 0 then
                log("RESULT   curl failed")
                show_error("Request failed (exit code " .. exit_code .. ")")
            else
                log("RESULT   empty response — no content chunks received")
                local err_detail = nil
                if #stderr_parts > 0 then
                    err_detail = table.concat(stderr_parts, " ")
                end
                local ok, parsed = pcall(vim.json.decode, raw_partial)
                if ok and parsed and parsed.error then
                    local msg = parsed.error.message or parsed.error.code or "unknown"
                    err_detail = tostring(msg)
                end
                if err_detail then
                    show_error(err_detail:sub(1, 120))
                else
                    show_error("Empty response — try again or switch models (s).")
                end
            end
            flush_log()
            open_input_area()
        end)
    end

    active_job = vim.fn.jobstart({
        "curl", "-sN",
        "https://openrouter.ai/api/v1/chat/completions",
        "-H", "Authorization: Bearer " .. api_key,
        "-H", "Content-Type: application/json",
        "-d", body,
    }, {
        stdout_buffered = false,
        on_stdout = on_stdout,
        on_stderr = on_stderr,
        on_exit = on_exit,
    })

    if active_job <= 0 then
        active_job = nil
        show_error("Failed to start curl")
    end
end

local function cycle_model()
    M.active_model = (M.active_model % #M.models) + 1
    update_title(current_phase)
    menus.flash("Model: " .. current_model().name, 1500)
end

local function warp_menu()
    vim.schedule(function()
        print("WARP: (s)witch model (b)lock copy (c)opy response (a)ll (q)uestion-only")
        local char = menus.read_menu_char():lower()
        if char == "s" then
            cycle_model()
        elseif char == "b" then
            copy_code_block()
        elseif char == "c" then
            local resp = get_last_response()
            if vim.trim(resp) == "" then
                menus.flash("No response to copy.", 1500)
            else
                vim.fn.setreg("+", resp)
                vim.fn.setreg("*", resp)
                menus.flash("Response copied.", 2000)
            end
        elseif char == "a" then
            if buf_valid() then
                local all = table.concat(
                    vim.api.nvim_buf_get_lines(warp_buf, 0, -1, false), "\n")
                vim.fn.setreg("+", all)
                vim.fn.setreg("*", all)
                menus.flash("All copied.", 2000)
            end
        elseif char == "q" then
            local q = get_current_input()
            if vim.trim(q) == "" then
                menus.flash("No question to copy.", 1500)
            else
                vim.fn.setreg("+", q)
                vim.fn.setreg("*", q)
                menus.flash("Question copied.", 2000)
            end
        else
            menus.flash("Cancelled.", 1000)
        end
    end)
end

function M.open()
    if win_valid() then
        M.close()
        return
    end

    warp_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[warp_buf].filetype = "markdown"
    vim.bo[warp_buf].bufhidden = "wipe"
    current_phase = "input"
    messages = {}
    input_start_line = 0
    session_cost = 0
    code_block_label_ids = {}

    pcall(vim.treesitter.start, warp_buf, "markdown")

    local width = math.floor(vim.o.columns * 0.27)
    local height = 4
    float_win = vim.api.nvim_open_win(warp_buf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        border = "rounded",
        title = float_title("input", "i"),
        title_pos = "center",
    })
    vim.wo[float_win].linebreak = true
    vim.wo[float_win].wrap = true
    vim.wo[float_win].conceallevel = 2

    local opts = { buffer = warp_buf, silent = true, nowait = true }
    vim.keymap.set("n", "<CR>", M.submit, opts)
    vim.keymap.set("i", "<CR>", function()
        vim.cmd("stopinsert")
        M.submit()
    end, opts)
    vim.keymap.set("n", "<Esc>", M.close, opts)
    vim.keymap.set("n", "m", warp_menu, opts)
    vim.keymap.set("n", "s", cycle_model, opts)
    vim.keymap.set("n", "b", copy_code_block, opts)

    vim.api.nvim_create_autocmd({ "InsertEnter", "CursorMovedI" }, {
        group = augroup,
        buffer = warp_buf,
        callback = clamp_cursor_to_input,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = augroup,
        buffer = warp_buf,
        once = true,
        callback = function()
            cancel_job()
            float_win = nil
            warp_buf = nil
            messages = {}
            input_start_line = 0
            session_cost = 0
            code_block_label_ids = {}
        end,
    })

    vim.cmd("startinsert")
end

return M
