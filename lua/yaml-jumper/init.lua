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
    -- Clear previous messages first
    vim.cmd("echo ''")
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

-- Get a single key from the user
local function get_key()
    local key = vim.fn.getchar()
    
    -- Return character code for special keys or character for printable keys
    if type(key) == "number" then
        if key >= 32 and key <= 126 then  -- Printable ASCII
            return {type = "char", value = vim.fn.nr2char(key)}
        elseif key == 13 then -- Enter
            return {type = "enter"}
        elseif key == 27 then -- Escape
            return {type = "escape"}
        elseif key == 8 or key == 127 then -- Backspace/Delete
            return {type = "backspace"}
        else
            return {type = "special", code = key}
        end
    else
        return {type = "string", value = key}
    end
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
                -- Only update status, don't show a new message for each keystroke
                show_status(string.format("YAML Jumper: '%s' (%d matches)", input, #key_matches))
            else
                show_status(string.format("YAML Jumper: '%s' (no matches)", input))
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
                -- Only update status, don't show a new message for each keystroke
                show_status(string.format("YAML Jumper: '%s' (%d matches)", input, #matches))
            else
                show_status(string.format("YAML Jumper: '%s' (no matches)", input))
            end
        end
    end
    
    -- Create the initial buffer
    ui_elements = create_mini_buffer(input)
    update_search()
    
    -- Start the input loop
    while true do
        -- Get keyboard input
        local key = get_key()
        
        -- Process the key
        if key.type == "enter" then
            break
        elseif key.type == "escape" then
            input = ""
            break
        elseif key.type == "backspace" then
            if #input > 0 then
                input = input:sub(1, -2)
                -- Do not show extra status messages for backspace
            end
        elseif key.type == "char" then
            input = input .. key.value
        end
        
        -- Update UI and search results
        update_search()
    end
    
    -- Clean up
    if ui_elements then
        vim.api.nvim_win_close(ui_elements.winid, true)
        vim.api.nvim_buf_delete(ui_elements.bufnr, {force = true})
    end
    
    -- Show final message
    if #input > 0 then
        show_status("YAML Jumper: Jumped to '" .. input .. "'")
    else
        show_status("")  -- Clear status
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
