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
        return M.create_telescope_picker(opts, config)
    else
        return M.create_snacks_picker(opts, config)
    end
end

-- Create a telescope picker
function M.create_telescope_picker(opts, config)
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
function M.create_snacks_picker(opts, config)
    -- Debug log the input options
    log("Creating snacks picker with options: " .. vim.inspect(opts))
    
    -- Create entries for snacks
    local entries = {}
    for _, item in ipairs(opts.results) do
        -- Debug log the item being processed
        log("Processing item: " .. vim.inspect(item))
        
        -- Extract value from text if not provided
        local value = item.value_text
        if not value and item.text then
            local _, val = item.text:match("^%s*[^:]+:%s*(.+)$")
            if val then
                value = val:gsub("^%s*(.-)%s*$", "%1")
            end
        end
        
        -- Debug log the extracted value
        log("Extracted value: " .. tostring(value))
        
        -- Create entry
        local entry = {
            value = item,
            text = item.text,
            lnum = item.lnum,
            col = item.col or 0,
            buf = item.buf,
            file = item.file_path,
            filename = item.file_path or vim.api.nvim_buf_get_name(0),
            path = item.path,
            value_text = value,
            label = item.path,
            description = value and (" = " .. value) or "",
            preview = function(self)
                if not self.filename then return end
                
                -- Get the current line and some context
                local start_line = math.max(1, self.lnum - 5)
                local end_line = self.lnum + 5
                local lines = vim.fn.readfile(self.filename, "", end_line)
                local context = {}
                
                -- Add context lines
                for i = start_line, math.min(end_line, #lines) do
                    if i == self.lnum then
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
                    highlight_line = self.lnum - start_line + 1,
                }
            end
        }
        
        -- Debug log the created entry
        log("Created entry: " .. vim.inspect(entry))
        
        table.insert(entries, entry)
    end
    
    -- Debug log total entries
    log("Total entries created: " .. #entries)
    
    -- Create the picker
    local picker = require("snacks").create({
        title = opts.prompt_title or "YAML Jumper",
        entries = entries,
        matcher = function(query, entry)
            -- Support both fuzzy and exact matching for paths
            local path = entry.path:lower()
            local q = query:lower()
            return path:find(q, 1, true) or path:match(q)
        end,
        sorter = function(a, b)
            -- Sort by path length and then alphabetically
            if #a.path ~= #b.path then
                return #a.path < #b.path
            end
            return a.path < b.path
        end,
        format = function(entry)
            -- Format the display with proper highlighting
            local display = {}
            
            -- Add the path with keyword highlighting
            table.insert(display, { entry.label, "Keyword" })
            
            -- Add the value if it exists
            if entry.description and entry.description ~= "" then
                table.insert(display, { " = ", "Normal" })
                table.insert(display, { entry.description:sub(4), "String" })
            end
            
            return display
        end,
        preview = function(entry)
            if not entry or not entry.value then return end
            return entry:preview()
        end,
        values = function(entry)
            if not entry or not entry.value then 
                log("No entry or value in values function")
                return {} 
            end
            
            -- Debug log the entry
            log(string.format("Processing values for entry: %s", vim.inspect(entry)))
            
            -- Get the value with its path for context
            if entry.description and entry.description ~= "" then
                local result = { entry.label .. entry.description }
                log(string.format("Returning value: %s", vim.inspect(result)))
                return result
            end
            
            log("No value found, returning empty table")
            return {}
        end,
        on_select = function(entry)
            if not entry or not entry.value then return end
            
            -- Debug log the selected entry
            log("Selected entry: " .. vim.inspect(entry))
            
            -- Get the filename and line number
            local filename = entry.filename
            local lnum = entry.lnum
            
            -- Open the file if it's not the current buffer
            if filename and filename ~= vim.api.nvim_buf_get_name(0) then
                vim.cmd("edit " .. vim.fn.fnameescape(filename))
            end
            
            -- Set cursor to the beginning of the line
            if lnum then
                vim.api.nvim_win_set_cursor(0, {lnum, 0})
                vim.cmd("normal! zz") -- Center the cursor line
            end
            
            -- Call the original on_select if it exists
            if opts.on_select then
                opts.on_select(entry.value)
            end
        end
    })
    
    return picker
end

return M 