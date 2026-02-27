local config = require("yaml-jumper.config")
local parser = require("yaml-jumper.parser")
local history = require("yaml-jumper.history")
local utils = require("yaml-jumper.utils")

local M = {}

-- Edit a YAML value in-place (works for current buffer or external file)
function M.edit_yaml_value(file_path, line_num, current_value)
    local bufnr
    if file_path and file_path ~= vim.fn.expand("%:p") then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_get_name(buf) == file_path then
                bufnr = buf
                break
            end
        end
        if not bufnr then
            bufnr = vim.fn.bufadd(file_path)
            vim.fn.bufload(bufnr)
        end
    else
        bufnr = vim.api.nvim_get_current_buf()
    end

    local line = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1]
    local before_value, value = line:match("^(.+:)%s*(.*)$")
    if not (before_value and value) then
        vim.notify("Could not parse YAML value on this line", vim.log.levels.ERROR)
        return false
    end

    local new_value = vim.fn.input({ prompt = "New value: ", default = value, cancelreturn = nil })
    if not new_value or new_value == value then
        return false
    end

    vim.api.nvim_buf_set_lines(bufnr, line_num - 1, line_num, false, { before_value .. " " .. new_value })
    vim.notify("Value updated", vim.log.levels.INFO)
    require("yaml-jumper.cache").clear(file_path or "current")
    return true
end

-- Telescope-only edit action (no-op for other pickers)
function M.add_edit_action(prompt_bufnr, map)
    if config.picker_type ~= "telescope" then
        return true
    end
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    map("i", "<C-e>", function()
        local sel = action_state.get_selected_entry()
        if sel then
            actions.close(prompt_bufnr)
            if sel.filename and sel.filename ~= vim.fn.expand("%:p") then
                pcall(vim.cmd, "edit " .. vim.fn.fnameescape(sel.filename))
            end
            pcall(vim.api.nvim_win_set_cursor, 0, { sel.lnum, 0 })
            M.edit_yaml_value(sel.filename, sel.lnum, sel.value_text or "")
        end
    end)
    return true
end

function M.jump_to_path()
    local lines = utils.read_file_lines()
    local paths = parser.get_yaml_paths(lines)
    local filename = vim.api.nvim_buf_get_name(0)

    local picker_opts = {
        prompt_title = "YAML Path",
        results = vim.tbl_map(function(entry)
            return {
                lnum = entry.line, text = entry.text, path = entry.path,
                file = filename, value_text = utils.extract_value_from_line(entry.text) or "",
            }
        end, paths),
        entry_maker = function(entry)
            return {
                display = entry.path, ordinal = entry.path,
                lnum = entry.lnum, text = entry.text, path = entry.path,
                file = entry.file, value_text = entry.value_text,
            }
        end,
        on_select = function(sel)
            pcall(vim.api.nvim_win_set_cursor, 0, { sel.lnum, 0 })
            history.add("paths", sel.path)
        end,
        on_attach = function(pb, map)
            M.add_edit_action(pb, map)
        end,
    }

    require("yaml-jumper.picker").create_picker(picker_opts, config):find()
end

function M.jump_to_key()
    local lines = utils.read_file_lines()
    local matches = parser.find_keys_with_prefix("", lines)

    local picker_opts = {
        prompt_title = "YAML Key",
        results = matches,
        entry_maker = function(entry)
            return {
                value = entry, display = entry.key, ordinal = entry.key,
                lnum = entry.line, text = entry.text,
            }
        end,
        on_select = function(sel)
            pcall(vim.api.nvim_win_set_cursor, 0, { sel.lnum, 0 })
        end,
    }

    require("yaml-jumper.picker").create_picker(picker_opts, config):find()
end

function M.jump_to_value()
    local lines = utils.read_file_lines()
    local values = parser.get_yaml_values(lines)
    local filename = vim.api.nvim_buf_get_name(0)
    local bufnr = vim.api.nvim_get_current_buf()

    local picker_opts = {
        prompt_title = "YAML Value Search",
        results = vim.tbl_map(function(entry)
            return {
                buf = bufnr, lnum = entry.line, text = entry.text,
                path = entry.path, filename = filename, file = filename,
                value_text = entry.value,
            }
        end, values),
        entry_maker = function(entry)
            local disp = entry.path .. ": " .. (entry.value_text or "")
            return {
                value = entry, display = disp,
                ordinal = entry.path .. " " .. (entry.value_text or ""),
                lnum = entry.lnum, text = entry.text, path = entry.path,
                value_text = entry.value_text, filename = entry.filename, file = entry.file,
            }
        end,
        on_select = function(sel)
            pcall(vim.api.nvim_win_set_cursor, 0, { sel.lnum, 0 })
            history.add("values", sel.path .. ": " .. (sel.value_text or ""))
        end,
        on_attach = function(pb, map)
            M.add_edit_action(pb, map)
        end,
    }

    require("yaml-jumper.picker").create_picker(picker_opts, config):find()
end

function M.jump_to_specific_path(path_string)
    local lines = utils.read_file_lines()
    local keys = utils.parse_path(path_string)
    local matches = parser.find_yaml_path(keys, lines)
    if #matches > 0 then
        pcall(vim.api.nvim_win_set_cursor, 0, { matches[1].line, 0 })
        vim.notify("Jumped to: " .. path_string, vim.log.levels.INFO)
    else
        vim.notify("Path not found: " .. path_string, vim.log.levels.WARN)
    end
end

function M.jump_to_specific_value(value_string)
    local path, value = value_string:match("^(.+): (.+)$")
    if not path then
        vim.notify("Invalid value format: " .. value_string, vim.log.levels.ERROR)
        return
    end
    local lines = utils.read_file_lines()
    local keys = utils.parse_path(path)
    local pm = parser.find_yaml_path(keys, lines)
    if #pm > 0 then
        pcall(vim.api.nvim_win_set_cursor, 0, { pm[1].line, 0 })
        vim.notify("Jumped to: " .. value_string, vim.log.levels.INFO)
        return
    end
    local vals = parser.get_yaml_values(lines)
    for _, entry in ipairs(vals) do
        if entry.path == path and entry.value == value then
            pcall(vim.api.nvim_win_set_cursor, 0, { entry.line, 0 })
            vim.notify("Jumped to: " .. value_string, vim.log.levels.INFO)
            return
        end
    end
    vim.notify("Value not found: " .. value_string, vim.log.levels.WARN)
end

return M
