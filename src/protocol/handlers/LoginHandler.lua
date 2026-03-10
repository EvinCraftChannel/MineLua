-- MineLua Login Handler
-- Handles the initial login sequence for MCBE players

local Logger = require("utils.Logger")
local BitBuffer = require("utils.BitBuffer")
local json = require("utils.json")

local LoginHandler = {}
LoginHandler.__index = LoginHandler

function LoginHandler:handle(player, buf)
    local protocol = buf:readInt()
    
    -- Check protocol version support
    local protocol_map = require("protocol.ProtocolManager").PROTOCOLS
    local version_str = protocol_map[protocol]
    
    Logger.info(string.format("Login attempt from %s - Protocol: %d (%s)", 
        player.connection.ip, protocol, version_str or "unknown"))
    
    if not version_str then
        -- Too old (before 1.1.0)
        if protocol < 113 then
            self.server.protocol:sendPlayStatus(player,
                require("protocol.ProtocolManager").PLAY_STATUS.LOGIN_FAILED_CLIENT)
            player:kick("Your Minecraft version is too old. Minimum: 1.1.0")
            return
        end
        -- Protocol is newer than our table (future versions beyond 26.x)
        -- Accept gracefully — the game protocol is largely backward-compatible
        -- between minor versions. Log a warning so server admins know to update.
        if protocol > 950 then
            Logger.warn(string.format(
                "Client protocol %d is newer than our maximum (944). " ..
                "Accepting anyway; update MineLua if issues arise.", protocol))
        else
            Logger.warn(string.format(
                "Unknown protocol %d — likely a minor hotfix between known versions. Accepting.", protocol))
        end
        -- Derive a human-readable version estimate for the 26.x range
        if protocol >= 918 then
            local drop = math.floor((protocol - 918) / 6)
            version_str = string.format("26.%d (estimated)", drop)
        elseif protocol >= 766 then
            version_str = string.format("1.21.x (protocol %d)", protocol)
        else
            version_str = string.format("unknown (protocol %d)", protocol)
        end
    end
    
    player.protocol_version = protocol
    player.game_version = version_str
    
    -- Read JWT chain data
    local chain_len = buf:readInt()
    local chain_data_raw = buf:readBytes(chain_len)
    
    -- Parse the JWT chain
    local ok, chain_data = pcall(json.decode, chain_data_raw)
    if not ok or not chain_data then
        Logger.error("Failed to parse login chain data")
        player:kick("Invalid login data")
        return
    end
    
    -- Extract player identity from JWT
    local identity = self:parseIdentityData(chain_data)
    if not identity then
        Logger.error("Failed to extract identity from JWT")
        player:kick("Invalid identity data")
        return
    end
    
    player.xuid = identity.XUID or ""
    player.uuid = identity.identity or self:generateUUID()
    player.name = identity.displayName or "Player"
    player.device_id = identity.DeviceId or ""
    player.platform = identity.DeviceOS or 0
    player.client_random_id = identity.ClientRandomId or 0
    
    -- Read skin/client data
    local skin_len = buf:readInt()
    local skin_data_raw = buf:readBytes(skin_len)
    
    local skin_ok, skin_data = pcall(json.decode, skin_data_raw)
    if skin_ok and skin_data then
        player.skin = self:parseSkinData(skin_data)
    end
    
    Logger.info(string.format("Player '%s' logging in (XUID: %s)", player.name, player.xuid))
    
    -- Check if server is full
    local server = self.server or player.server
    if server.players:count() >= server.max_players then
        server.protocol:sendPlayStatus(player,
            require("protocol.ProtocolManager").PLAY_STATUS.LOGIN_FAILED_SERVER_FULL)
        player:kick("Server is full!")
        return
    end
    
    -- Check ban list
    if server:isBanned(player.name) then
        server.protocol:sendDisconnect(player, "You are banned from this server!")
        return
    end
    
    -- Fire pre-login event
    local event_result = server.events:fire("PlayerPreLogin", {
        player = player,
        name = player.name,
        xuid = player.xuid,
        cancel = false
    })
    
    if event_result and event_result.cancel then
        player:kick(event_result.reason or "Login denied by plugin")
        return
    end
    
    -- Send login success (no encryption for simplicity)
    server.protocol:sendPlayStatus(player,
        require("protocol.ProtocolManager").PLAY_STATUS.LOGIN_SUCCESS)
    
    -- Send resource pack info (empty - no resource packs by default)
    self:sendResourcePackInfo(player, server)
end

function LoginHandler:parseIdentityData(chain_data)
    if not chain_data.chain then return nil end
    
    for _, chain_link in ipairs(chain_data.chain) do
        -- Decode JWT payload (base64url decode middle part)
        local parts = {}
        for part in chain_link:gmatch("[^%.]+") do
            table.insert(parts, part)
        end
        
        if #parts >= 2 then
            local payload = self:base64Decode(parts[2])
            local ok, data = pcall(require("utils.json").decode, payload)
            if ok and data and data.extraData then
                return data.extraData
            end
        end
    end
    
    -- Fallback for offline mode
    return {
        XUID = "",
        identity = self:generateUUID(),
        displayName = "Player"
    }
end

function LoginHandler:parseSkinData(skin_data)
    return {
        skin_id = skin_data.SkinId or "",
        skin_data = skin_data.SkinData or "",
        skin_color = skin_data.SkinColor or "#0000000",
        arm_size = skin_data.ArmSize or "wide",
        cape_id = skin_data.CapeId or "",
        cape_data = skin_data.CapeData or "",
        geometry = skin_data.SkinGeometryData or "",
        premium = skin_data.PremiumSkin or false,
        persona = skin_data.PersonaSkin or false,
    }
end

function LoginHandler:sendResourcePackInfo(player, server)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    
    buf:writeBool(false) -- must accept
    buf:writeBool(false) -- has scripts
    buf:writeBool(false) -- force server packs
    buf:writeLShort(0) -- behavior pack count
    buf:writeLShort(0) -- resource pack count
    
    server.protocol:sendPacket(player, PID.RESOURCE_PACKS_INFO, buf)
end

function LoginHandler:base64Decode(s)
    -- Standard base64url decode
    s = s:gsub("-", "+"):gsub("_", "/")
    local padding = (4 - #s % 4) % 4
    s = s .. string.rep("=", padding)
    
    local result = {}
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for i = 1, #chars do
        lookup[chars:sub(i, i)] = i - 1
    end
    
    for i = 1, #s, 4 do
        local b0 = lookup[s:sub(i, i)] or 0
        local b1 = lookup[s:sub(i+1, i+1)] or 0
        local b2 = lookup[s:sub(i+2, i+2)] or 0
        local b3 = lookup[s:sub(i+3, i+3)] or 0
        
        table.insert(result, string.char((b0 << 2) | (b1 >> 4)))
        if s:sub(i+2, i+2) ~= "=" then
            table.insert(result, string.char(((b1 & 0xF) << 4) | (b2 >> 2)))
        end
        if s:sub(i+3, i+3) ~= "=" then
            table.insert(result, string.char(((b2 & 0x3) << 6) | b3))
        end
    end
    
    return table.concat(result)
end

function LoginHandler:generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return template:gsub("[xy]", function(c)
        local v = c == "x" and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end)
end

return LoginHandler
