-- MineLua JSON (pure-Lua encoder/decoder)
-- Handles the full JSON spec needed for MCBE login & plugins

local json = {}

---------------------------------------------------------------------------
-- Decode
---------------------------------------------------------------------------
local function skip_ws(s, i)
    while i <= #s do
        local c = s:sub(i,i)
        if c == ' ' or c == '\t' or c == '\n' or c == '\r' then i = i+1
        else break end
    end
    return i
end

local function parse_string(s, i)
    i = i + 1  -- skip opening "
    local parts = {}
    while i <= #s do
        local c = s:sub(i,i)
        if c == '"' then return table.concat(parts), i+1 end
        if c == '\\' then
            i = i+1
            local e = s:sub(i,i)
            local esc = {['"']='"', ['\']='\', ['/']='/', b='', f='', n='
', r='', t='	'}
            if esc[e] then parts[#parts+1] = esc[e]
            elseif e == 'u' then
                local hex = s:sub(i+1,i+4)
                parts[#parts+1] = utf8_char(tonumber(hex,16) or 0)
                i = i+4
            end
        else
            parts[#parts+1] = c
        end
        i = i+1
    end
    error("Unterminated string")
end

local function utf8_char(cp)
    if cp < 0x80 then return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0+(cp>>6), 0x80+(cp&0x3F))
    else
        return string.char(0xE0+(cp>>12), 0x80+((cp>>6)&0x3F), 0x80+(cp&0x3F))
    end
end

local parse_value
local function parse_array(s, i)
    i = i+1
    local arr = {}
    i = skip_ws(s,i)
    if s:sub(i,i) == ']' then return arr, i+1 end
    while true do
        local v; v,i = parse_value(s,i)
        arr[#arr+1] = v
        i = skip_ws(s,i)
        local c = s:sub(i,i)
        if c == ']' then return arr, i+1
        elseif c == ',' then i = i+1; i = skip_ws(s,i)
        else error("Expected , or ] in array at "..i) end
    end
end

local function parse_object(s, i)
    i = i+1
    local obj = {}
    i = skip_ws(s,i)
    if s:sub(i,i) == '}' then return obj, i+1 end
    while true do
        i = skip_ws(s,i)
        if s:sub(i,i) ~= '"' then error("Expected key at "..i) end
        local k; k,i = parse_string(s,i)
        i = skip_ws(s,i)
        if s:sub(i,i) ~= ':' then error("Expected : at "..i) end
        i = skip_ws(s, i+1)
        local v; v,i = parse_value(s,i)
        obj[k] = v
        i = skip_ws(s,i)
        local c = s:sub(i,i)
        if c == '}' then return obj, i+1
        elseif c == ',' then i = i+1
        else error("Expected , or } in object at "..i) end
    end
end

parse_value = function(s, i)
    i = skip_ws(s,i)
    local c = s:sub(i,i)
    if c == '"' then return parse_string(s,i)
    elseif c == '[' then return parse_array(s,i)
    elseif c == '{' then return parse_object(s,i)
    elseif c == 't' then return true, i+4
    elseif c == 'f' then return false, i+5
    elseif c == 'n' then return nil, i+4
    else
        local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
        if num then return tonumber(num), i+#num end
        error("Unexpected character '"..c.."' at position "..i)
    end
end

function json.decode(s)
    if type(s) ~= "string" or #s == 0 then return nil end
    local ok, val = pcall(parse_value, s, 1)
    if ok then return val end
    return nil, val
end

---------------------------------------------------------------------------
-- Encode
---------------------------------------------------------------------------
local encode

local function encode_string(s)
    return '"' .. s:gsub('[\\"]', '\\%0')
                    :gsub('\n','\\n'):gsub('\r','\\r')
                    :gsub('\t','\\t') .. '"'
end

local function encode_array(t)
    local parts = {}
    for _, v in ipairs(t) do parts[#parts+1] = encode(v) end
    return '[' .. table.concat(parts, ',') .. ']'
end

local function encode_object(t)
    local parts = {}
    for k, v in pairs(t) do
        if type(k) == 'string' then
            parts[#parts+1] = encode_string(k) .. ':' .. encode(v)
        end
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

encode = function(v)
    local t = type(v)
    if t == 'nil'     then return 'null'
    elseif t == 'boolean' then return tostring(v)
    elseif t == 'number'  then
        if v ~= v then return 'null' end  -- NaN
        return string.format(v == math.floor(v) and "%d" or "%.10g", v)
    elseif t == 'string' then return encode_string(v)
    elseif t == 'table' then
        -- Detect array vs object
        local max_i, cnt = 0, 0
        for k in pairs(v) do
            cnt = cnt + 1
            if type(k) == 'number' and k == math.floor(k) and k > 0 then
                max_i = math.max(max_i, k)
            end
        end
        if max_i == cnt and cnt > 0 then return encode_array(v) end
        return encode_object(v)
    else
        return '"[' .. t .. ']"'
    end
end

function json.encode(v)
    return encode(v)
end

return json
