local M = {}

-- Highlight group for the current path
vim.api.nvim_set_hl(0, 'YamlPathHighlight', { bg = '#2d2d2d', fg = '#ffffff' })

-- Parse a dot-notation path into a table of keys
local function parse_path(path)
    local keys = {}
    for key in path:gmatch("([^%.]+)") do
        table.insert(keys, key)
    end
    return keys
end

-- Find the line number where a specific YAML path exists
local function find_yaml_path(keys, lines)
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
            current_indent = current_indent - 2 -- Assuming 2-space indentation
        end

        -- Extract the key from the current line
        local key = line:match("^%s*([^:]+):")
        if key then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            table.insert(current_keys, key)
            current_indent = indent

            -- Check if we've found our path
            if #current_keys == #keys then
                local found = true
                for j, k in ipairs(keys) do
                    if current_keys[j] ~= k then
                        found = false
                        break
                    end
                end
                if found then
                    table.insert(matches, i)
                end
            end
        end

        ::continue::
    end

    return matches
end

-- Main function to jump to a YAML path
function M.jump_to_path()
    -- Clear any existing highlights
    vim.fn.clearmatches()
    
    -- Create a custom input prompt
    local input = ""
    local matches = {}
    
    -- Function to update search results
    local function update_search()
        -- Clear previous highlights
        vim.fn.clearmatches()
        
        -- Parse and find matches
        local keys = parse_path(input)
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        matches = find_yaml_path(keys, lines)
        
        -- Highlight all matches
        for _, line in ipairs(matches) do
            vim.fn.matchadd('YamlPathHighlight', '\\%' .. line .. 'l.*')
        end
        
        -- Jump to first match if there are any
        if #matches > 0 then
            vim.api.nvim_win_set_cursor(0, {matches[1], 0})
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
        
        -- Update search results without showing the input
        update_search()
    end
    
    -- Clear highlights when done
    vim.fn.clearmatches()
end

-- Setup function
function M.setup()
    vim.api.nvim_create_user_command(
        "YamlJump",
        function() M.jump_to_path() end,
        { nargs = 0 }
    )
    
    -- Add key mapping (default: <leader>yj)
    vim.keymap.set('n', '<leader>yj', ':YamlJump<CR>', { silent = true, desc = 'Jump to YAML path' })
end

return M
