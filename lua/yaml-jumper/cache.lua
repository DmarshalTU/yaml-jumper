local config = require("yaml-jumper.config")

local M = {
    paths = {},
    paths_time = {},
    values = {},
    values_time = {},
    lines = {},
    lines_time = {},
    yaml_docs = {},
    yaml_docs_time = {},
}

function M.get(store, key)
    if not config.cache_enabled or not key then
        return nil
    end
    local data = M[store]
    local times = M[store .. "_time"]
    if data and data[key] and times and (os.time() - (times[key] or 0)) < config.cache_ttl then
        return data[key]
    end
    return nil
end

function M.set(store, key, value)
    if not config.cache_enabled or not key then
        return
    end
    M[store] = M[store] or {}
    M[store .. "_time"] = M[store .. "_time"] or {}
    M[store][key] = value
    M[store .. "_time"][key] = os.time()
end

function M.clear(file_path)
    if file_path then
        for _, store in ipairs({ "paths", "values", "lines", "yaml_docs" }) do
            if M[store] then M[store][file_path] = nil end
            if M[store .. "_time"] then M[store .. "_time"][file_path] = nil end
        end
    else
        for _, store in ipairs({ "paths", "values", "lines", "yaml_docs" }) do
            M[store] = {}
            M[store .. "_time"] = {}
        end
    end
end

return M
