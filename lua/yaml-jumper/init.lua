-- yaml-jumper.init
-- Efficient YAML navigation and search for Neovim
-- Author: DmarshalTU
-- License: MIT

local M = {}

-- Module-level cache for performance
local cache = {
    paths = {},
    values = {}
}

-- Configuration with defaults
local config = {
    highlights = {
        enabled = true,
        path = { bg = '#404040', fg = '#ffffff', bold = true },
        key = { fg = '#ff9900', bg = '#333333', bold = true }
    },
    max_file_size = 1024 * 1024, -- 1MB max file size for scanning
    max_preview_lines = 20,
    cache_enabled = true,
    cache_ttl = 30, -- seconds
    depth_limit = 10 -- Max directory scan depth
}

-- Helper functions
local utils = {}

-- Clear cache for a file or all files
function utils.clear_cache(file_path)
    if file_path then
        cache.paths[file_path] = nil
        cache.values[file_path] = nil
    else
        cache.paths = {}
        cache.values = {}
    end
end

-- Check if a file is too large to process
function utils.is_file_too_large(file_path)
    local size = vim.fn.getfsize(file_path)
    return size > config.max_file_size
end

-- Parse a dot-notation path into a table of keys
function utils.parse_path(path)
    local keys = {}
    for key in path:gmatch("([^%.]+)") do
        table.insert(keys, key)
    end
    return keys
end

-- Safely access contents of very large files
function utils.get_file_lines(file_path)
    -- Use cached lines if available and cache is enabled
    if config.cache_enabled and cache.lines and cache.lines[file_path] and 
       (os.time() - (cache.lines_time or 0) < config.cache_ttl) then
        return cache.lines[file_path]
    end
    
    -- Check file size before proceeding
    if file_path and utils.is_file_too_large(file_path) then
        vim.notify("File too large to process: " .. file_path, vim.log.levels.WARN)
        return {}
    end
    
    -- Read file content
    local lines = {}
    if file_path then
        local file, err = io.open(file_path, "r")
        if not file then
            vim.notify("Error opening file: " .. (err or "unknown error"), vim.log.levels.ERROR)
            return {}
        end
        
        for line in file:lines() do
            table.insert(lines, line)
        end
        file:close()
    else
        -- Get lines from current buffer
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    end
    
    -- Cache the result if caching is enabled
    if config.cache_enabled then
        cache.lines = cache.lines or {}
        cache.lines[file_path or "current"] = lines
        cache.lines_time = os.time()
    end
    
    return lines
end

-- Find keys that start with a prefix
function M.find_keys_with_prefix(prefix, lines, options)
    options = options or {}
    local matches = {}
    
    for i, line in ipairs(lines) do
        -- Skip empty lines and comments
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end
        
        -- Extract the key from the current line
        local key = line:match("^%s*([^:]+):")
        if key then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            
            -- Check if key starts with prefix
            if prefix == "" or key:lower():find("^" .. prefix:lower()) then
                table.insert(matches, {
                    line = i,
                    key = key,
                    text = line:gsub("^%s+", ""),
                    path = key
                })
                
                -- Limit results if requested
                if options.limit and #matches >= options.limit then
                    break
                end
            end
        end
        
        ::continue::
    end
    
    return matches
end

-- Find the line number where a specific YAML path exists
function M.find_yaml_path(keys, lines, options)
    options = options or {}
    local current_indent = 0
    local current_keys = {}
    local matches = {}

    for i, line in ipairs(lines) do
        -- Skip empty lines and comments
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end

        -- Get the current line's indent level
        local indent = line:match("^%s*"):len()
        
        -- If we're going back in indentation, remove keys from our path
        while #current_keys > 0 and indent <= current_indent do
            table.remove(current_keys)
            if #current_keys > 0 then
                current_indent = current_indent - 2 -- Assuming 2-space indentation
            else
                current_indent = 0
            end
        end

        -- Extract the key from the current line
        local key = line:match("^%s*([^:]+):")
        if key then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            
            table.insert(current_keys, key)
            current_indent = indent

            -- Check if we've found our path
            local found = true
            for j, k in ipairs(keys) do
                if j > #current_keys or current_keys[j] ~= k then
                    found = false
                    break
                end
            end
            
            if found and #current_keys >= #keys then
                local path = table.concat(current_keys, ".", 1, #keys)
                table.insert(matches, {
                    line = i,
                    key = current_keys[#keys],
                    text = line:gsub("^%s+", ""),
                    path = path
                })
                
                -- Limit results if requested
                if options.limit and #matches >= options.limit then
                    break
                end
            end
        end

        ::continue::
    end

    return matches
end

-- Get all YAML paths from the current buffer or file
function M.get_yaml_paths(lines, file_path)
    -- Use cached paths if available and cache is enabled
    if config.cache_enabled and file_path and cache.paths[file_path] and 
       (os.time() - (cache.paths_time or {})[file_path] or 0) < config.cache_ttl then
        return cache.paths[file_path]
    end
    
    local paths = {}
    local current_indent = 0
    local current_keys = {}

    for i, line in ipairs(lines) do
        -- Skip empty lines and comments
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end

        -- Get the current line's indent level
        local indent = line:match("^%s*"):len()
        
        -- If we're going back in indentation, remove keys from our path
        while #current_keys > 0 and indent <= current_indent do
            table.remove(current_keys)
            if #current_keys > 0 then
                current_indent = current_indent - 2 -- Assuming 2-space indentation
            else
                current_indent = 0
            end
        end

        -- Extract the key from the current line
        local key = line:match("^%s*([^:]+):")
        if key then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            
            table.insert(current_keys, key)
            current_indent = indent
            
            -- Add the current path to our list
            local path = table.concat(current_keys, ".")
            table.insert(paths, {
                line = i,
                key = key,
                text = line:gsub("^%s+", ""),
                path = path
            })
        end

        ::continue::
    end
    
    -- Cache the result if caching is enabled
    if config.cache_enabled and file_path then
        cache.paths = cache.paths or {}
        cache.paths_time = cache.paths_time or {}
        cache.paths[file_path] = paths
        cache.paths_time[file_path] = os.time()
    end

    return paths
end

-- Get all YAML values from the current buffer or file
function M.get_yaml_values(lines, file_path)
    -- Use cached values if available and cache is enabled
    if config.cache_enabled and file_path and cache.values[file_path] and 
       (os.time() - (cache.values_time or {})[file_path] or 0) < config.cache_ttl then
        return cache.values[file_path]
    end
    
    local values = {}
    local current_indent = 0
    local current_keys = {}

    for i, line in ipairs(lines) do
        -- Skip empty lines and comments
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end

        -- Get the current line's indent level
        local indent = line:match("^%s*"):len()
        
        -- If we're going back in indentation, remove keys from our path
        while #current_keys > 0 and indent <= current_indent do
            table.remove(current_keys)
            if #current_keys > 0 then
                current_indent = current_indent - 2 -- Assuming 2-space indentation
            else
                current_indent = 0
            end
        end

        -- Extract the key and value from the current line
        local key, value = line:match("^%s*([^:]+):%s*(.*)$")
        if key and value and value ~= "" then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            value = value:gsub("^%s*(.-)%s*$", "%1")
            
            -- Create the path
            table.insert(current_keys, key)
            current_indent = indent
            local path = table.concat(current_keys, ".")
            
            -- Add the value to our list
            table.insert(values, {
                line = i,
                key = key,
                path = path,
                value = value,
                text = line:gsub("^%s+", "")
            })
            
            -- Remove the key since we've captured its value
            table.remove(current_keys)
        else
            -- If there's a key without a value on this line, it might be a parent node
            key = line:match("^%s*([^:]+):")
            if key then
                key = key:gsub("^%s*(.-)%s*$", "%1")
                table.insert(current_keys, key)
                current_indent = indent
            end
        end

        ::continue::
    end
    
    -- Cache the result if caching is enabled
    if config.cache_enabled and file_path then
        cache.values = cache.values or {}
        cache.values_time = cache.values_time or {}
        cache.values[file_path] = values
        cache.values_time[file_path] = os.time()
    end

    return values
end

-- Find YAML files in the project
function M.find_yaml_files()
    -- Check if plenary is available for file searching
    local has_plenary, plenary_scan = pcall(require, "plenary.scandir")
    if not has_plenary then
        vim.notify("Plenary.nvim is required for multi-file search", vim.log.levels.ERROR)
        return {}
    end
    
    -- Get the project root
    local cwd = vim.fn.getcwd()
    
    -- Scan for YAML files
    local files
    local ok, result = pcall(function()
        return plenary_scan.scan_dir(cwd, {
            hidden = false,
            depth = config.depth_limit,
            search_pattern = function(entry)
                return entry:match("%.ya?ml$")
            end
        })
    end)
    
    if ok then
        files = result
    else
        vim.notify("Error scanning for YAML files: " .. (result or "unknown error"), vim.log.levels.ERROR)
        files = {}
    end
    
    return files
end

-- Edit a YAML value in-place
function M.edit_yaml_value(file_path, line_num, current_value)
    -- If file_path is not provided, use the current buffer
    if not file_path then
        -- Get the current line
        local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]
        
        -- Extract the key-value pattern from the line
        local before_value, value = line:match("^(.+:)%s*(.*)$")
        
        if before_value and value then
            -- Prompt for a new value
            local new_value = vim.fn.input({
                prompt = "New value: ",
                default = value,
                cancelreturn = nil
            })
            
            -- If user didn't cancel and the value changed
            if new_value and new_value ~= value then
                -- Construct the new line
                local new_line = before_value .. " " .. new_value
                
                -- Replace the current line
                vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, false, {new_line})
                vim.notify("Value updated successfully", vim.log.levels.INFO)
                
                -- Clear cache for this file
                utils.clear_cache("current")
                return true
            end
        else
            vim.notify("Could not parse YAML value on this line", vim.log.levels.ERROR)
        end
    else
        -- Open the file if it's not already open
        local current_file = vim.fn.expand("%:p")
        local switched_buffer = false
        local bufnr
        
        if current_file ~= file_path then
            -- Check if the file is already in a buffer
            local bufs = vim.api.nvim_list_bufs()
            for _, buf in ipairs(bufs) do
                if vim.api.nvim_buf_get_name(buf) == file_path then
                    bufnr = buf
                    break
                end
            end
            
            -- If not in a buffer, open it but don't switch
            if not bufnr then
                bufnr = vim.fn.bufadd(file_path)
                vim.fn.bufload(bufnr)
            end
        else
            bufnr = vim.api.nvim_get_current_buf()
        end
        
        -- Read the line to edit
        local line = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1]
        
        -- Extract the key-value pattern from the line
        local before_value, value = line:match("^(.+:)%s*(.*)$")
        
        if before_value and value then
            -- Prompt for a new value
            local new_value = vim.fn.input({
                prompt = "New value: ",
                default = value,
                cancelreturn = nil
            })
            
            -- If user didn't cancel and the value changed
            if new_value and new_value ~= value then
                -- Construct the new line
                local new_line = before_value .. " " .. new_value
                
                -- Replace the current line in the buffer
                vim.api.nvim_buf_set_lines(bufnr, line_num - 1, line_num, false, {new_line})
                
                -- Write the changes if needed
                if not vim.api.nvim_buf_get_option(bufnr, "modified") then
                    vim.api.nvim_buf_call(bufnr, function()
                        vim.cmd("write")
                    end)
                end
                
                vim.notify("Value updated successfully in " .. vim.fn.fnamemodify(file_path, ":t"), vim.log.levels.INFO)
                
                -- Clear cache for this file
                utils.clear_cache(file_path)
                return true
            end
        else
            vim.notify("Could not parse YAML value on this line", vim.log.levels.ERROR)
        end
    end
    
    return false
end

-- Add edit action to the value search
function M.add_edit_action(prompt_bufnr, map)
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    
    -- Add 'e' mapping to edit the value
    map("i", "<C-e>", function()
        local selection = action_state.get_selected_entry()
        if selection then
            actions.close(prompt_bufnr)
            
            -- Edit the value
            local file_path = selection.filename
            local line_num = selection.lnum
            local current_value = selection.value_text or ""
            
            -- Open the file if needed
            if file_path and file_path ~= vim.fn.expand("%:p") then
                pcall(vim.cmd, "edit " .. vim.fn.fnameescape(file_path))
            end
            
            -- Move cursor to the selected line
            pcall(vim.api.nvim_win_set_cursor, 0, {line_num, 0})
            
            -- Edit the value
            M.edit_yaml_value(file_path, line_num, current_value)
        end
    end)
    
    -- Return true to keep the default mappings
    return true
end

-- Jump to a YAML path using telescope
function M.jump_to_path()
    -- Check if telescope is available
    local has_telescope, telescope = pcall(require, "telescope.builtin")
    if not has_telescope then
        vim.notify("Telescope is required for yaml-jumper", vim.log.levels.ERROR)
        return
    end
    
    -- Get lines of current buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = utils.get_file_lines()
    
    -- Get all paths
    local paths = M.get_yaml_paths(lines)
    
    -- Preview function that shows the YAML value at the selected path
    local previewer = require("telescope.previewers").new_buffer_previewer({
        title = "YAML Value Preview",
        define_preview = function(self, entry, status)
            local content = {}
            local lnum = entry.lnum
            
            -- Add selected line
            table.insert(content, lines[lnum])
            
            -- Try to capture the value and any nested content
            local indent_level = lines[lnum]:match("^(%s*)"):len()
            local max_lines = config.max_preview_lines
            local line_count = 0
            
            -- Add lines with deeper indentation (the value and any nested content)
            for i = lnum + 1, #lines do
                if line_count >= max_lines then
                    table.insert(content, "... (more lines not shown)")
                    break
                end
                
                local line = lines[i]
                local line_indent = line:match("^(%s*)"):len()
                
                -- Stop when we reach a line with same or less indentation
                if line_indent <= indent_level then
                    break
                end
                
                table.insert(content, line)
                line_count = line_count + 1
            end
            
            -- Add the content to the preview buffer
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
            
            -- Syntax highlighting for YAML
            vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "yaml")
        end
    })
    
    -- Create finder options
    local opts = {
        prompt_title = "YAML Path",
        finder = require("telescope.finders").new_table {
            results = paths,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.path,
                    ordinal = entry.path,
                    path = entry.path,
                    lnum = entry.line,
                    text = entry.text
                }
            end
        },
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = previewer,
        attach_mappings = function(prompt_bufnr, map)
            local actions = require("telescope.actions")
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = require("telescope.actions.state").get_selected_entry()
                pcall(vim.api.nvim_win_set_cursor, 0, {selection.lnum, 0})
            end)
            
            -- Add edit action
            M.add_edit_action(prompt_bufnr, map)
            
            return true
        end
    }
    
    -- Open telescope
    require("telescope.pickers").new(opts):find()
end

-- Jump to a key prefix using telescope
function M.jump_to_key()
    -- Check if telescope is available
    local has_telescope, telescope = pcall(require, "telescope.builtin")
    if not has_telescope then
        vim.notify("Telescope is required for yaml-jumper", vim.log.levels.ERROR)
        return
    end
    
    -- Get lines of current buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = utils.get_file_lines()
    
    -- Get all keys
    local matches = M.find_keys_with_prefix("", lines)
    
    -- Preview function that shows the YAML value at the selected key
    local previewer = require("telescope.previewers").new_buffer_previewer({
        title = "YAML Value Preview",
        define_preview = function(self, entry, status)
            local content = {}
            local lnum = entry.lnum
            
            -- Add selected line
            table.insert(content, lines[lnum])
            
            -- Try to capture the value and any nested content
            local indent_level = lines[lnum]:match("^(%s*)"):len()
            local max_lines = config.max_preview_lines
            local line_count = 0
            
            -- Add lines with deeper indentation (the value and any nested content)
            for i = lnum + 1, #lines do
                if line_count >= max_lines then
                    table.insert(content, "... (more lines not shown)")
                    break
                end
                
                local line = lines[i]
                local line_indent = line:match("^(%s*)"):len()
                
                -- Stop when we reach a line with same or less indentation
                if line_indent <= indent_level then
                    break
                end
                
                table.insert(content, line)
                line_count = line_count + 1
            end
            
            -- Add the content to the preview buffer
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
            
            -- Syntax highlighting for YAML
            vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "yaml")
        end
    })
    
    -- Create finder options
    local opts = {
        prompt_title = "YAML Key",
        finder = require("telescope.finders").new_table {
            results = matches,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.key,
                    ordinal = entry.key,
                    lnum = entry.line,
                    text = entry.text
                }
            end
        },
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = previewer,
        attach_mappings = function(prompt_bufnr, map)
            local actions = require("telescope.actions")
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = require("telescope.actions.state").get_selected_entry()
                vim.api.nvim_win_set_cursor(0, {selection.lnum, 0})
            end)
            return true
        end
    }
    
    -- Open telescope
    require("telescope.pickers").new(opts):find()
end

-- Jump to a YAML value using telescope
function M.jump_to_value()
    -- Check if telescope is available
    local has_telescope, telescope = pcall(require, "telescope.builtin")
    if not has_telescope then
        vim.notify("Telescope is required for yaml-jumper", vim.log.levels.ERROR)
        return
    end
    
    -- Get lines of current buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = utils.get_file_lines()
    
    -- Get all values
    local values = M.get_yaml_values(lines)
    
    -- Preview function for values
    local previewer = require("telescope.previewers").new_buffer_previewer({
        title = "YAML Context Preview",
        define_preview = function(self, entry, status)
            local content = {}
            local lnum = entry.lnum
            
            -- Try to show some context around the value
            local start_line = math.max(1, lnum - 5)
            local end_line = math.min(#lines, lnum + 5)
            
            -- Add context lines
            for i = start_line, end_line do
                if i == lnum then
                    -- Highlight the current line
                    table.insert(content, "> " .. lines[i])
                else
                    table.insert(content, "  " .. lines[i])
                end
            end
            
            -- Add the content to the preview buffer
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
            
            -- Syntax highlighting for YAML
            vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "yaml")
        end
    })
    
    -- Create finder options
    local opts = {
        prompt_title = "YAML Value Search",
        finder = require("telescope.finders").new_table {
            results = values,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.path .. ": " .. entry.value,
                    ordinal = entry.path .. " " .. entry.value,
                    lnum = entry.line,
                    text = entry.text,
                    path = entry.path,
                    value_text = entry.value
                }
            end
        },
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = previewer,
        attach_mappings = function(prompt_bufnr, map)
            local actions = require("telescope.actions")
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = require("telescope.actions.state").get_selected_entry()
                vim.api.nvim_win_set_cursor(0, {selection.lnum, 0})
            end)
            
            -- Add edit action
            M.add_edit_action(prompt_bufnr, map)
            
            return true
        end
    }
    
    -- Open telescope
    require("telescope.pickers").new(opts):find()
end

-- Search for YAML paths across multiple files
function M.search_paths_in_project()
    -- Check if telescope is available
    local has_telescope, telescope = pcall(require, "telescope.builtin")
    if not has_telescope then
        vim.notify("Telescope is required for yaml-jumper", vim.log.levels.ERROR)
        return
    end
    
    -- Find YAML files in the project
    local files = M.find_yaml_files()
    if #files == 0 then
        vim.notify("No YAML files found in the project", vim.log.levels.WARN)
        return
    end
    
    -- Build a list of all paths with their files
    local all_paths = {}
    
    -- Process each file
    for _, file_path in ipairs(files) do
        local file_content = {}
        
        -- Read the file content
        local file = io.open(file_path, "r")
        if file then
            for line in file:lines() do
                table.insert(file_content, line)
            end
            file:close()
            
            -- Extract paths from the file
            local paths = M.get_yaml_paths(file_content)
            
            -- Add file information to each path
            for _, path in ipairs(paths) do
                path.file_path = file_path
                path.file_name = vim.fn.fnamemodify(file_path, ":t")
                path.relative_path = vim.fn.fnamemodify(file_path, ":~:.")
                table.insert(all_paths, path)
            end
        end
    end
    
    -- Preview function for multi-file paths
    local previewer = require("telescope.previewers").new_buffer_previewer({
        title = "YAML Preview",
        define_preview = function(self, entry, status)
            -- Read the file for preview
            local content = {}
            local file = io.open(entry.filename, "r")
            if file then
                local line_num = 1
                local target_line = entry.lnum
                local content_lines = {}
                
                -- Read all lines
                for line in file:lines() do
                    content_lines[line_num] = line
                    line_num = line_num + 1
                end
                file:close()
                
                -- Add some context before and after the target line
                local start_line = math.max(1, target_line - 5)
                local end_line = math.min(#content_lines, target_line + 10)
                
                -- Add context to preview
                for i = start_line, end_line do
                    if i == target_line then
                        -- Highlight the current line
                        table.insert(content, "> " .. content_lines[i])
                    else
                        table.insert(content, "  " .. content_lines[i])
                    end
                end
            else
                table.insert(content, "Error: Could not read file")
            end
            
            -- Add the content to the preview buffer
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
            
            -- Apply syntax highlighting
            vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "yaml")
        end
    })
    
    -- Create finder options
    local opts = {
        prompt_title = "YAML Paths in Project",
        finder = require("telescope.finders").new_table {
            results = all_paths,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.relative_path .. ":" .. entry.path,
                    ordinal = entry.file_name .. " " .. entry.path,
                    filename = entry.file_path,
                    lnum = entry.line,
                    text = entry.text
                }
            end
        },
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = previewer,
        attach_mappings = function(prompt_bufnr, map)
            local actions = require("telescope.actions")
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = require("telescope.actions.state").get_selected_entry()
                -- Open the file if it's not the current buffer
                if vim.fn.expand("%:p") ~= selection.filename then
                    vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
                end
                vim.api.nvim_win_set_cursor(0, {selection.lnum, 0})
            end)
            return true
        end
    }
    
    -- Open telescope
    require("telescope.pickers").new(opts):find()
end

-- Search for YAML values across multiple files
function M.search_values_in_project()
    -- Check if telescope is available
    local has_telescope, telescope = pcall(require, "telescope.builtin")
    if not has_telescope then
        vim.notify("Telescope is required for yaml-jumper", vim.log.levels.ERROR)
        return
    end
    
    -- Find YAML files in the project
    local files = M.find_yaml_files()
    if #files == 0 then
        vim.notify("No YAML files found in the project", vim.log.levels.WARN)
        return
    end
    
    -- Build a list of all values with their files
    local all_values = {}
    
    -- Process each file
    for _, file_path in ipairs(files) do
        local file_content = {}
        
        -- Read the file content
        local file = io.open(file_path, "r")
        if file then
            for line in file:lines() do
                table.insert(file_content, line)
            end
            file:close()
            
            -- Extract values from the file
            local values = M.get_yaml_values(file_content)
            
            -- Add file information to each value
            for _, value in ipairs(values) do
                value.file_path = file_path
                value.file_name = vim.fn.fnamemodify(file_path, ":t")
                value.relative_path = vim.fn.fnamemodify(file_path, ":~:.")
                table.insert(all_values, value)
            end
        end
    end
    
    -- Preview function for multi-file values
    local previewer = require("telescope.previewers").new_buffer_previewer({
        title = "YAML Value Preview",
        define_preview = function(self, entry, status)
            -- Read the file for preview
            local content = {}
            local file = io.open(entry.filename, "r")
            if file then
                local line_num = 1
                local target_line = entry.lnum
                local content_lines = {}
                
                -- Read all lines
                for line in file:lines() do
                    content_lines[line_num] = line
                    line_num = line_num + 1
                end
                file:close()
                
                -- Add some context before and after the target line
                local start_line = math.max(1, target_line - 5)
                local end_line = math.min(#content_lines, target_line + 10)
                
                -- Add context to preview
                for i = start_line, end_line do
                    if i == target_line then
                        -- Highlight the current line
                        table.insert(content, "> " .. content_lines[i])
                    else
                        table.insert(content, "  " .. content_lines[i])
                    end
                end
            else
                table.insert(content, "Error: Could not read file")
            end
            
            -- Add the content to the preview buffer
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
            
            -- Apply syntax highlighting
            vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "yaml")
        end
    })
    
    -- Create finder options
    local opts = {
        prompt_title = "YAML Values in Project",
        finder = require("telescope.finders").new_table {
            results = all_values,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.relative_path .. ": " .. entry.path .. " = " .. entry.value,
                    ordinal = entry.file_name .. " " .. entry.path .. " " .. entry.value,
                    filename = entry.file_path,
                    lnum = entry.line,
                    text = entry.text,
                    value_text = entry.value
                }
            end
        },
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = previewer,
        attach_mappings = function(prompt_bufnr, map)
            local actions = require("telescope.actions")
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = require("telescope.actions.state").get_selected_entry()
                -- Open the file if it's not the current buffer
                if vim.fn.expand("%:p") ~= selection.filename then
                    vim.cmd("edit " .. vim.fn.fnameescape(selection.filename))
                end
                vim.api.nvim_win_set_cursor(0, {selection.lnum, 0})
            end)
            
            -- Add edit action
            M.add_edit_action(prompt_bufnr, map)
            
            return true
        end
    }
    
    -- Open telescope
    require("telescope.pickers").new(opts):find()
end

-- Setup function with configuration
function M.setup(opts)
    -- Merge user config with defaults
    if opts then
        for k, v in pairs(opts) do
            if type(v) == "table" and type(config[k]) == "table" then
                -- Merge nested tables
                for k2, v2 in pairs(v) do
                    config[k][k2] = v2
                end
            else
                config[k] = v
            end
        end
    end
    
    -- Set up highlight groups if enabled
    if config.highlights.enabled then
        vim.api.nvim_set_hl(0, 'YamlPathHighlight', config.highlights.path)
        vim.api.nvim_set_hl(0, 'YamlKeyHighlight', config.highlights.key)
    end
    
    -- Add commands for single file operations
    vim.api.nvim_create_user_command(
        "YamlJump",
        function() M.jump_to_path() end,
        { nargs = 0 }
    )
    
    vim.api.nvim_create_user_command(
        "YamlJumpKey",
        function() M.jump_to_key() end,
        { nargs = 0 }
    )
    
    vim.api.nvim_create_user_command(
        "YamlJumpValue",
        function() M.jump_to_value() end,
        { nargs = 0 }
    )
    
    -- Add commands for multi-file operations
    vim.api.nvim_create_user_command(
        "YamlJumpProject",
        function() M.search_paths_in_project() end,
        { nargs = 0 }
    )
    
    vim.api.nvim_create_user_command(
        "YamlJumpValueProject",
        function() M.search_values_in_project() end,
        { nargs = 0 }
    )
    
    -- Add command to clear the cache
    vim.api.nvim_create_user_command(
        "YamlJumpClearCache",
        function() utils.clear_cache() end,
        { nargs = 0 }
    )
    
    -- Add key mappings for single file operations
    local path_keymap = config.path_keymap or '<leader>yj'
    local key_keymap = config.key_keymap or '<leader>yk'
    local value_keymap = config.value_keymap or '<leader>yv'
    
    -- Add key mappings for multi-file operations
    local project_path_keymap = config.project_path_keymap or '<leader>yJ'
    local project_value_keymap = config.project_value_keymap or '<leader>yV'
    
    -- Set up key mappings
    vim.keymap.set('n', path_keymap, ':YamlJump<CR>', { silent = true, desc = 'Jump to YAML path' })
    vim.keymap.set('n', key_keymap, ':YamlJumpKey<CR>', { silent = true, desc = 'Jump to YAML key' })
    vim.keymap.set('n', value_keymap, ':YamlJumpValue<CR>', { silent = true, desc = 'Jump to YAML value' })
    vim.keymap.set('n', project_path_keymap, ':YamlJumpProject<CR>', { silent = true, desc = 'Search YAML paths in project' })
    vim.keymap.set('n', project_value_keymap, ':YamlJumpValueProject<CR>', { silent = true, desc = 'Search YAML values in project' })
    
    -- Set up autocommands to clear cache on file write
    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = {"*.yaml", "*.yml"},
        callback = function(event)
            utils.clear_cache(event.file)
        end,
    })
    
    return M
end

return M
