local config = require("yaml-jumper.config")
local parser = require("yaml-jumper.parser")
local utils = require("yaml-jumper.utils")

local M = {}

function M.search_paths_in_project()
    local files = parser.find_yaml_files()
    if #files == 0 then
        vim.notify("No YAML files found in the project", vim.log.levels.WARN)
        return
    end

    local all_paths = {}
    for _, fp in ipairs(files) do
        local lines = utils.read_file_lines(fp)
        if #lines > 0 then
            local meta = utils.file_meta(fp)
            for _, p in ipairs(parser.get_yaml_paths(lines, fp)) do
                p.file_path = meta.file_path
                p.file_name = meta.file_name
                p.relative_path = meta.relative_path
                all_paths[#all_paths + 1] = p
            end
        end
    end

    local picker_opts = {
        prompt_title = "YAML Paths in Project",
        results = all_paths,
        entry_maker = function(entry)
            return {
                value = entry,
                display = (entry.relative_path or "") .. ":" .. (entry.path or ""),
                ordinal = (entry.file_name or "") .. " " .. (entry.path or ""),
                filename = entry.file_path, lnum = entry.line, text = entry.text,
            }
        end,
        on_select = function(sel)
            if vim.fn.expand("%:p") ~= sel.filename then
                vim.cmd("edit " .. vim.fn.fnameescape(sel.filename))
            end
            pcall(vim.api.nvim_win_set_cursor, 0, { sel.lnum, 0 })
        end,
    }

    require("yaml-jumper.picker").create_picker(picker_opts, config):find()
end

function M.search_values_in_project()
    local files = parser.find_yaml_files()
    if #files == 0 then
        vim.notify("No YAML files found in the project", vim.log.levels.WARN)
        return
    end

    local all_values = {}
    for _, fp in ipairs(files) do
        local lines = utils.read_file_lines(fp)
        if #lines > 0 then
            local meta = utils.file_meta(fp)
            for _, v in ipairs(parser.get_yaml_values(lines, fp)) do
                v.file_path = meta.file_path
                v.file_name = meta.file_name
                v.relative_path = meta.relative_path
                all_values[#all_values + 1] = v
            end
        end
    end

    local picker_opts = {
        prompt_title = "YAML Values in Project",
        results = all_values,
        entry_maker = function(entry)
            local val = entry.value or ""
            local path = entry.path or ""
            return {
                value = entry,
                display = (entry.relative_path or "") .. ": " .. path .. " = " .. val,
                ordinal = (entry.file_name or "") .. " " .. path .. " " .. val,
                filename = entry.file_path, lnum = entry.line,
                text = entry.text, value_text = val,
            }
        end,
        on_select = function(sel)
            if vim.fn.expand("%:p") ~= sel.filename then
                vim.cmd("edit " .. vim.fn.fnameescape(sel.filename))
            end
            pcall(vim.api.nvim_win_set_cursor, 0, { sel.lnum, 0 })
        end,
    }

    require("yaml-jumper.picker").create_picker(picker_opts, config):find()
end

return M
