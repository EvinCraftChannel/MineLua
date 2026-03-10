-- MineLua Config Loader (YAML subset)
local Config = {}

function Config.load(path)
    local defaults = {
        motd        = "MineLua Server",
        sub_motd    = "Powered by MineLua",
        max_players = 20,
        port        = 19132,
        host        = "0.0.0.0",
        game_mode   = "survival",
        difficulty  = "normal",
        view_distance        = 10,
        default_world        = "world",
        log_level            = "INFO",
        online_mode          = false,
        announce_player_join  = true,
        announce_player_leave = true,
        auto_save_interval   = 300,
        white_list           = false,
        enable_query         = true,
        enable_rcon          = false,
        compression_threshold = 256,
    }

    local f = io.open(path, "r")
    if not f then
        Config.save(path, defaults)
        return defaults
    end

    local cfg = {}
    for line in f:lines() do
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local k, v = line:match("^%s*([%w_%-]+)%s*:%s*(.-)%s*$")
            if k and v then
                v = v:match("^(.-)%s*#.*$") or v
                v = v:match('^"(.*)"$') or v:match("^'(.*)'$") or v
                if     v == "true"                then v = true
                elseif v == "false"               then v = false
                elseif v == "null" or v == "~"    then v = nil
                elseif tonumber(v)                then v = tonumber(v)
                end
                cfg[k] = v
            end
        end
    end
    f:close()

    for k, dv in pairs(defaults) do
        if cfg[k] == nil then cfg[k] = dv end
    end
    return cfg
end

function Config.save(path, cfg)
    local dir = path:match("(.+)/[^/]+$")
    if dir then os.execute("mkdir -p " .. dir) end
    local f = io.open(path, "w")
    if not f then return false end

    f:write("# MineLua Server Configuration\n\n")
    for k, v in pairs(cfg) do
        if type(v) == "string" then
            f:write(string.format('%s: "%s"\n', k, v))
        elseif v ~= nil then
            f:write(string.format('%s: %s\n', k, tostring(v)))
        end
    end
    f:close()
    return true
end

return Config
