local config = require("yaml-jumper.config")
local cache = require("yaml-jumper.cache")
local utils = require("yaml-jumper.utils")

local M = {}

local has_lua_yaml, yaml = pcall(require, "lyaml")

M.has_smart_parser = has_lua_yaml

-- Parse raw YAML string via lyaml
local function smart_parse(content, file_path)
    if not has_lua_yaml then
        return nil
    end
    local cached = cache.get("yaml_docs", file_path or "buffer")
    if cached then
        return cached
    end
    local ok, parsed = pcall(yaml.load, content)
    if ok and parsed then
        cache.set("yaml_docs", file_path or "buffer", parsed)
        return parsed
    end
    return nil
end

-- Recursively extract paths from parsed YAML data
local function extract_paths_from_data(data, prefix, result)
    prefix = prefix or ""
    result = result or {}
    if type(data) ~= "table" then
        return result
    end
    local is_list = (vim.islist or vim.tbl_islist)(data)
    if is_list then
        for i, v in ipairs(data) do
            local p = prefix ~= "" and (prefix .. "." .. i) or tostring(i)
            if type(v) == "table" then
                result[#result + 1] = { path = p, value = "Array Item " .. i, isArray = true, arrayIndex = i }
                extract_paths_from_data(v, p, result)
            else
                result[#result + 1] = { path = p, value = tostring(v), isArray = true, arrayIndex = i }
            end
        end
    else
        for key, v in pairs(data) do
            local p = prefix ~= "" and (prefix .. "." .. key) or key
            if type(v) == "table" then
                result[#result + 1] = { path = p, value = "Object", isArray = false }
                extract_paths_from_data(v, p, result)
            else
                result[#result + 1] = { path = p, value = tostring(v), isArray = false }
            end
        end
    end
    return result
end

local function get_line_info(line)
    if line:match("^%s*$") or line:match("^%s*#") then
        return nil
    end
    local indent = #line:match("^%s*")
    local key = line:match("^%s*([^:]+):")
    local value = line:match(":%s*(.+)$")
    if not key then
        return nil
    end
    key = key:gsub("^%s*(.-)%s*$", "%1")
    local arr = key:match("^%-%s*(.*)$")
    if arr then
        if arr ~= "" then
            return { indent = indent, key = arr:gsub("^%s*(.-)%s*$", "%1"), value = value, is_array_item = true }
        end
        return { indent = indent, is_array_item = true, value = value }
    end
    return { indent = indent, key = key, value = value }
end

-- Unwind indent stack: pops keys when indentation decreases
local function unwind_indent(current_keys, current_indent, indent)
    while #current_keys > 0 and indent <= current_indent do
        table.remove(current_keys)
        current_indent = #current_keys > 0 and (current_indent - 2) or 0
    end
    return current_indent
end

-- Get all YAML paths from lines
function M.get_yaml_paths(lines, file_path)
    local cached = cache.get("paths", file_path)
    if cached then
        return cached
    end

    local paths = {}

    -- Try smart parser first
    if config.use_smart_parser and has_lua_yaml then
        local content = table.concat(lines, "\n")
        local parsed = smart_parse(content, file_path)
        if parsed then
            local smart_paths = extract_paths_from_data(parsed)
            for i, line in ipairs(lines) do
                local info = get_line_info(line)
                if info and info.key then
                    for _, pi in ipairs(smart_paths) do
                        local parts = vim.split(pi.path, ".", { plain = true })
                        if parts[#parts] == info.key then
                            paths[#paths + 1] = {
                                line = i, key = info.key, text = line:gsub("^%s+", ""),
                                path = pi.path, value = pi.value, isArray = pi.isArray or false,
                            }
                            break
                        end
                    end
                end
            end
            if #paths > 0 then
                cache.set("paths", file_path, paths)
                return paths
            end
        end
    end

    -- Traditional parser with array support
    local current_indent = 0
    local current_keys = {}
    local array_indices = {}

    for i, line in ipairs(lines) do
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end
        local indent = #line:match("^%s*")
        current_indent = unwind_indent(current_keys, current_indent, indent)

        if line:match("^%s*%-") then
            local arr_path = #current_keys > 0 and table.concat(current_keys, ".") or ""
            array_indices[arr_path] = (array_indices[arr_path] or 0) + 1
            local idx = array_indices[arr_path]
            local item_key = line:match("^%s*%-%s*([^:]+):")
            local full_path
            if item_key then
                item_key = item_key:gsub("^%s*(.-)%s*$", "%1")
                full_path = (arr_path ~= "" and arr_path .. "." or "") .. idx .. "." .. item_key
            else
                full_path = (arr_path ~= "" and arr_path .. "." or "") .. idx
                item_key = "[" .. idx .. "]"
            end
            paths[#paths + 1] = {
                line = i, key = item_key, text = line:gsub("^%s+", ""),
                path = full_path, isArray = true, arrayIndex = idx,
            }
        else
            local key = line:match("^%s*([^:]+):")
            if key then
                key = key:gsub("^%s*(.-)%s*$", "%1")
                current_keys[#current_keys + 1] = key
                current_indent = indent
                paths[#paths + 1] = {
                    line = i, key = key, text = line:gsub("^%s+", ""),
                    path = table.concat(current_keys, "."),
                }
            end
        end
        ::continue::
    end

    cache.set("paths", file_path, paths)
    return paths
end

-- Get all YAML key-value pairs from lines
function M.get_yaml_values(lines, file_path)
    local cached = cache.get("values", file_path)
    if cached then
        return cached
    end

    local values = {}
    local current_indent = 0
    local current_keys = {}
    local seen = {}

    for i, line in ipairs(lines) do
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end
        local indent = #line:match("^%s*")
        current_indent = unwind_indent(current_keys, current_indent, indent)

        local key, val = line:match("^%s*([^:]+):%s*(.*)$")
        if key then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            current_keys[#current_keys + 1] = key
            current_indent = indent
            local path = table.concat(current_keys, ".")
            if not seen[path] then
                seen[path] = true
                if val and val ~= "" then
                    val = val:gsub("^%s*(.-)%s*$", "%1")
                    values[#values + 1] = {
                        line = i, key = key, path = path,
                        value = val, text = line:gsub("^%s+", ""),
                    }
                end
            end
            if val and val ~= "" then
                table.remove(current_keys)
            end
        end
        ::continue::
    end

    cache.set("values", file_path, values)
    return values
end

-- Find keys starting with a prefix
function M.find_keys_with_prefix(prefix, lines, options)
    options = options or {}
    local matches = {}
    for i, line in ipairs(lines) do
        if not (line:match("^%s*$") or line:match("^%s*#")) then
            local key = line:match("^%s*([^:]+):")
            if key then
                key = key:gsub("^%s*(.-)%s*$", "%1")
                if prefix == "" or key:lower():find("^" .. prefix:lower()) then
                    matches[#matches + 1] = { line = i, key = key, text = line:gsub("^%s+", ""), path = key }
                    if options.limit and #matches >= options.limit then
                        break
                    end
                end
            end
        end
    end
    return matches
end

-- Find the line number for a specific YAML path
function M.find_yaml_path(keys, lines, options)
    options = options or {}
    local current_indent = 0
    local current_keys = {}
    local matches = {}
    for i, line in ipairs(lines) do
        if line:match("^%s*$") or line:match("^%s*#") then
            goto continue
        end
        local indent = #line:match("^%s*")
        current_indent = unwind_indent(current_keys, current_indent, indent)
        local key = line:match("^%s*([^:]+):")
        if key then
            key = key:gsub("^%s*(.-)%s*$", "%1")
            current_keys[#current_keys + 1] = key
            current_indent = indent
            local found = true
            for j, k in ipairs(keys) do
                if j > #current_keys or current_keys[j] ~= k then
                    found = false
                    break
                end
            end
            if found and #current_keys >= #keys then
                matches[#matches + 1] = {
                    line = i, key = current_keys[#keys],
                    text = line:gsub("^%s+", ""),
                    path = table.concat(current_keys, ".", 1, #keys),
                }
                if options.limit and #matches >= options.limit then
                    break
                end
            end
        end
        ::continue::
    end
    return matches
end

-- Find YAML files in project (built-in vim.fs, no external deps)
function M.find_yaml_files()
    local cwd = vim.fn.getcwd()
    return vim.fs.find(function(name)
        return name:match("%.ya?ml$") ~= nil
    end, { path = cwd, upward = false, limit = math.huge, type = "file" }) or {}
end

return M
