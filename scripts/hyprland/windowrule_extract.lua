-- Really executes hyprland/rules.lua with a stub `hl` table so every
-- hl.window_rule() call gets resolved by Lua itself. Only hl.window_rule
-- needs a real stub (it records its argument table); every other hl.*
-- entry point used elsewhere in that file (workspace_rule, layer_rule, on,
-- dispatch, dsp, get_active_monitor, ...) is stubbed as a harmless no-op
-- since we only care about window_rule calls here.
--
-- Usage: lua5.4 windowrule_extract.lua <hyprland-rules.lua path>
-- Prints one JSON object to stdout: {"ok":true,"rules":[...]} or {"ok":false,"error":"..."}

local function jsonString(s)
    local out = { '"' }
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = s:byte(i)
        if c == '"' or c == '\\' then
            out[#out + 1] = "\\" .. c
        elseif c == "\n" then
            out[#out + 1] = "\\n"
        elseif c == "\t" then
            out[#out + 1] = "\\t"
        elseif b < 0x20 then
            out[#out + 1] = string.format("\\u%04x", b)
        else
            out[#out + 1] = c
        end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

local toJson
toJson = function(v)
    local t = type(v)
    if v == nil then
        return "null"
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "number" then
        return tostring(v)
    elseif t == "string" then
        return jsonString(v)
    elseif t == "table" then
        local isArray, n = true, 0
        for k in pairs(v) do
            n = n + 1
            if type(k) ~= "number" then isArray = false end
        end
        if isArray and n > 0 then
            local parts = {}
            for i = 1, n do parts[#parts + 1] = toJson(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = jsonString(tostring(k)) .. ":" .. toJson(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    else
        return "null"
    end
end

local recorded = {}

local function noop() return setmetatable({}, {__index = function() return noop end, __call = function() return nil end}) end

hl = setmetatable({
    window_rule = function(spec)
        local match = spec.match or {}
        local effects = {}
        for k, v in pairs(spec) do
            if k ~= "match" and k ~= "name" and k ~= "enabled" then
                effects[#effects + 1] = { key = k, value = v }
            end
        end
        recorded[#recorded + 1] = { match = match, effects = effects }
        return noop()
    end,
}, { __index = function() return noop end })

local rulesPath = arg[1]
if not rulesPath then
    io.write('{"ok":false,"error":"usage: windowrule_extract.lua <rules.lua path>"}')
    os.exit(1)
end

local chunk, err = loadfile(rulesPath)
if not chunk then
    io.write('{"ok":false,"error":' .. jsonString("failed to load: " .. tostring(err)) .. '}')
    os.exit(1)
end

local ok, runErr = pcall(chunk)
if not ok then
    io.write('{"ok":false,"error":' .. jsonString("failed to run: " .. tostring(runErr)) .. '}')
    os.exit(1)
end

io.write('{"ok":true,"rules":' .. toJson(recorded) .. '}')
