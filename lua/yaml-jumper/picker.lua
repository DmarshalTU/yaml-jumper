local M = {}

function M.create_picker(opts, config)
    if config.picker_type == "snacks" then
        return M.create_snacks_picker(opts, config)
    elseif config.picker_type == "fzf-lua" then
        return M.create_fzf_picker(opts, config)
    else
        return M.create_telescope_picker(opts, config)
    end
end

-- Telescope backend
function M.create_telescope_picker(opts)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    return pickers.new(opts, {
        prompt_title = opts.prompt_title,
        finder = finders.new_table({
            results = opts.results,
            entry_maker = opts.entry_maker,
        }),
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = opts.previewer,
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local sel = action_state.get_selected_entry()
                if sel and opts.on_select then
                    opts.on_select(sel)
                end
            end)
            if opts.on_attach then
                opts.on_attach(prompt_bufnr, map)
            end
            return true
        end,
    })
end

-- fzf-lua backend
function M.create_fzf_picker(opts)
    return {
        find = function()
            local fzf = require("fzf-lua")
            local entries = {}
            local entry_map = {}

            for _, item in ipairs(opts.results) do
                local entry = opts.entry_maker(item)
                local display = entry.display or ""
                entries[#entries + 1] = display
                entry_map[display] = entry
            end

            fzf.fzf_exec(entries, {
                prompt = (opts.prompt_title or "YAML") .. "> ",
                previewer = false,
                fzf_opts = { ["--layout"] = "reverse" },
                actions = {
                    ["default"] = function(selected)
                        if not selected or #selected == 0 then
                            return
                        end
                        local entry = entry_map[selected[1]]
                        if entry and opts.on_select then
                            opts.on_select(entry)
                        end
                    end,
                },
            })
        end,
    }
end

-- Snacks.nvim backend
function M.create_snacks_picker(opts)
    local current_buf = vim.api.nvim_get_current_buf()
    local current_file = vim.api.nvim_buf_get_name(current_buf)
    local extract = require("yaml-jumper.utils").extract_value_from_line

    local entries = {}
    for _, item in ipairs(opts.results) do
        entries[#entries + 1] = {
            value = item,
            text = item.text,
            lnum = item.lnum or item.line,
            col = 0,
            buf = item.buf or current_buf,
            file = item.file or current_file,
            filename = item.filename or current_file,
            path = item.path,
            value_text = item.value_text or extract(item.text),
        }
    end

    local picker = require("snacks").picker({
        items = entries,
        prompt = "YAML Jump: ",
        layout = { width = 0.8, height = 0.8, cycle = true, preset = "default" },
        jump = { jumplist = true, close = true, match = false, reuse_win = true },
        matcher = { fuzzy = true, smartcase = true, ignorecase = true },
        sort = { fields = { "score:desc", "#text", "idx" } },
        win = {
            input = {
                keys = {
                    ["<CR>"] = { "confirm", mode = { "n", "i" } },
                    ["<Esc>"] = "cancel",
                    ["<C-e>"] = { "edit", mode = { "n", "i" } },
                },
            },
        },
        on_select = function(selection)
            if not selection or not selection.value then
                return
            end
            local item = selection.value
            local lnum = item.line or item.lnum
            if lnum then
                pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
            end
            if opts.on_select then
                opts.on_select(selection)
            end
        end,
        format = function(item)
            local display = { { item.path or "", "Keyword" } }
            local val = item.value_text or extract(item.text)
            if val and val ~= "" then
                display[#display + 1] = { " = ", "Normal" }
                display[#display + 1] = { val, "String" }
            end
            return display
        end,
        preview = function(entry)
            if not entry or not entry.value then
                return
            end
            local item = entry.value
            local fname = item.filename
            local lnum = tonumber(item.lnum) or 1
            local lines
            if fname and fname ~= "" and vim.fn.filereadable(fname) == 1 then
                lines = vim.fn.readfile(fname)
            else
                lines = vim.api.nvim_buf_get_lines(item.buf or 0, 0, -1, false)
            end
            if not lines or #lines == 0 then
                return { text = "(empty)", ft = "yaml" }
            end
            lnum = math.max(1, math.min(lnum, #lines))
            local s = math.max(1, lnum - 5)
            local e = math.min(#lines, lnum + 5)
            local ctx = {}
            for i = s, e do
                ctx[#ctx + 1] = (i == lnum and "> " or "  ") .. (lines[i] or "")
            end
            return { text = table.concat(ctx, "\n"), ft = "yaml" }
        end,
    })

    return picker
end

return M
