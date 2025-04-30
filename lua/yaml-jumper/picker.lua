local M = {}

-- Log file path
local log_file = vim.fn.expand("~/.local/share/nvim/yaml-jumper.log")

-- Helper function to write to log file
local function log(msg)
    local file = io.open(log_file, "a")
    if file then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        file:write(string.format("[%s] %s\n", timestamp, msg))
        file:close()
    end
end

-- Create a picker based on the configured type
function M.create_picker(opts, config)
    if config.picker_type == "telescope" then
        return M.create_telescope_picker(opts)
    elseif config.picker_type == "snacks" then
        return M.create_snacks_picker(opts)
    else
        vim.notify("Invalid picker type: " .. config.picker_type, vim.log.levels.ERROR)
        return nil
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
    local current_buf = vim.api.nvim_get_current_buf()
    local current_file = vim.api.nvim_buf_get_name(current_buf)

    -- Create entries for snacks
    for _, item in ipairs(opts.results) do
        -- Extract value from text if not provided
        local value = item.value
        if not value then
            -- Try to extract value from the line
            local _, val = item.text:match("^%s*[^:]+:%s*(.+)$")
            if val then
                value = val:gsub("^%s*(.-)%s*$", "%1")
            end
        end

        -- Create a clean entry with only the relevant information
        local entry = {
            value = item,
            text = item.text,
            lnum = item.line,
            col = 1,
            buf = current_buf,
            file = current_file,
            filename = current_file,
            path = item.path,
            value_text = value,
            label = item.path,
            description = value,
            preview = {
                text = item.text,
                ft = "yaml",
                loc = true
            }
        }
        
        table.insert(entries, entry)
    end

    -- Create the picker with proper configuration
    local picker = require("snacks").picker({
        items = entries,
        prompt = "YAML Jump: ",
        layout = {
            width = 0.8,
            height = 0.8,
            cycle = true,
            preset = function()
                return vim.o.columns >= 120 and "default" or "vertical"
            end,
        },
        jump = {
            jumplist = true,
            close = true,
            match = false,
            reuse_win = true,
        },
        matcher = {
            fuzzy = true,
            smartcase = true,
            ignorecase = true,
            sort_empty = false,
            -- Add exact matching for paths
            match_fn = function(item, query)
                if not query or query == "" then return true end
                -- First try exact match
                if item.path == query then return true end
                -- Then try fuzzy match
                return item.path:lower():find(query:lower(), 1, true) ~= nil
            end
        },
        sort = {
            fields = { "score:desc", "#text", "idx" },
        },
        win = {
            input = {
                keys = {
                    ["<CR>"] = { "confirm", mode = { "n", "i" } },
                    ["<Esc>"] = "cancel",
                    ["<C-e>"] = { "edit", mode = { "n", "i" } },
                },
            },
        },
        on_select = function(selection)
            if not selection or not selection.value then return end
            local item = selection.value
            
            -- Open the file if needed
            if vim.fn.expand("%:p") ~= item.filename then
                vim.cmd("edit " .. item.filename)
            end

            -- Jump to the beginning of the line
            vim.api.nvim_win_set_cursor(0, {item.lnum, 0})
            
            -- Add to history if on_select callback exists
            if opts.on_select then
                opts.on_select(selection)
            end
        end,
        format = function(item)
            -- Create a more visible display format
            local display = {}
            
            -- Add the path in a visible color
            table.insert(display, { item.path, "Keyword" })
            
            -- Add the value if it exists
            if item.value_text and item.value_text ~= "" then
                table.insert(display, { " = ", "Normal" })
                table.insert(display, { item.value_text, "String" })
            end
            
            return display
        end,
        preview = function(entry)
            if not entry or not entry.value then return end
            local item = entry.value
            local filename = item.filename
            if not filename then return end

            -- Get the current line and some context
            local start_line = math.max(1, item.lnum - 5)
            local end_line = item.lnum + 5
            local lines = vim.fn.readfile(filename, "", end_line)
            local context = {}
            
            -- Add context lines
            for i = start_line, math.min(end_line, #lines) do
                if i == item.lnum then
                    -- Highlight the current line
                    table.insert(context, "> " .. lines[i])
                else
                    table.insert(context, "  " .. lines[i])
                end
            end

            return {
                filetype = "yaml",
                contents = context,
                syntax = "yaml",
                highlight_line = item.lnum - start_line + 1,
            }
        end,
        values = function(entry)
            if not entry or not entry.value then return {} end
            local item = entry.value
            
            -- Extract value from text if not already available
            local value = item.value_text
            if not value then
                local _, val = item.text:match("^%s*[^:]+:%s*(.+)$")
                if val then
                    value = val:gsub("^%s*(.-)%s*$", "%1")
                end
            end
            
            -- Get the parent path for context
            local path_parts = vim.split(item.path, ".", { plain = true })
            local parent_path = table.concat(path_parts, ".", 1, #path_parts - 1)
            
            -- Format the value with context
            local formatted_value = {}
            if parent_path ~= "" then
                table.insert(formatted_value, parent_path .. ":")
            end
            table.insert(formatted_value, "  " .. path_parts[#path_parts] .. ": " .. (value or ""))
            
            -- Only return the value if it exists and isn't empty
            if value and value ~= "" then
                return formatted_value
            end
            return {}
        end
    })

    return picker
end

return M 