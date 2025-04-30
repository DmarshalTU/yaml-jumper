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
    local current_file = vim.api.nvim_buf_get_name(0)
    local seen_entries = {} -- Track seen entries using a composite key
    
    for _, item in ipairs(opts.results) do
        local entry = opts.entry_maker(item)
        local filename = entry.filename or current_file
        local bufnr = vim.fn.bufnr(filename)
        
        -- Create a unique key for this entry
        local entry_key = string.format("%s:%s:%d", filename, entry.path or entry.key or "", entry.lnum or entry.line or 0)
        
        -- Skip if we've already seen this exact entry
        if seen_entries[entry_key] then
            goto continue
        end
        seen_entries[entry_key] = true
        
        -- Create a proper display string
        local display = entry.path or entry.key or "Unknown"
        if entry.value_text then
            display = display .. ": " .. entry.value_text
        elseif entry.text then
            display = display .. ": " .. entry.text
        end
        
        -- Create a proper ordinal for sorting
        local ordinal = entry.path or entry.key or display
        
        -- Create the entry with all required fields
        local snack_entry = {
            value = entry,
            display = display,
            ordinal = ordinal,
            filename = filename,
            file = filename,  -- Required by Snacks for jumping
            buf = bufnr,     -- Required by Snacks for jumping
            lnum = entry.lnum or entry.line or 1,
            text = entry.text or display,
            path = entry.path,
            value_text = entry.value_text or entry.value,
            key = entry.key
        }
        
        -- Only add the entry if it has a valid display string and path
        if display ~= "Unknown" and (snack_entry.path or snack_entry.key) then
            table.insert(entries, snack_entry)
        end
        
        ::continue::
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
            if not entry.filename then return end
            
            -- Create a preview buffer
            local preview_bufnr = vim.api.nvim_create_buf(false, true)
            
            -- Get the content around the target line
            local lines = vim.api.nvim_buf_get_lines(vim.fn.bufnr(entry.filename), 0, -1, false)
            local start_line = math.max(0, entry.lnum - 5)
            local end_line = math.min(#lines, entry.lnum + 5)
            
            local preview_lines = {}
            for i = start_line, end_line do
                if i == entry.lnum - 1 then
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
        -- Add snacks picker specific options
        matcher = {
            fuzzy = true,
            smartcase = true,
            ignorecase = true,
            sort_empty = false,
            filename_bonus = true,
            file_pos = true,
            cwd_bonus = false,
            frecency = false,
            history_bonus = false
        },
        sort = {
            fields = { "score:desc", "#text", "idx" }
        },
        layout = {
            preset = "default",
            preview = "main"
        },
        -- Add Snacks-specific options to avoid conflicts
        picker = {
            enabled = true,
            preview = true,
            preview_lines = 10,
            preview_border = "rounded",
            preview_highlight = "Normal",
            preview_winblend = 0,
            preview_winhighlight = "Normal:NormalFloat",
            preview_winopts = {
                relative = "editor",
                style = "minimal",
                border = "rounded",
                title = "YAML Preview",
                title_pos = "center",
                zindex = 50
            }
        }
    })
    
    return picker
end

return M 