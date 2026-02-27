local M = {
    highlights = {
        enabled = true,
        path = { bg = "#404040", fg = "#ffffff", bold = true },
        key = { fg = "#ff9900", bg = "#333333", bold = true },
    },
    max_file_size = 1024 * 1024,
    max_preview_lines = 20,
    cache_enabled = true,
    cache_ttl = 30,
    depth_limit = 10,
    max_history_items = 20,
    use_smart_parser = true,
    debug_performance = false,
    picker_type = "telescope", -- "telescope", "fzf-lua", or "snacks"
}

function M.apply(opts)
    opts = opts or {}
    for k, v in pairs(opts) do
        M[k] = v
    end
end

return M
