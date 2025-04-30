local M = {}

-- Create a picker based on the configured type
function M.create_picker(opts, config)
    if config.picker_type == "telescope" then
        return M.create_telescope_picker(opts)
    else
        return M.create_snacks_picker(opts)
    end
end

-- Create a telescope picker
function M.create_telescope_picker(opts)
    local telescope = require("telescope.pickers")
    local finders = require("telescope.finders")
    local previewers = require("telescope.previewers")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    
    return telescope.new(opts, {
        prompt_title = opts.prompt_title,
        finder = finders.new_table {
            results = opts.results,
            entry_maker = opts.entry_maker
        },
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = opts.previewer,
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection and opts.on_select then
                    opts.on_select(selection)
                end
            end)
            
            if opts.on_attach then
                opts.on_attach(prompt_bufnr, map)
            end
            
            return true
        end
    })
end

-- Create a snacks picker
function M.create_snacks_picker(opts)
    local entries = {}
    local seen_paths = {}
    local current_file = vim.api.nvim_buf_get_name(0)
    local current_buf = vim.api.nvim_get_current_buf()

    for _, item in ipairs(opts.results) do
        if not seen_paths[item.path] then
            seen_paths[item.path] = true
            local display = string.format("%-40s %s", item.path, item.value or item.value_text or "")
            table.insert(entries, {
                value = item,
                display = display,
                ordinal = item.path .. " " .. (item.value or item.value_text or ""),
                buf = current_buf,
                file = current_file,
                lnum = item.line or 1,
                text = display,
                preview = function(entry, state)
                    local bufnr = state.bufnr
                    local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
                    local lnum = entry.lnum
                    local start_line = math.max(0, lnum - 5)
                    local end_line = math.min(#lines, lnum + 5)
                    local preview_lines = {}
                    
                    for i = start_line, end_line do
                        if i == lnum - 1 then
                            table.insert(preview_lines, "> " .. lines[i])
                        else
                            table.insert(preview_lines, "  " .. lines[i])
                        end
                    end
                    
                    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, preview_lines)
                    vim.api.nvim_buf_set_option(bufnr, "filetype", "yaml")
                end
            })
        end
    end

    return require("snacks").picker({
        items = entries,
        title = " YAML Paths ",
        title_pos = "center",
        border = "rounded",
        width = 0.8,
        height = 0.6,
        preview = {
            enabled = true,
            filetype = "yaml",
            lines = 10,
        },
        on_select = function(selection)
            if selection and selection.value and selection.value.line then
                vim.api.nvim_win_set_cursor(0, {selection.value.line, 0})
            end
        end,
        keys = {
            q = "close",
            ["<CR>"] = "select",
            ["<C-c>"] = "close",
        },
    })
end

return M 