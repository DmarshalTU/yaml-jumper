-- yaml-jumper.init
-- Efficient YAML navigation and search for Neovim
-- Author: DmarshalTU
-- License: MIT

local M = {}

-- Module-level cache for performance
local cache = {
    paths = {},
    values = {},
    history = {
        paths = {},
        values = {}
    }
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
    depth_limit = 10, -- Max directory scan depth
    max_history_items = 20, -- Max number of items to keep in history
    use_smart_parser = true, -- Use the smart YAML parser when available
    debug_performance = false, -- Enable performance logging
    picker_type = "telescope", -- or "snacks"
    picker_config = {
        snacks = {
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
            format = function(item)
                local display = {}
                table.insert(display, { item.path, "Keyword" })
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
            end,
            values = function(entry)
                if not entry or not entry.value then return {} end
                local item = entry.value
                
                local value = item.value_text
                if not value then
                    local _, val = item.text:match("^%s*[^:]+:%s*(.+)$")
                    if val then
                        value = val:gsub("^%s*(.-)%s*$", "%1")
                    end
                end
                
                local path_parts = vim.split(item.path, ".", { plain = true })
                local parent_path = table.concat(path_parts, ".", 1, #path_parts - 1)
                
                local formatted_value = {}
                if parent_path ~= "" then
                    table.insert(formatted_value, parent_path .. ":")
                end
                table.insert(formatted_value, "  " .. path_parts[#path_parts] .. ": " .. (value or ""))
                
                if value and value ~= "" then
                    return formatted_value
                end
                return {}
            end
        }
    }
}

-- History storage for YAML jumps
local history = {}
local max_history_size = 100

-- Helper functions
local utils = {}

-- Performance profiling utilities
local profiler = {}

-- Start timing an operation
function profiler.start(name)
    if not config.debug_performance then
        return function() end
    end
    
    local start_time = vim.loop.hrtime()
    return function()
        local end_time = vim.loop.hrtime()
        local duration = (end_time - start_time) / 1000000 -- convert to ms
        vim.notify(string.format("[yaml-jumper] %s took %.2f ms", name, duration), vim.log.levels.DEBUG)
        return duration
    end
end

-- Log message with timestamp
function profiler.log(msg)
    if not config.debug_performance then
        return
    end
    
    vim.notify("[yaml-jumper] " .. msg, vim.log.levels.DEBUG)
end

-- Check for optional dependencies
local has_lua_yaml, yaml = pcall(require, "lyaml")

-- Smart YAML parser module
local smart_parser = {}

-- Parse YAML content using smart parser
function smart_parser.parse_content(content)
    if has_lua_yaml then
        local ok, parsed = pcall(yaml.load, content)
        if ok and parsed then
            return parsed
        else
            -- Log parsing error but don't show to user to avoid disruption
            vim.schedule(function()
                vim.diagnostic.show(vim.diagnostic.severity.HINT, 0, {
                    {
                        lnum = 0,
                        col = 0,
                        message = "YAML parser: " .. (parsed or "unknown error")
                    }
                }, {})
            end)
        end
    end
    return nil
end

-- Cache for parsed YAML documents to avoid repeated parsing
local yaml_cache = {}
local yaml_cache_time = {}

-- Get cached or freshly parsed YAML data
function smart_parser.get_parsed_yaml(content, file_path)
    -- Check if we have a valid cached version
    if config.cache_enabled and file_path and yaml_cache[file_path] and
       (os.time() - (yaml_cache_time[file_path] or 0) < config.cache_ttl) then
        return yaml_cache[file_path]
    end
    
    -- Parse the content
    local parsed = smart_parser.parse_content(content)
    
    -- Cache the result if parsing succeeded
    if parsed and config.cache_enabled and file_path then
        yaml_cache[file_path] = parsed
        yaml_cache_time[file_path] = os.time()
    end
    
    return parsed
end

-- Clear the YAML parser cache
function smart_parser.clear_cache(file_path)
    if file_path then
        yaml_cache[file_path] = nil
        yaml_cache_time[file_path] = nil
    else
        yaml_cache = {}
        yaml_cache_time = {}
    end
end

-- Extract paths from parsed YAML data recursively
function smart_parser.extract_paths(data, current_path, paths_result)
    current_path = current_path or ""
    paths_result = paths_result or {}
    
    if type(data) ~= "table" then
        return paths_result
    end
    
    -- Handle both array and dictionary types
    local is_array = vim.tbl_islist(data)
    
    if is_array then
        -- Handle array items
        for i, value in ipairs(data) do
            local item_path = current_path ~= "" and (current_path .. "." .. i) or tostring(i)
            
            if type(value) == "table" then
                -- Add the array index path
                table.insert(paths_result, {
                    path = item_path,
                    value = "Array Item " .. i,
                    isArray = true,
                    arrayIndex = i
                })
                -- Recursively add nested paths
                smart_parser.extract_paths(value, item_path, paths_result)
            else
                -- Add leaf array item
                table.insert(paths_result, {
                    path = item_path,
                    value = tostring(value),
                    isArray = true,
                    arrayIndex = i
                })
            end
        end
    else
        -- Handle dictionary items
        for key, value in pairs(data) do
            local item_path = current_path ~= "" and (current_path .. "." .. key) or key
            
            if type(value) == "table" then
                -- Add the key path
                table.insert(paths_result, {
                    path = item_path,
                    value = "Object",
                    isArray = false
                })
                -- Recursively add nested paths
                smart_parser.extract_paths(value, item_path, paths_result)
            else
                -- Add leaf item
                table.insert(paths_result, {
                    path = item_path,
                    value = tostring(value),
                    isArray = false
                })
            end
        end
    end
    
    return paths_result
end

-- Extract hierarchy info from line
function smart_parser.get_line_info(line)
    -- Skip empty lines and comments
    if line:match("^%s*$") or line:match("^%s*#") then
        return nil
    end
    
    local indent = line:match("^%s*"):len()
    local key = line:match("^%s*([^:]+):")
    local value = line:match(":%s*(.+)$")
    
    if key then
        key = key:gsub("^%s*(.-)%s*$", "%1")
        
        -- Check if this is an array item
        local is_array_item = key:match("^%-%s*(.*)$")
        if is_array_item then
            -- This is an array item
            if is_array_item ~= "" then
                -- This is a named item in an array
                key = is_array_item:gsub("^%s*(.-)%s*$", "%1")
                return {
                    indent = indent,
                    key = key,
                    value = value,
                    is_array_item = true
                }
            else
                -- This is an unnamed array item
                return {
                    indent = indent,
                    is_array_item = true,
                    value = value,
                }
            end
        else
            -- This is a regular key
            return {
                indent = indent,
                key = key,
                value = value
            }
        end
    end
    
    return nil
end

-- Clear cache for a file or all files
function utils.clear_cache(file_path)
    if file_path then
        cache.paths[file_path] = nil
        cache.values[file_path] = nil
        smart_parser.clear_cache(file_path)
    else
        cache.paths = {}
        cache.values = {}
        smart_parser.clear_cache()
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
    local stop_timer = profiler.start("get_yaml_paths")
    
    -- Use cached paths if available and cache is enabled
    if config.cache_enabled and file_path and cache.paths[file_path] and 
       (os.time() - (cache.paths_time or {})[file_path] or 0) < config.cache_ttl then
        profiler.log("Using cached paths for " .. file_path)
        stop_timer()
        return cache.paths[file_path]
    end
    
    local paths = {}
    
    -- Try to use smart parser if enabled
    if config.use_smart_parser and has_lua_yaml then
        profiler.log("Using smart parser")
        local smart_timer = profiler.start("smart_parse")
        
        -- Join lines into a single string for parsing
        local content = table.concat(lines, "\n")
        
        -- Get parsed YAML data (from cache if available)
        local parsed_data = smart_parser.get_parsed_yaml(content, file_path)
        
        if parsed_data then
            -- Extract paths from parsed data
            local extraction_timer = profiler.start("extract_paths")
            local smart_paths = smart_parser.extract_paths(parsed_data)
            extraction_timer()
            
            -- Map smart paths to line numbers as best we can
            local mapping_timer = profiler.start("map_paths")
            for i, line in ipairs(lines) do
                local info = smart_parser.get_line_info(line)
                if info and info.key then
                    for _, path_info in ipairs(smart_paths) do
                        -- Check if this line contains the key for this path
                        local path_parts = vim.split(path_info.path, ".", { plain = true })
                        local last_part = path_parts[#path_parts]
                        
                        if last_part == info.key then
                            table.insert(paths, {
                                line = i,
                                key = info.key,
                                text = line:gsub("^%s+", ""),
                                path = path_info.path,
                                value = path_info.value,
                                isArray = path_info.isArray or false
                            })
                            break
                        end
                    end
                end
            end
            mapping_timer()
            
            if #paths > 0 then
                profiler.log("Smart parsing found " .. #paths .. " paths")
                -- Cache and return smart parsed results
                if config.cache_enabled and file_path then
                    cache.paths = cache.paths or {}
                    cache.paths_time = cache.paths_time or {}
                    cache.paths[file_path] = paths
                    cache.paths_time[file_path] = os.time()
                end
                
                smart_timer()
                stop_timer()
                return paths
            end
            -- If smart parsing yielded no results, fall back to traditional method
            profiler.log("Smart parsing found no paths, falling back")
        end
        smart_timer()
    end
    
    -- Traditional parsing method with array support
    profiler.log("Using traditional parser")
    local trad_timer = profiler.start("traditional_parse")
    
    local current_indent = 0
    local current_keys = {}
    local array_indices = {}

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

        -- Check if this is an array item
        local is_array_item = line:match("^%s*%-")
        if is_array_item then
            -- Get the current array path
            local array_path = #current_keys > 0 and table.concat(current_keys, ".") or ""
            
            -- Initialize or increment array index
            array_indices[array_path] = (array_indices[array_path] or 0) + 1
            local index = array_indices[array_path]
            
            -- Extract array item key if it exists (e.g., "- name: value")
            local item_key = line:match("^%s*%-%s*([^:]+):")
            local array_item_path
            
            if item_key then
                item_key = item_key:gsub("^%s*(.-)%s*$", "%1")
                if array_path ~= "" then
                    array_item_path = array_path .. "." .. index .. "." .. item_key
                else
                    array_item_path = index .. "." .. item_key
                end
            else
                -- Simple array item without a key
                if array_path ~= "" then
                    array_item_path = array_path .. "." .. index
                else
                    array_item_path = tostring(index)
                end
                item_key = "[" .. index .. "]"
            end
            
            -- Add the array item path only once
            table.insert(paths, {
                line = i,
                key = item_key,
                text = line:gsub("^%s+", ""),
                path = array_item_path,
                isArray = true,
                arrayIndex = index
            })
        else
            -- Extract the key from the current line (regular key, not array item)
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
        end

        ::continue::
    end
    
    profiler.log("Traditional parsing found " .. #paths .. " paths")
    trad_timer()
    
    -- Cache the result if caching is enabled
    if config.cache_enabled and file_path then
        cache.paths = cache.paths or {}
        cache.paths_time = cache.paths_time or {}
        cache.paths[file_path] = paths
        cache.paths_time[file_path] = os.time()
    end

    stop_timer()
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
    local seen_paths = {} -- Track seen paths to avoid duplicates

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
        if key then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            
            -- Create the path
            table.insert(current_keys, key)
            current_indent = indent
            local path = table.concat(current_keys, ".")
            
            -- Only add if we haven't seen this path before
            if not seen_paths[path] then
                seen_paths[path] = true
                
                -- If there's a value, add it to our list
                if value and value ~= "" then
                    value = value:gsub("^%s*(.-)%s*$", "%1")
                    table.insert(values, {
                        line = i,
                        key = key,
                        path = path,
                        value = value,
                        text = line:gsub("^%s+", "")
                    })
                end
            end
            
            -- If there's no value on this line, it might be a parent node
            if not value or value == "" then
                -- Keep the key in current_keys for nested paths
            else
                -- Remove the key since we've captured its value
                table.remove(current_keys)
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

-- Add a path to history
function utils.add_to_history(path, history_type)
    if not path or path == "" then
        return
    end
    
    -- Initialize if needed
    cache.history = cache.history or { paths = {}, values = {} }
    
    -- Get the right history list
    local history = cache.history[history_type] or {}
    
    -- Remove if already exists (to avoid duplicates)
    for i, item in ipairs(history) do
        if item == path then
            table.remove(history, i)
            break
        end
    end
    
    -- Add to the beginning
    table.insert(history, 1, path)
    
    -- Limit size
    if #history > config.max_history_items then
        history[#history] = nil
    end
    
    -- Save back
    cache.history[history_type] = history

    -- Also add to global history for the dedicated history picker
    add_to_global_history({
        type = history_type,
        value = path,
        timestamp = os.time()
    })
end

-- Add an entry to the unified global history
function add_to_global_history(entry)
    -- Prevent duplicate consecutive entries
    if #history > 0 and 
       history[#history].type == entry.type and 
       history[#history].value == entry.value then
        return
    end
    
    -- Add to history
    table.insert(history, entry)
    
    -- Trim history if it exceeds max size
    if #history > max_history_size then
        table.remove(history, 1)
    end
end

-- Get path history
function utils.get_history(history_type)
    cache.history = cache.history or { paths = {}, values = {} }
    return cache.history[history_type] or {}
end

-- Jump to a YAML path using telescope
function M.jump_to_path()
    -- Get lines of current buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = utils.get_file_lines()
    local filename = vim.api.nvim_buf_get_name(bufnr)

    -- Get all paths
    local paths = M.get_yaml_paths(lines)

    -- Add history items to the results
    local history_items = utils.get_history("paths")
    local has_history = #history_items > 0

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

    -- Create picker options
    local picker_opts = {
        prompt_title = has_history and "YAML Path (Recent First)" or "YAML Path",
        results = vim.tbl_map(function(entry)
            return {
                filename = filename,
                lnum = entry.line,
                text = entry.text,
                path = entry.path,
            }
        end, paths),
        entry_maker = function(entry)
            local display = entry.path
            local is_history = false
            for _, h in ipairs(history_items) do
                if h == entry.path then
                    is_history = true
                    display = "⭐ " .. display
                    break
                end
            end
            return {
                display = display,
                ordinal = (is_history and "0" or "1") .. entry.path,
                filename = entry.filename,
                lnum = entry.lnum,
                text = entry.text,
                path = entry.path,
                is_history = is_history,
            }
        end,
        previewer = previewer,
        on_select = function(selection)
            pcall(vim.api.nvim_win_set_cursor, 0, {selection.lnum, 0})
            utils.add_to_history(selection.path, "paths")
        end,
        on_attach = function(prompt_bufnr, map)
            M.add_edit_action(prompt_bufnr, map)
        end
    }

    local picker = require("yaml-jumper.picker").create_picker(picker_opts, config)
    picker:find()
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
    -- Get lines of current buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local lines = utils.get_file_lines()
    
    -- Get all values
    local values = M.get_yaml_values(lines)
    
    -- Get history
    local history_items = utils.get_history("values")
    local has_history = #history_items > 0
    
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
    
    -- Create picker options
    local picker_opts = {
        prompt_title = has_history and "YAML Value Search (Recent First)" or "YAML Value Search",
        results = values,
        entry_maker = function(entry)
            local path_value = entry.path .. ": " .. entry.value
            local is_history = false
            for _, h in ipairs(history_items) do
                if h == path_value then
                    is_history = true
                    path_value = "⭐ " .. path_value
                    break
                end
            end
            local filename = vim.api.nvim_buf_get_name(0)
            local lnum = entry.line
            local text = entry.text or (lnum and vim.api.nvim_buf_get_lines(0, lnum-1, lnum, false)[1]) or ""
            return {
                value = {
                    path = entry.path,
                    text = text,
                    lnum = lnum,
                    line = lnum,
                    filename = filename,
                    buf = vim.api.nvim_get_current_buf(),
                    value_text = entry.value,
                },
                display = path_value,
                ordinal = (is_history and "0" or "1") .. entry.path .. " " .. entry.value,
                lnum = lnum,
                line = lnum,
                text = text,
                path = entry.path,
                value_text = entry.value,
                is_history = is_history,
                filename = filename,
            }
        end,
        previewer = previewer,
        on_select = function(selection)
            pcall(vim.api.nvim_win_set_cursor, 0, {selection.lnum, 0})
            -- Add to history
            utils.add_to_history(selection.path .. ": " .. selection.value_text, "values")
        end,
        on_attach = function(prompt_bufnr, map)
            -- Add edit action
            M.add_edit_action(prompt_bufnr, map)
        end
    }
    
    -- Create and show the picker
    local picker = require("yaml-jumper.picker").create_picker(picker_opts, config)
    picker:find()
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

-- Jump to history of recent YAML paths
function M.jump_to_history()
    -- Check if telescope is available
    local has_telescope, telescope = pcall(require, "telescope.builtin")
    if not has_telescope then
        vim.notify("Telescope is required for yaml-jumper history", vim.log.levels.ERROR)
        return
    end
    
    if #history == 0 then
        vim.notify("No YAML jump history available", vim.log.levels.INFO)
        return
    end

    local items = {}
    for i = #history, 1, -1 do
        local entry = history[i]
        local display = ""
        local time_str = os.date("%H:%M:%S", entry.timestamp)
        
        if entry.type == "paths" then
            display = "[" .. time_str .. "] Path: " .. entry.value
        elseif entry.type == "values" then
            display = "[" .. time_str .. "] Value: " .. entry.value
        end
        
        table.insert(items, {
            display = display,
            entry = entry,
            index = i
        })
    end
    
    -- Create finder options
    local opts = {
        prompt_title = "YAML Jump History",
        finder = require("telescope.finders").new_table {
            results = items,
            entry_maker = function(item)
                return {
                    value = item,
                    display = item.display,
                    ordinal = item.display
                }
            end
        },
        sorter = require("telescope.config").values.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
            local actions = require("telescope.actions")
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = require("telescope.actions.state").get_selected_entry()
                
                -- Jump to appropriate place based on type
                if selection.value.entry.type == "paths" then
                    M.jump_to_specific_path(selection.value.entry.value)
                elseif selection.value.entry.type == "values" then
                    M.jump_to_specific_value(selection.value.entry.value)
                end
            end)
            
            return true
        end
    }
    
    -- Open telescope
    require("telescope.pickers").new(opts):find()
end

-- Helper function to jump to a specific path
function M.jump_to_specific_path(path_string)
    -- Get buffer lines
    local lines = utils.get_file_lines()
    
    -- Find the path
    local keys = utils.parse_path(path_string)
    local matches = M.find_yaml_path(keys, lines)
    
    if #matches > 0 then
        vim.api.nvim_win_set_cursor(0, {matches[1].line, 0})
        vim.notify("Jumped to: " .. path_string, vim.log.levels.INFO)
    else
        vim.notify("Path not found: " .. path_string, vim.log.levels.WARN)
    end
end

-- Helper function to jump to a specific value
function M.jump_to_specific_value(value_string)
    -- Extract path and value
    local path, value = value_string:match("^(.+): (.+)$")
    
    if not path or not value then
        vim.notify("Invalid value format: " .. value_string, vim.log.levels.ERROR)
        return
    end
    
    -- Get buffer lines
    local lines = utils.get_file_lines()
    
    -- First try to find by path
    local keys = utils.parse_path(path)
    local path_matches = M.find_yaml_path(keys, lines)
    
    if #path_matches > 0 then
        vim.api.nvim_win_set_cursor(0, {path_matches[1].line, 0})
        vim.notify("Jumped to: " .. value_string, vim.log.levels.INFO)
    else
        -- If not found by path, search values
        local values = M.get_yaml_values(lines)
        local found = false
        
        for _, entry in ipairs(values) do
            if entry.path == path and entry.value == value then
                vim.api.nvim_win_set_cursor(0, {entry.line, 0})
                vim.notify("Jumped to: " .. value_string, vim.log.levels.INFO)
                found = true
                break
            end
        end
        
        if not found then
            vim.notify("Value not found: " .. value_string, vim.log.levels.WARN)
        end
    end
end

-- Setup function to configure yaml-jumper
function M.setup(opts)
    -- Merge user options with defaults
    opts = opts or {}
    
    -- Apply configuration
    for k, v in pairs(opts) do
        config[k] = v
    end

    -- Check for required dependencies based on picker type
    if config.picker_type == "telescope" then
        local has_telescope = pcall(require, "telescope.builtin")
        if not has_telescope then
            vim.notify("Telescope is required for yaml-jumper", vim.log.levels.ERROR)
            return
        end
    elseif config.picker_type == "snacks" then
        local has_snacks = pcall(require, "snacks")
        if not has_snacks then
            vim.notify("Snacks.nvim is required for yaml-jumper", vim.log.levels.ERROR)
            return
        end
    else
        vim.notify("Invalid picker_type: " .. config.picker_type, vim.log.levels.ERROR)
        return
    end

    -- Set max history size if provided
    if opts.max_history_size then
        max_history_size = opts.max_history_size
    end
    
    -- Check for smart parser availability
    if config.use_smart_parser and not has_lua_yaml then
        vim.notify("lyaml library not found. Smart YAML parsing disabled. Run 'luarocks install lyaml' to enable.", vim.log.levels.WARN)
    end
    
    -- Log configuration if debug is enabled
    if config.debug_performance then
        vim.notify("[yaml-jumper] Debug performance logging enabled", vim.log.levels.INFO)
        profiler.log("Configuration: " .. vim.inspect(vim.tbl_filter(function(k, v) 
            return type(v) ~= "table" 
        end, config)))
    end
    
    -- Set up key mappings if they exist
    local mappings = {
        {"path_keymap", "yp", function() M.jump_to_path() end},
        {"key_keymap", "yk", function() M.jump_to_key() end},
        {"value_keymap", "yv", function() M.jump_to_value() end},
        {"project_path_keymap", "yJ", function() M.search_paths_in_project() end},
        {"project_value_keymap", "yV", function() M.search_values_in_project() end},
        {"history_keymap", "yh", function() M.jump_to_history() end}
    }
    
    -- Register mappings
    for _, mapping in ipairs(mappings) do
        local key = mapping[1]
        local default = mapping[2]
        local fn = mapping[3]
        
        local keymap = nil
        if opts[key] == nil then
            keymap = "<leader>" .. default
        elseif opts[key] == false then
            keymap = nil
        else
            keymap = opts[key]
        end
        
        if keymap then
            vim.keymap.set("n", keymap, fn, {noremap = true, silent = true})
        end
    end
    
    -- Register commands
    vim.api.nvim_create_user_command("YamlJump", function() M.jump_to_path() end, {})
    vim.api.nvim_create_user_command("YamlJumpKey", function() M.jump_to_key() end, {})
    vim.api.nvim_create_user_command("YamlJumpValue", function() M.jump_to_value() end, {})
    vim.api.nvim_create_user_command("YamlJumpProject", function() M.search_paths_in_project() end, {})
    vim.api.nvim_create_user_command("YamlJumpValueProject", function() M.search_values_in_project() end, {})
    vim.api.nvim_create_user_command("YamlJumpClearCache", function() utils.clear_cache() end, {})
    vim.api.nvim_create_user_command("YamlJumpHistory", function() M.jump_to_history() end, {})
    
    -- Set up autocommands for cache clearing
    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = {"*.yaml", "*.yml"},
        callback = function()
            local file_path = vim.api.nvim_buf_get_name(0)
            if file_path and file_path ~= "" then
                utils.clear_cache(file_path)
            end
        end
    })
end

return M
