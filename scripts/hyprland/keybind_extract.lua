-- Really executes hyprland/keybinds.lua with a stub `hl` table so every
-- hl.bind() call gets resolved by Lua itself, including ones generated
-- inside for-loops (workspace numbers, arrow-key focus/move, ...) - no
-- regex re-implementation of Lua's evaluation semantics needed.
--
-- Only hl.* functions that are actually called eagerly (at bind-registration
-- time) need real stubs; anything only reachable from inside a bind's own
-- dispatcher function (fired later, on keypress) never runs here and needs
-- no stub at all.
--
-- Usage: lua5.4 keybind_extract.lua <lib-init.lua path> <variables.lua path> <hyprland-keybinds.lua path>
-- Prints one JSON object to stdout: {"ok":true,"binds":[...]} or {"ok":false,"error":"..."}

local function quoteLuaString(s)
    return string.format("%q", s)
end

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return n > 0
end

local toSource
toSource = function(v)
    local t = type(v)
    if v == nil then
        return "nil"
    elseif t == "boolean" or t == "number" then
        return tostring(v)
    elseif t == "string" then
        return quoteLuaString(v)
    elseif t == "table" then
        local parts = {}
        if isArray(v) then
            for _, item in ipairs(v) do
                parts[#parts + 1] = toSource(item)
            end
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                local keyStr
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    keyStr = k
                else
                    keyStr = "[" .. toSource(k) .. "]"
                end
                parts[#parts + 1] = keyStr .. " = " .. toSource(v[k])
            end
        end
        return "{ " .. table.concat(parts, ", ") .. " }"
    else
        return "nil"
    end
end

local function jsonString(s)
    local out = s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == '\\' then return '\\\\' end
        if c == '\n' then return '\\n' end
        if c == '\r' then return '\\r' end
        if c == '\t' then return '\\t' end
        return string.format('\\u%04x', string.byte(c))
    end)
    return '"' .. out .. '"'
end

local jsonValue
jsonValue = function(v)
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
        local parts = {}
        if isArray(v) then
            for _, item in ipairs(v) do
                parts[#parts + 1] = jsonValue(item)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                parts[#parts + 1] = jsonString(tostring(k)) .. ":" .. jsonValue(v[k])
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

local function isSimpleValue(v)
    local t = type(v)
    if v == nil or t == "boolean" or t == "number" or t == "string" then
        return true
    end
    if t == "table" then
        for _, item in pairs(v) do
            if not isSimpleValue(item) then return false end
        end
        return true
    end
    return false
end

-- ── hl stub ──────────────────────────────────────────────────────────────

local results = {}
local inSubmap = false

local function mkDispatcher(name)
    return function(args)
        return { __dispatcher = name, __args = args }
    end
end

local hl
hl = {
    env = function() end,
    config = function() end,
    get_config = function() return 0 end,
    exec_cmd = function() end,
    dispatch = function() end,
    get_current_submap = function() return "" end,
    dsp = {
        global = mkDispatcher("global"),
        exec_cmd = mkDispatcher("exec_cmd"),
        focus = mkDispatcher("focus"),
        layout = mkDispatcher("layout"),
        submap = mkDispatcher("submap"),
        window = {
            close = mkDispatcher("window.close"),
            drag = mkDispatcher("window.drag"),
            resize = mkDispatcher("window.resize"),
            float = mkDispatcher("window.float"),
            fullscreen = mkDispatcher("window.fullscreen"),
            fullscreen_state = mkDispatcher("window.fullscreen_state"),
            move = mkDispatcher("window.move"),
            pin = mkDispatcher("window.pin"),
        },
        workspace = {
            toggle_special = mkDispatcher("workspace.toggle_special"),
        },
    },
    define_submap = function(name, fn)
        local prev = inSubmap
        inSubmap = true
        local ok, err = pcall(fn)
        inSubmap = prev
        if not ok then
            io.stderr:write("warning: submap '" .. tostring(name) .. "' callback raised: " .. tostring(err) .. "\n")
        end
    end,
    bind = function(key, dispatcher, opts)
        local info = debug.getinfo(2, "Sl")
        local entry = {
            key = key,
            callLine = info and info.currentline or 0,
            inSubmap = inSubmap,
            opts = opts and toSource(opts) or nil,
        }
        if type(dispatcher) == "function" then
            local dinfo = debug.getinfo(dispatcher, "S")
            local upvalues = {}
            local unsupported = false
            local i = 1
            while true do
                local uname, uvalue = debug.getupvalue(dispatcher, i)
                if not uname then break end
                if uname ~= "_ENV" then
                    -- Upvalues that aren't plain literals (e.g. a reference to
                    -- another local helper function defined in this file) can't
                    -- be safely relocated into custom/keybinds.lua by copying
                    -- the closure's text alone - the referenced name wouldn't
                    -- exist there.
                    if not isSimpleValue(uvalue) then
                        unsupported = true
                    else
                        upvalues[uname] = toSource(uvalue)
                    end
                end
                i = i + 1
            end
            if unsupported then
                entry.dispatcherKind = "unsupported"
            else
                entry.dispatcherKind = "closure"
                entry.closureLine = dinfo.linedefined
                entry.upvalues = upvalues
            end
        elseif type(dispatcher) == "table" and dispatcher.__dispatcher then
            entry.dispatcherKind = "direct"
            local argSrc = dispatcher.__args ~= nil and toSource(dispatcher.__args) or ""
            entry.dispatcherSource = "hl.dsp." .. dispatcher.__dispatcher .. "(" .. argSrc .. ")"
        else
            entry.dispatcherKind = "unknown"
        end
        results[#results + 1] = entry
        return { unbind = function() end, remove = function() end, set_enabled = function() end }
    end,
    is_key_down = function() return false end,
    timer = function() end,
}
_G.hl = hl
_G.require = function() return true end

local libPath, varsPath, keybindsPath = arg[1], arg[2], arg[3]

local function runFile(path)
    local chunk, loadErr = loadfile(path)
    if not chunk then
        error("failed to load " .. path .. ": " .. tostring(loadErr))
    end
    local ok, runErr = pcall(chunk)
    if not ok then
        error("failed to run " .. path .. ": " .. tostring(runErr))
    end
end

local ok, err = pcall(function()
    runFile(libPath)
    runFile(varsPath)
    runFile(keybindsPath)
end)

if not ok then
    print('{"ok":false,"error":' .. jsonString(tostring(err)) .. '}')
    os.exit(0)
end

print('{"ok":true,"binds":' .. jsonValue(results) .. '}')
