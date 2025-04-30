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
    if config.picker_type == "snacks" then
        return M.create_snacks_picker(opts, config)
    else
        return M.create_telescope_picker(opts, config)
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
    -- Debug log the options
    log(string.format("Creating snacks picker with options: %s", vim.inspect(opts)))

    local entries = {}
    local current_buf = vim.api.nvim_get_current_buf()
    local current_file = vim.api.nvim_buf_get_name(current_buf)

    -- Create entries for snacks
    for _, item in ipairs(opts.results) do
        -- Debug log the item being processed
        log(string.format("Processing item: %s", vim.inspect(item)))

        -- Extract value from text
        local value = nil
        if item.text then
            local _, val = item.text:match("^%s*[^:]+:%s*(.+)$")
            if val then
                value = val:gsub("^%s*(.-)%s*$", "%1")
            end
        end

        -- Create entry with all necessary fields
        local entry = {
            value = item,
            text = item.text,
            lnum = item.line or item.lnum,
            col = 0,
            buf = current_buf,
            file = current_file,
            filename = current_file,
            path = item.path,
            value_text = value,
            label = item.path,
            description = value
        }

        -- Debug log the created entry
        log(string.format("Created entry: %s", vim.inspect(entry)))
        table.insert(entries, entry)
    end

    -- Create picker configuration
    local picker = require("snacks").picker({
        items = entries,
        prompt = "YAML Jump: ",
        layout = {
            width = 0.8,
            height = 0.8,
            cycle = true,
            preset = "default"
        },
        jump = {
            jumplist = true,
            close = true,
            match = false,
            reuse_win = true
        },
        matcher = {
            fuzzy = true,
            smartcase = true,
            ignorecase = true
        },
        sort = {
            fields = { "score:desc", "#text", "idx" }
        },
        win = {
            input = {
                keys = {
                    ["<CR>"] = { "confirm", mode = { "n", "i" } },
                    ["<Esc>"] = "cancel",
                    ["<C-e>"] = { "edit", mode = { "n", "i" } }
                }
            }
        },
        on_select = function(selection)
            if not selection or not selection.value then
                log("No selection or value in on_select")
                return
            end

            local item = selection.value
            log(string.format("Selected item: %s", vim.inspect(item)))

            -- Get line number
            local line_number = item.line or item.lnum
            if not line_number then
                log("No line number found in item")
                return
            end

            -- Position cursor at start of line
            vim.api.nvim_win_set_cursor(0, {line_number, 0})
            log(string.format("Set cursor to line %d", line_number))

            -- Call on_select callback if provided
            if opts.on_select then
                opts.on_select(selection)
            end
        end,
        format = function(item)
            local display = {}
            
            -- Add path with highlighting
            table.insert(display, { item.path, "Keyword" })
            
            -- Get value from text
            local value = nil
            if item.text then
                local _, val = item.text:match("^%s*[^:]+:%s*(.+)$")
                if val then
                    value = val:gsub("^%s*(.-)%s*$", "%1")
                end
            end
            
            -- Add value if it exists
            if value and value ~= "" then
                table.insert(display, { " = ", "Normal" })
                table.insert(display, { value, "String" })
            end
            
            return display
        end,
        values = function(entry)
            if not entry or not entry.value then
                log("No entry or value in values function")
                return {}
            end

            local item = entry.value
            log(string.format("Processing values for entry: %s", vim.inspect(item)))

            -- Get value from text
            local value = nil
            if item.text then
                local _, val = item.text:match("^%s*[^:]+:%s*(.+)$")
                if val then
                    value = val:gsub("^%s*(.-)%s*$", "%1")
                end
            end

            -- If no value found, return empty table
            if not value or value == "" then
                log("No value found")
                return {}
            end

            -- Format value with path context
            local path_parts = vim.split(item.path, ".", { plain = true })
            local parent_path = table.concat(path_parts, ".", 1, #path_parts - 1)
            local last_part = path_parts[#path_parts]

            local formatted_value = {}
            if parent_path ~= "" then
                table.insert(formatted_value, parent_path .. ":")
            end
            table.insert(formatted_value, "  " .. last_part .. ": " .. value)

            log(string.format("Returning formatted value: %s", vim.inspect(formatted_value)))
            return formatted_value
        end,
        preview = function(entry)
            if not entry or not entry.value then return end
            local item = entry.value
            local filename = item.filename
            if not filename then return end

            local start_line = math.max(1, item.lnum - 5)
            local end_line = item.lnum + 5
            local lines = vim.fn.readfile(filename, "", end_line)
            local context = {}
            
            for i = start_line, math.min(end_line, #lines) do
                if i == item.lnum then
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
        end
    })

    return picker
end

return M 