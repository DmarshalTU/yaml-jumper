local M = {}

-- Highlight groups with more prominent colors
vim.api.nvim_set_hl(0, 'YamlPathHighlight', { bg = '#404040', fg = '#ffffff', bold = true })
vim.api.nvim_set_hl(0, 'YamlKeyHighlight', { fg = '#ff9900', bg = '#333333', bold = true })

-- Parse a dot-notation path into a table of keys
local function parse_path(path)
    local keys = {}
    for key in path:gmatch("([^%.]+)") do
        table.insert(keys, key)
    end
    return keys
end

-- Find keys that start with a prefix
local function find_keys_with_prefix(prefix, lines)
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
                table.insert(matches, {line = i, key = key})
            end
        end
        
        ::continue::
    end
    
    return matches
end

-- Find the line number where a specific YAML path exists
local function find_yaml_path(keys, lines)
    local current_indent = 0
    local current_keys = {}
    local matches = {}
    local key_positions = {}

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
            current_indent = current_indent - 2 -- Assuming 2-space indentation
        end

        -- Extract the key from the current line
        local key = line:match("^%s*([^:]+):")
        if key then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            -- Store key position for highlighting
            local key_start = line:find(key, 1, true)
            
            table.insert(current_keys, key)
            current_indent = indent

            -- Check if we've found our path (partial or complete)
            local found = true
            local highlight_keys = {}
            
            for j = 1, math.min(#current_keys, #keys) do
                if current_keys[j] ~= keys[j] then
                    found = false
                    break
                end
                table.insert(highlight_keys, {key = keys[j], line = i, col_start = key_start})
            end
            
            if found then
                if #current_keys >= #keys then
                    table.insert(matches, {line = i, key_positions = highlight_keys})
                end
            end
        end

        ::continue::
    end

    return matches
end

-- Highlight matches for a given input
local function highlight_matches(input, lines)
    -- Clear previous highlights
    vim.fn.clearmatches()
    
    -- If input is empty or doesn't contain dots, show keys with prefix
    if input == "" or not input:find("%.") then
        local key_matches = find_keys_with_prefix(input, lines)
        
        -- Highlight and jump to first match
        if #key_matches > 0 then
            for _, match in ipairs(key_matches) do
                vim.fn.matchadd('YamlKeyHighlight', '\\%' .. match.line .. 'l\\s*' .. match.key)
            end
            
            vim.api.nvim_win_set_cursor(0, {key_matches[1].line, 0})
            return #key_matches, true
        else
            return 0, false
        end
    else
        -- Parse and find matches for dot notation path
        local keys = parse_path(input)
        local matches = find_yaml_path(keys, lines)
        
        -- Highlight all matches
        for _, match in ipairs(matches) do
            -- Highlight the line
            vim.fn.matchadd('YamlPathHighlight', '\\%' .. match.line .. 'l.*')
            
            -- Highlight each key in the path
            for _, key_pos in ipairs(match.key_positions) do
                vim.fn.matchadd('YamlKeyHighlight', '\\%' .. key_pos.line .. 'l\\%' .. key_pos.col_start .. 'c' .. key_pos.key)
            end
        end
        
        -- Jump to first match if there are any
        if #matches > 0 then
            vim.api.nvim_win_set_cursor(0, {matches[1].line, 0})
            return #matches, true
        else
            return 0, false
        end
    end
end

-- Main function to jump to a YAML path
function M.jump_to_path()
    -- Get lines of current buffer
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    
    -- Clear any existing highlights
    vim.fn.clearmatches()
    
    -- Custom completion function that shows matches as you type
    local function path_completion(arglead, cmdline, cursorpos)
        local match_count, has_matches = highlight_matches(arglead, lines)
        return {} -- Return empty list since we're not actually completing
    end
    
    -- Use Neovim's built-in input function with custom completion
    local input = vim.fn.input({
        prompt = "YAML Path: ",
        completion = path_completion,
        cancelreturn = "",
    })
    
    if input ~= "" then
        -- Do final highlight and jump
        local match_count, has_matches = highlight_matches(input, lines)
        
        -- Show completion message
        if has_matches then
            vim.api.nvim_echo({{string.format("Jumped to YAML path: %s (%d matches)", input, match_count), "Normal"}}, false, {})
        else
            vim.api.nvim_echo({{string.format("No matches found for: %s", input), "WarningMsg"}}, false, {})
        end
        
        -- Keep the highlights for a short time
        vim.defer_fn(function()
            vim.fn.clearmatches()
        end, 3000)
    else
        -- Clear highlights if cancelled
        vim.fn.clearmatches()
    end
end

-- Setup function
function M.setup(opts)
    opts = opts or {}
    
    -- Create highlight groups
    vim.api.nvim_create_user_command(
        "YamlJump",
        function() M.jump_to_path() end,
        { nargs = 0 }
    )
    
    -- Add key mapping (default: <leader>yj)
    local keymap = opts.keymap or '<leader>yj'
    vim.keymap.set('n', keymap, ':YamlJump<CR>', { silent = true, desc = 'Jump to YAML path' })
end

return M
