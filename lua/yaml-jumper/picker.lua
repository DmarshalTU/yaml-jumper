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
    local Snacks = require("snacks")
    
    -- Helper function to extract value from YAML text
    local function extract_value(text)
        if not text then return nil end
        local _, value = text:match("^[^:]+:%s*(.+)$")
        return value
    end
    
    -- Create entries for snacks
    local entries = {}
    local seen_paths = {}
    
    for _, item in ipairs(opts.results) do
        if not seen_paths[item.path] then
            seen_paths[item.path] = true
            local display = string.format("%-40s %s", item.path, item.value_text or item.text or "")
            table.insert(entries, {
                value = item,
                display = display,
                ordinal = item.path .. " " .. (item.value_text or item.text or ""),
                filename = item.filename,
                lnum = item.line or 1,
                text = display,
            })
        end
    end
    
    return Snacks.picker({
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
                local bufnr = vim.fn.bufnr(selection.value.filename)
                if bufnr == -1 then
                    bufnr = vim.fn.bufadd(selection.value.filename)
                end
                vim.api.nvim_set_current_buf(bufnr)
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