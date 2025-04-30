local M = {}

-- Create a picker based on the configured type
function M.create_picker(opts)
    if config.picker_type == "telescope" then
        return M.create_telescope_picker(opts)
    else
        return M.create_snacks_picker(opts)
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
    local snacks = require("snacks")
    
    return snacks.picker.new({
        prompt = opts.prompt_title,
        finder = function()
            local entries = {}
            for _, item in ipairs(opts.results) do
                local entry = opts.entry_maker(item)
                table.insert(entries, {
                    value = entry.value,
                    display = entry.display,
                    ordinal = entry.ordinal,
                    filename = entry.filename,
                    lnum = entry.lnum,
                    text = entry.text,
                    path = entry.path,
                    value_text = entry.value_text
                })
            end
            return entries
        end,
        previewer = function(entry)
            if opts.previewer then
                local preview_bufnr = vim.api.nvim_create_buf(false, true)
                opts.previewer.define_preview({ state = { bufnr = preview_bufnr } }, entry, {})
                return preview_bufnr
            end
        end,
        on_select = function(selection)
            if opts.on_select then
                opts.on_select(selection)
            end
        end,
        attach_mappings = function(map)
            if opts.on_attach then
                opts.on_attach(nil, map)
            end
        end
    })
end

return M 