local config = require("yaml-jumper.config")

local M = {}

function M.read_file_lines(file_path)
    if not file_path then
        return vim.api.nvim_buf_get_lines(0, 0, -1, false)
    end
    local size = vim.fn.getfsize(file_path)
    if size > config.max_file_size then
        vim.notify("File too large to process: " .. file_path, vim.log.levels.WARN)
        return {}
    end
    local file, err = io.open(file_path, "r")
    if not file then
        vim.notify("Error opening file: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return {}
    end
    local lines = {}
    for line in file:lines() do
        lines[#lines + 1] = line
    end
    file:close()
    return lines
end

function M.parse_path(path)
    local keys = {}
    for key in path:gmatch("[^%.]+") do
        keys[#keys + 1] = key
    end
    return keys
end

function M.extract_value_from_line(text)
    if not text then
        return nil
    end
    local val = text:match("^%s*[^:]+:%s*(.+)$")
    if val then
        return val:gsub("^%s*(.-)%s*$", "%1")
    end
    return nil
end

function M.file_meta(file_path)
    return {
        file_path = file_path,
        file_name = vim.fn.fnamemodify(file_path, ":t"),
        relative_path = vim.fn.fnamemodify(file_path, ":~:."),
    }
end

return M
