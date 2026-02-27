local config = require("yaml-jumper.config")

local M = {}

local entries = {}
local max_size = 100

function M.set_max_size(n)
    max_size = n
end

function M.add(type_name, value)
    if not value or value == "" then
        return
    end
    -- Prevent duplicate consecutive entries
    if #entries > 0 and entries[#entries].type == type_name and entries[#entries].value == value then
        return
    end
    entries[#entries + 1] = { type = type_name, value = value, timestamp = os.time() }
    if #entries > max_size then
        table.remove(entries, 1)
    end
end

function M.get_entries()
    return entries
end

function M.is_empty()
    return #entries == 0
end

return M
