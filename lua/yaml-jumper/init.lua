-- yaml-jumper
-- Fast YAML navigation for Neovim
-- Author: DmarshalTU
-- License: MIT

local config = require("yaml-jumper.config")
local navigation = require("yaml-jumper.navigation")
local project = require("yaml-jumper.project")
local history = require("yaml-jumper.history")
local cache = require("yaml-jumper.cache")
local parser = require("yaml-jumper.parser")

local M = {}

-- Re-export public API
M.jump_to_path = navigation.jump_to_path
M.jump_to_key = navigation.jump_to_key
M.jump_to_value = navigation.jump_to_value
M.jump_to_history = function()
    if history.is_empty() then
        vim.notify("No YAML jump history available", vim.log.levels.INFO)
        return
    end
    local raw = history.get_entries()
    local items = {}
    for i = #raw, 1, -1 do
        local e = raw[i]
        local ts = os.date("%H:%M:%S", e.timestamp)
        local label = e.type == "paths" and ("Path: " .. e.value) or ("Value: " .. e.value)
        items[#items + 1] = { display = "[" .. ts .. "] " .. label, entry = e, index = i }
    end
    require("yaml-jumper.picker").create_picker({
        prompt_title = "YAML Jump History",
        results = items,
        entry_maker = function(item)
            return { value = item, display = item.display, ordinal = item.display }
        end,
        on_select = function(sel)
            local e = sel.value.entry
            if e.type == "paths" then
                navigation.jump_to_specific_path(e.value)
            elseif e.type == "values" then
                navigation.jump_to_specific_value(e.value)
            end
        end,
    }, config):find()
end
M.search_paths_in_project = project.search_paths_in_project
M.search_values_in_project = project.search_values_in_project
M.edit_yaml_value = navigation.edit_yaml_value

-- Expose internals for advanced use
M.get_yaml_paths = parser.get_yaml_paths
M.get_yaml_values = parser.get_yaml_values
M.find_yaml_files = parser.find_yaml_files
M.find_keys_with_prefix = parser.find_keys_with_prefix
M.find_yaml_path = parser.find_yaml_path
M.clear_cache = cache.clear

function M.setup(opts)
    opts = opts or {}
    config.apply(opts)

    local valid = { telescope = true, ["fzf-lua"] = true, snacks = true }
    if not valid[config.picker_type] then
        vim.notify("yaml-jumper: invalid picker_type '" .. tostring(config.picker_type) .. "'", vim.log.levels.ERROR)
        return
    end

    if opts.max_history_size then
        history.set_max_size(opts.max_history_size)
    end

    if config.use_smart_parser and not parser.has_smart_parser then
        vim.notify("lyaml not found. Smart YAML parsing disabled. Install: luarocks install lyaml", vim.log.levels.WARN)
    end

    -- Keymaps
    local maps = {
        { "path_keymap", "yp", M.jump_to_path, "Jump to YAML path" },
        { "key_keymap", "yk", M.jump_to_key, "Jump to YAML key" },
        { "value_keymap", "yv", M.jump_to_value, "Jump to YAML value" },
        { "project_path_keymap", "yJ", M.search_paths_in_project, "Search YAML paths in project" },
        { "project_value_keymap", "yV", M.search_values_in_project, "Search YAML values in project" },
        { "history_keymap", "yh", M.jump_to_history, "Jump to YAML history" },
    }
    for _, m in ipairs(maps) do
        local keymap
        if opts[m[1]] == nil then
            keymap = "<leader>" .. m[2]
        elseif opts[m[1]] == false then
            keymap = nil
        else
            keymap = opts[m[1]]
        end
        if keymap then
            vim.keymap.set("n", keymap, m[3], { noremap = true, silent = true, desc = m[4] })
        end
    end

    -- Commands
    vim.api.nvim_create_user_command("YamlJump", M.jump_to_path, {})
    vim.api.nvim_create_user_command("YamlJumpKey", M.jump_to_key, {})
    vim.api.nvim_create_user_command("YamlJumpValue", M.jump_to_value, {})
    vim.api.nvim_create_user_command("YamlJumpProject", M.search_paths_in_project, {})
    vim.api.nvim_create_user_command("YamlJumpValueProject", M.search_values_in_project, {})
    vim.api.nvim_create_user_command("YamlJumpHistory", M.jump_to_history, {})
    vim.api.nvim_create_user_command("YamlJumpClearCache", cache.clear, {})

    -- Auto-clear cache on YAML save
    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = { "*.yaml", "*.yml" },
        callback = function()
            local fp = vim.api.nvim_buf_get_name(0)
            if fp ~= "" then
                cache.clear(fp)
            end
        end,
    })
end

M._config = config
return M
