local M = {}

-- Highlight groups with more prominent colors
vim.api.nvim_set_hl(0, 'YamlPathHighlight', { bg = '#404040', fg = '#ffffff', bold = true })
vim.api.nvim_set_hl(0, 'YamlKeyHighlight', { fg = '#ff9900', bg = '#333333', bold = true })
vim.api.nvim_set_hl(0, 'YamlInputPrompt', { fg = '#ffffff', bg = '#0066cc', bold = true })

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

-- Display status message at bottom of screen
local function show_status(message)
    vim.api.nvim_echo({{message, "YamlInputPrompt"}}, false, {})
end

-- Create a mini buffer for displaying the current search
local function create_mini_buffer(input)
    local bufnr = vim.api.nvim_create_buf(false, true)
    local width = #input + 25  -- Make the window wider
    local height = 1
    
    local ui = vim.api.nvim_list_uis()[1]
    local win_width = ui.width
    local win_height = ui.height
    
    local win_opts = {
        relative = 'editor',
        width = width,
        height = height,
        row = win_height - 5,  -- Position higher on screen
        col = math.floor((win_width - width) / 2),
        style = 'minimal',
        border = 'rounded',
        title = "YAML Jumper",
        title_pos = "center",
    }
    
    local winid = vim.api.nvim_open_win(bufnr, false, win_opts)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {"Path: " .. input})
    
    -- Apply highlight to the floating window
    vim.api.nvim_win_set_option(winid, 'winhighlight', 'Normal:YamlInputPrompt')
    
    return {bufnr = bufnr, winid = winid}
end

-- Main function to jump to a YAML path
function M.jump_to_path()
    -- Clear any existing highlights
    vim.fn.clearmatches()
    
    -- Create a custom input prompt
    local input = ""
    local matches = {}
    local ui_elements = nil
    
    -- Show initial message
    show_status("YAML Jumper: Type to search (Esc to cancel, Enter to confirm)")
    
    -- Function to update search results
    local function update_search()
        -- Clear previous highlights
        vim.fn.clearmatches()
        
        if ui_elements then
            -- Update the input display
            vim.api.nvim_buf_set_lines(ui_elements.bufnr, 0, -1, false, {"Path: " .. input})
        else
            -- Create the UI elements on first iteration
            ui_elements = create_mini_buffer(input)
        end
        
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        
        -- If input is empty or doesn't contain dots, show keys with prefix
        if input == "" or not input:find("%.") then
            local key_matches = find_keys_with_prefix(input, lines)
            
            -- Highlight and jump to first match
            if #key_matches > 0 then
                for _, match in ipairs(key_matches) do
                    vim.fn.matchadd('YamlKeyHighlight', '\\%' .. match.line .. 'l\\s*' .. match.key)
                end
                
                vim.api.nvim_win_set_cursor(0, {key_matches[1].line, 0})
                show_status("Found " .. #key_matches .. " matches for '" .. input .. "' (press Enter to confirm)")
            else
                show_status("No matches found for '" .. input .. "'")
            end
        else
            -- Parse and find matches for dot notation path
            local keys = parse_path(input)
            matches = find_yaml_path(keys, lines)
            
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
                show_status("Found " .. #matches .. " matches for '" .. input .. "' (press Enter to confirm)")
            else
                show_status("No matches found for '" .. input .. "'")
            end
        end
    end
    
    -- Start the input loop
    while true do
        local char = vim.fn.getchar()
        if char == 13 then -- Enter
            break
        elseif char == 27 then -- Escape
            input = ""
            break
        elseif char == 8 or char == 127 then -- Backspace
            input = input:sub(1, -2)
        else
            input = input .. vim.fn.nr2char(char)
        end
        
        -- Update search results
        update_search()
    end
    
    -- Clean up
    if ui_elements then
        vim.api.nvim_win_close(ui_elements.winid, true)
        vim.api.nvim_buf_delete(ui_elements.bufnr, {force = true})
    end
    
    -- Show a message before clearing highlights
    if #input > 0 then
        show_status("Jumped to: " .. input)
    end
    
    -- Leave the highlights on for a short time so the user can see them
    vim.defer_fn(function()
        vim.fn.clearmatches()
        vim.cmd("echo ''") -- Clear status line after a delay
    end, 2000)
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
