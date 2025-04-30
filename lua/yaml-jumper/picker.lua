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
    
    -- Create entries for snacks
    local entries = {}
    for _, item in ipairs(opts.results) do
        local entry = opts.entry_maker(item)
        local filename = entry.filename or vim.api.nvim_buf_get_name(0)
        local bufnr = vim.fn.bufnr(filename)
        
        -- Create a proper display string
        local display = entry.path
        if entry.value_text then
            display = display .. ": " .. entry.value_text
        end
        
        table.insert(entries, {
            value = entry.value,
            display = display,
            ordinal = entry.ordinal,
            filename = filename,
            bufnr = bufnr,
            file = filename,
            lnum = entry.lnum,
            text = entry.text,
            path = entry.path,
            value_text = entry.value_text
        })
    end
    
    -- Create the picker using Snacks.picker
    local picker = Snacks.picker({
        prompt = opts.prompt_title,
        items = entries,
        on_select = function(selection)
            if opts.on_select then
                opts.on_select(selection)
            end
        end,
        preview = function(entry)
            if not entry.bufnr then return end
            
            -- Create a preview buffer
            local preview_bufnr = vim.api.nvim_create_buf(false, true)
            
            -- Get the content around the target line
            local lines = vim.api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
            local start_line = math.max(0, entry.lnum - 5)
            local end_line = math.min(#lines, entry.lnum + 5)
            
            local preview_lines = {}
            for i = start_line, end_line do
                if i == entry.lnum - 1 then
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
        end
    })
    
    return picker
end

return M 