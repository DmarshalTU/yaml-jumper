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
    -- Clear log file at start
    local file = io.open(log_file, "w")
    if file then file:close() end
    
    -- Log input options
    log("Input options: " .. vim.inspect(opts))
    
    local entries = {}
    local seen_paths = {}
    local current_buf = vim.api.nvim_get_current_buf()
    local current_file = vim.api.nvim_buf_get_name(current_buf)

    -- Log current buffer info
    log("Current buffer: " .. current_buf .. ", file: " .. current_file)

    -- Helper function to extract value from YAML text
    local function extract_value(text)
        if not text then return "" end
        local value = text:match(":%s*(.+)$")
        return value and value:gsub("^%s*(.-)%s*$", "%1") or ""
    end

    -- Create entries for snacks
    for _, item in ipairs(opts.results) do
        -- Log each item being processed
        log("Processing item: " .. vim.inspect(item))
        
        if not seen_paths[item.path] then
            seen_paths[item.path] = true
            local value = extract_value(item.text)
            
            -- Log extracted value
            log("Path: " .. item.path .. ", Value: " .. value)
            
            local entry = {
                value = item,
                display = function()
                    return string.format("%-40s = %s", item.path, value)
                end,
                text = item.text,
                lnum = item.line or 1,
                col = 1,
                buf = current_buf,
                file = current_file,
                filename = current_file,
                path = item.path,
                value_text = value,
                label = item.path,
                description = value,
                jump = {
                    line = item.line or 1,
                    col = 1
                }
            }
            
            -- Log created entry
            log("Created entry: " .. vim.inspect(entry))
            
            table.insert(entries, entry)
        end
    end

    -- Log final entries count
    log("Total entries created: " .. #entries)

    -- Create the picker with proper configuration
    local picker = require("snacks").picker({
        items = entries,
        prompt = "YAML Jump: ",
        layout = {
            width = 0.8,
            height = 0.8,
        },
        jump = {
            jumplist = true,
            close = true,
            match = false,
        },
        preview = function(entry)
            -- Log preview request
            log("Preview requested for: " .. vim.inspect(entry))
            
            if not entry or not entry.value then return end
            local item = entry.value
            local filename = item.filename
            if not filename then return end

            local start_line = math.max(1, item.line - 5)
            local end_line = item.line + 5
            local lines = vim.fn.readfile(filename, "", end_line)
            local context = {}
            
            for i = start_line, math.min(end_line, #lines) do
                table.insert(context, lines[i])
            end

            return {
                filetype = "yaml",
                contents = context,
                syntax = "yaml",
                highlight_line = item.line - start_line + 1,
            }
        end,
        on_select = function(selection)
            -- Log selection
            log("Selection made: " .. vim.inspect(selection))
            
            if not selection or not selection.value then return end
            local item = selection.value
            local filename = item.filename
            if not filename then return end

            -- Open the file if needed
            if vim.fn.expand("%:p") ~= filename then
                vim.cmd("edit " .. filename)
            end

            -- Jump to the line
            vim.api.nvim_win_set_cursor(0, {item.line, 0})
            vim.cmd("normal! zz") -- Center the line
        end,
    })

    return picker
end

return M 