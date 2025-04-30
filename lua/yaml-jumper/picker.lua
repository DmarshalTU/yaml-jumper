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
    local current_file = vim.api.nvim_buf_get_name(0)
    local seen_paths = {} -- Track seen paths to avoid duplicates
    
    for _, item in ipairs(opts.results) do
        -- Skip if we've already seen this path
        if seen_paths[item.path] then
            goto continue
        end
        seen_paths[item.path] = true
        
        -- Extract value from text
        local value = extract_value(item.text)
        
        -- Create the display string with proper formatting
        local display = string.format("%-40s %s", item.path, value or "")
        
        -- Create the entry with all required fields
        local snack_entry = {
            value = item,
            display = display,
            ordinal = item.path,
            filename = current_file,
            file = current_file,
            lnum = item.line or 1, -- Ensure we have a line number
            text = item.text,
            path = item.path,
            key = item.key,
            value_text = value,
            -- Add Snacks-specific fields
            label = display,
            description = value or "",
            -- Add the actual value for display
            value = value
        }
        
        table.insert(entries, snack_entry)
        
        ::continue::
    end
    
    -- Create the picker using Snacks.picker
    local picker = Snacks.picker({
        prompt = opts.prompt_title,
        items = entries,
        on_select = function(selection)
            if selection and selection.value and selection.value.line then
                -- Jump to the line
                vim.api.nvim_win_set_cursor(0, {selection.value.line, 0})
                -- Add to history if the callback exists
                if opts.on_select then
                    opts.on_select(selection)
                end
            end
        end,
        preview = function(entry)
            if not entry.filename then return end
            
            -- Create a preview buffer
            local preview_bufnr = vim.api.nvim_create_buf(false, true)
            
            -- Get the content around the target line
            local lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr(entry.filename), 0, -1, false)
            local start_line = math.max(0, (entry.value and entry.value.line or entry.lnum) - 5)
            local end_line = math.min(#lines, (entry.value and entry.value.line or entry.lnum) + 5)
            
            local preview_lines = {}
            for i = start_line, end_line do
                if i == (entry.value and entry.value.line or entry.lnum) - 1 then
                    -- Highlight the current line
                    table.insert(preview_lines, "> " .. lines[i])
                else
                    table.insert(preview_lines, "  " .. lines[i])
                end
            end
            
            -- Set the preview content
            vim.api.nvim_buf_set_lines(preview_bufnr, 0, -1, false, preview_lines)
            
            -- Set filetype for syntax highlighting
            vim.api.nvim_buf_set_option(preview_bufnr, "filetype", "yaml")
            
            return preview_bufnr
        end,
        attach_mappings = function(map)
            if opts.on_attach then
                opts.on_attach(nil, map)
            end
        end,
        matcher = {
            fuzzy = true,
            smartcase = true,
            ignorecase = true
        },
        sort = {
            fields = { "ordinal" }
        },
        layout = {
            preview = "main"
        },
        -- Add custom display format
        display = function(entry)
            return entry.display
        end
    })
    
    return picker
end

return M 