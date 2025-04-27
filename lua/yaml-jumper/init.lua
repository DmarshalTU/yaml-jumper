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
                table.insert(matches, {
                    line = i,
                    key = key,
                    text = line:gsub("^%s+", ""),
                    path = key
                })
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
            end
        end

        ::continue::
    end

    return matches
end

-- Get all YAML paths from the current buffer
local function get_yaml_paths(lines)
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
            current_indent = current_indent - 2 -- Assuming 2-space indentation
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

    return paths
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
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    
    -- Get all paths
    local paths = get_yaml_paths(lines)
    
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
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    
    -- Get all keys
    local matches = find_keys_with_prefix("", lines)
    
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

-- Setup function
function M.setup(opts)
    opts = opts or {}
    
    -- Add command for dot notation paths
    vim.api.nvim_create_user_command(
        "YamlJump",
        function() M.jump_to_path() end,
        { nargs = 0 }
    )
    
    -- Add command for key search
    vim.api.nvim_create_user_command(
        "YamlJumpKey",
        function() M.jump_to_key() end,
        { nargs = 0 }
    )
    
    -- Add key mappings
    local path_keymap = opts.path_keymap or '<leader>yj'
    local key_keymap = opts.key_keymap or '<leader>yk'
    
    vim.keymap.set('n', path_keymap, ':YamlJump<CR>', { silent = true, desc = 'Jump to YAML path' })
    vim.keymap.set('n', key_keymap, ':YamlJumpKey<CR>', { silent = true, desc = 'Jump to YAML key' })
end

return M
