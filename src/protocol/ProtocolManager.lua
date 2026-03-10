-- MineLua Protocol Manager
-- Handles MCBE game packet encoding/decoding
-- Supports protocol versions from 1.0 to 26.x (2026 new versioning)

local BitBuffer = require("utils.BitBuffer")
local Logger = require("utils.Logger")
local zlib = require("zlib") -- lua-zlib

local ProtocolManager = {}
ProtocolManager.__index = ProtocolManager

-- MCBE Protocol versions mapping
ProtocolManager.PROTOCOLS = {
    -- Older versions
    [113] = "1.1.0",
    [137] = "1.2.0",
    [141] = "1.2.5",
    [150] = "1.2.6",
    [160] = "1.2.7",
    [201] = "1.3.0",
    [211] = "1.4.0",
    [223] = "1.5.0",
    [237] = "1.6.0",
    [240] = "1.6.1",
    [261] = "1.7.0",
    [274] = "1.8.0",
    [282] = "1.9.0",
    [291] = "1.10.0",
    [313] = "1.11.0",
    [332] = "1.12.0",
    [340] = "1.13.0",
    [354] = "1.14.0",
    [361] = "1.14.60",
    [388] = "1.16.0",
    [389] = "1.16.20",
    [390] = "1.16.40",
    [407] = "1.16.100",
    [408] = "1.16.200",
    [419] = "1.16.210",
    [422] = "1.16.220",
    [428] = "1.17.0",
    [431] = "1.17.10",
    [440] = "1.17.30",
    [448] = "1.17.40",
    [465] = "1.18.0",
    [471] = "1.18.10",
    [475] = "1.18.30",
    [486] = "1.19.0",
    [503] = "1.19.10",
    [527] = "1.19.20",
    [534] = "1.19.21",
    [544] = "1.19.30",
    [545] = "1.19.31",
    [554] = "1.19.40",
    [557] = "1.19.41",
    [560] = "1.19.50",
    [567] = "1.19.60",
    [568] = "1.19.62",
    [575] = "1.19.70",
    [582] = "1.19.80",
    [589] = "1.20.0",
    [594] = "1.20.10",
    [618] = "1.20.30",
    [622] = "1.20.40",
    [630] = "1.20.50",
    [649] = "1.20.60",
    [662] = "1.20.70",
    [671] = "1.20.80",
    [685] = "1.21.0",
    [686] = "1.21.1",
    [712] = "1.21.20",
    [729] = "1.21.30",
    [748] = "1.21.40",
    [766] = "1.21.50",

    -- ── 1.21.60+ (2025 updates) ─────────────────────────────────
    [776] = "1.21.60",   -- Chase the Skies
    [786] = "1.21.70",   -- Spring to Life (March 2025)
    [800] = "1.21.80",   -- The Copper Age (June 2025)
    [818] = "1.21.90",   -- Mounts of Mayhem beta
    [819] = "1.21.93",   -- Mounts of Mayhem (July 2025)
    [830] = "1.21.100",  -- The Garden Awakens (September 2025)
    [835] = "1.21.101",
    [840] = "1.21.110",  -- The Garden Awakens hotfix
    [844] = "1.21.112",  -- hotfix
    [850] = "1.21.120",  -- Mounts of Mayhem update (November 2025)
    [855] = "1.21.121",
    [859] = "1.21.122",
    [866] = "1.21.124",
    [876] = "1.21.130",  -- Mounts of Mayhem final (December 2025)
    [880] = "1.21.131",
    [898] = "1.21.132",

    -- ── 26.x series (new 2026 year-based versioning) ────────────
    -- Mojang switched to year-based versions starting 2026
    -- Preview versions (betas)
    [900] = "26.0-preview.25",  -- Preview 26.0.25 (Dec 2025)
    [905] = "26.0-preview.26",  -- Preview 26.0.26 (Dec 2025)
    [908] = "26.0-preview.27",  -- Preview 26.0.27 (Jan 2026)
    [912] = "26.0-preview.28",  -- Preview 26.0.28 (Jan 2026)

    -- Official releases
    [918] = "26.0",   -- Drop 1 of 2026 (February 10, 2026)
    [920] = "26.1",   -- Hotfix (February 19–23, 2026)
    [924] = "26.2",   -- Hotfix (February 25, 2026) ← LATEST RELEASE
    [926] = "26.3",   -- Hotfix (March 2, 2026)

    -- Future previews (accept gracefully)
    [930] = "26.10-preview",
    [935] = "26.10-preview.23",
    [944] = "26.10-preview.25",  -- latest known preview
}

-- ── Current server protocol ────────────────────────────────────────────────
-- This is what MineLua advertises to connecting clients.
-- 924 = Bedrock Edition 26.2 (released February 25, 2026)
ProtocolManager.CURRENT_PROTOCOL = 924
ProtocolManager.CURRENT_VERSION  = "26.2"

-- Minimum supported protocol (MCBE 1.1.0)
ProtocolManager.MIN_PROTOCOL = 113

-- Protocol range for 26.x series
ProtocolManager.V26_MIN = 918   -- 26.0 official release
ProtocolManager.V26_MAX = 944   -- 26.10 preview (highest known)

-- Packet IDs (MCBE)
ProtocolManager.PACKET_ID = {
    LOGIN = 0x01,
    PLAY_STATUS = 0x02,
    SERVER_TO_CLIENT_HANDSHAKE = 0x03,
    CLIENT_TO_SERVER_HANDSHAKE = 0x04,
    DISCONNECT = 0x05,
    RESOURCE_PACKS_INFO = 0x06,
    RESOURCE_PACK_STACK = 0x07,
    RESOURCE_PACK_CLIENT_RESPONSE = 0x08,
    TEXT = 0x09,
    SET_TIME = 0x0A,
    START_GAME = 0x0B,
    ADD_PLAYER = 0x0C,
    ADD_ENTITY = 0x0D,
    REMOVE_ENTITY = 0x0E,
    ADD_ITEM_ENTITY = 0x0F,
    TAKE_ITEM_ENTITY = 0x11,
    MOVE_ENTITY_ABSOLUTE = 0x12,
    MOVE_PLAYER = 0x13,
    RIDER_JUMP = 0x14,
    UPDATE_BLOCK = 0x15,
    ADD_PAINTING = 0x16,
    TICK_SYNC = 0x17,
    LEVEL_SOUND_EVENT_V1 = 0x18,
    LEVEL_EVENT = 0x19,
    BLOCK_EVENT = 0x1A,
    ENTITY_EVENT = 0x1B,
    MOB_EFFECT = 0x1C,
    UPDATE_ATTRIBUTES = 0x1D,
    INVENTORY_TRANSACTION = 0x1E,
    MOB_EQUIPMENT = 0x1F,
    MOB_ARMOR_EQUIPMENT = 0x20,
    INTERACT = 0x21,
    BLOCK_PICK_REQUEST = 0x22,
    ENTITY_PICK_REQUEST = 0x23,
    PLAYER_ACTION = 0x24,
    HURT_ARMOR = 0x26,
    SET_ENTITY_DATA = 0x27,
    SET_ENTITY_MOTION = 0x28,
    SET_ENTITY_LINK = 0x29,
    SET_HEALTH = 0x2A,
    SET_SPAWN_POSITION = 0x2B,
    ANIMATE = 0x2C,
    RESPAWN = 0x2D,
    CONTAINER_OPEN = 0x2E,
    CONTAINER_CLOSE = 0x2F,
    PLAYER_HOTBAR = 0x30,
    INVENTORY_CONTENT = 0x31,
    INVENTORY_SLOT = 0x32,
    CONTAINER_SET_DATA = 0x33,
    CRAFTING_DATA = 0x34,
    CRAFTING_EVENT = 0x35,
    GUI_DATA_PICK_ITEM = 0x36,
    ADVENTURE_SETTINGS = 0x37,
    BLOCK_ENTITY_DATA = 0x38,
    PLAYER_INPUT = 0x39,
    LEVEL_CHUNK = 0x3A,
    SET_COMMANDS_ENABLED = 0x3B,
    SET_DIFFICULTY = 0x3C,
    CHANGE_DIMENSION = 0x3D,
    SET_PLAYER_GAME_TYPE = 0x3E,
    PLAYER_LIST = 0x3F,
    SIMPLE_EVENT = 0x40,
    TELEMETRY_EVENT = 0x41,
    SPAWN_EXPERIENCE_ORB = 0x42,
    CLIENTBOUND_MAP_ITEM_DATA = 0x43,
    MAP_INFO_REQUEST = 0x44,
    REQUEST_CHUNK_RADIUS = 0x45,
    CHUNK_RADIUS_UPDATE = 0x46,
    ITEM_FRAME_DROP_ITEM = 0x47,
    GAME_RULES_CHANGED = 0x48,
    CAMERA = 0x49,
    BOSS_EVENT = 0x4A,
    SHOW_CREDITS = 0x4B,
    AVAILABLE_COMMANDS = 0x4C,
    COMMAND_REQUEST = 0x4D,
    COMMAND_BLOCK_UPDATE = 0x4E,
    COMMAND_OUTPUT = 0x4F,
    UPDATE_TRADE = 0x50,
    UPDATE_EQUIPMENT = 0x51,
    RESOURCE_PACK_DATA_INFO = 0x52,
    RESOURCE_PACK_CHUNK_DATA = 0x53,
    RESOURCE_PACK_CHUNK_REQUEST = 0x54,
    TRANSFER = 0x55,
    PLAY_SOUND = 0x56,
    STOP_SOUND = 0x57,
    SET_TITLE = 0x58,
    ADD_BEHAVIOR_TREE = 0x59,
    STRUCTURE_BLOCK_UPDATE = 0x5A,
    SHOW_STORE_OFFER = 0x5B,
    PURCHASE_RECEIPT = 0x5C,
    PLAYER_SKIN = 0x5D,
    SUB_CLIENT_LOGIN = 0x5E,
    AUTOMATION_CLIENT_CONNECT = 0x5F,
    SET_LAST_HURT_BY = 0x60,
    BOOK_EDIT = 0x61,
    NPC_REQUEST = 0x62,
    PHOTO_TRANSFER = 0x63,
    MODAL_FORM_REQUEST = 0x64,
    MODAL_FORM_RESPONSE = 0x65,
    SERVER_SETTINGS_REQUEST = 0x66,
    SERVER_SETTINGS_RESPONSE = 0x67,
    SHOW_PROFILE = 0x68,
    SET_DEFAULT_GAME_TYPE = 0x69,
    REMOVE_OBJECTIVE = 0x6A,
    SET_DISPLAY_OBJECTIVE = 0x6B,
    SET_SCORE = 0x6C,
    LAB_TABLE = 0x6D,
    UPDATE_BLOCK_SYNCED = 0x6E,
    MOVE_ENTITY_DELTA = 0x6F,
    SET_SCOREBOARD_IDENTITY = 0x70,
    SET_LOCAL_PLAYER_AS_INITIALIZED = 0x71,
    UPDATE_SOFT_ENUM = 0x72,
    NETWORK_STACK_LATENCY = 0x73,
    SCRIPT_CUSTOM_EVENT = 0x75,
    SPAWN_PARTICLE_EFFECT = 0x76,
    AVAILABLE_ENTITY_IDENTIFIERS = 0x77,
    LEVEL_SOUND_EVENT_V2 = 0x78,
    NETWORK_CHUNK_PUBLISHER_UPDATE = 0x79,
    BIOME_DEFINITION_LIST = 0x7A,
    LEVEL_SOUND_EVENT = 0x7B,
    LEVEL_EVENT_GENERIC = 0x7C,
    LECTERN_UPDATE = 0x7D,
    VIDEO_STREAM_CONNECT = 0x7E,
    CLIENT_CACHE_STATUS = 0x81,
    ON_SCREEN_TEXTURE_ANIMATION = 0x82,
    MAP_CREATE_LOCKED_COPY = 0x83,
    STRUCTURE_TEMPLATE_DATA_REQUEST = 0x84,
    STRUCTURE_TEMPLATE_DATA_RESPONSE = 0x85,
    UPDATE_BLOCK_PROPERTIES = 0x87,
    CLIENT_CACHE_BLOB_STATUS = 0x88,
    CLIENT_CACHE_MISS_RESPONSE = 0x89,
    EDUCATION_SETTINGS = 0x8A,
    EMOTE = 0x8B,
    MULTIPLAYER_SETTINGS = 0x8C,
    SETTINGS_COMMAND = 0x8D,
    ANVIL_DAMAGE = 0x8E,
    COMPLETED_USING_ITEM = 0x8F,
    NETWORK_SETTINGS = 0x8F,
    PLAYER_AUTH_INPUT = 0x90,
    CREATIVE_CONTENT = 0x91,
    PLAYER_ENCHANT_OPTIONS = 0x92,
    ITEM_STACK_REQUEST = 0x93,
    ITEM_STACK_RESPONSE = 0x94,
    PLAYER_ARMOR_DAMAGE = 0x95,
    CODE_BUILDER = 0x96,
    UPDATE_PLAYER_GAME_TYPE = 0x97,
    EMOTE_LIST = 0x98,
    POSITION_TRACKING_DB_SERVER_BROADCAST = 0x99,
    POSITION_TRACKING_DB_CLIENT_REQUEST = 0x9A,
    DEBUG_INFO = 0x9B,
    PACKET_VIOLATION_WARNING = 0x9C,
    MOTION_PREDICTION_HINTS = 0x9D,
    ANIMATE_ENTITY = 0x9E,
    CAMERA_SHAKE = 0x9F,
    PLAYER_FOG = 0xA0,
    CORRECT_PLAYER_MOVE_PREDICTION = 0xA1,
    ITEM_COMPONENT = 0xA2,
    FILTER_TEXT = 0xA3,
    CLIENT_BOUNDABLE_DEBUG = 0xA4,
    SYNC_ENTITY_PROPERTY = 0xA5,
    ADD_VOLUME_ENTITY = 0xA6,
    REMOVE_VOLUME_ENTITY = 0xA7,
    SIMULATION_TYPE = 0xA8,
    NPC_DIALOGUE = 0xA9,
    EDU_URI_RESOURCE = 0xAA,
    CAMERA_PRESETS = 0xAB,
    UNLOCKED_RECIPES = 0xAC,
}

-- Play status codes
ProtocolManager.PLAY_STATUS = {
    LOGIN_SUCCESS = 0,
    LOGIN_FAILED_CLIENT = 1,
    LOGIN_FAILED_SERVER = 2,
    PLAYER_SPAWN = 3,
    LOGIN_FAILED_INVALID_TENANT = 4,
    LOGIN_FAILED_VANILLA_EDU = 5,
    LOGIN_FAILED_EDU_VANILLA = 6,
    LOGIN_FAILED_SERVER_FULL = 7,
}

function ProtocolManager.new(server)
    local self = setmetatable({}, ProtocolManager)
    self.server = server
    self.handlers = {}
    self:registerHandlers()
    return self
end

function ProtocolManager:registerHandlers()
    local PID = ProtocolManager.PACKET_ID
    
    self.handlers[PID.LOGIN] = require("protocol.handlers.LoginHandler")
    self.handlers[PID.CLIENT_TO_SERVER_HANDSHAKE] = require("protocol.handlers.HandshakeHandler")
    self.handlers[PID.RESOURCE_PACK_CLIENT_RESPONSE] = require("protocol.handlers.ResourcePackHandler")
    self.handlers[PID.REQUEST_CHUNK_RADIUS] = require("protocol.handlers.ChunkRadiusHandler")
    self.handlers[PID.TEXT] = require("protocol.handlers.TextHandler")
    self.handlers[PID.MOVE_PLAYER] = require("protocol.handlers.MoveHandler")
    self.handlers[PID.PLAYER_ACTION] = require("protocol.handlers.PlayerActionHandler")
    self.handlers[PID.INTERACT] = require("protocol.handlers.InteractHandler")
    self.handlers[PID.INVENTORY_TRANSACTION] = require("protocol.handlers.InventoryHandler")
    self.handlers[PID.CRAFTING_EVENT] = require("protocol.handlers.CraftingHandler")
    self.handlers[PID.COMMAND_REQUEST] = require("protocol.handlers.CommandHandler")
    self.handlers[PID.CONTAINER_CLOSE] = require("protocol.handlers.ContainerHandler")
    self.handlers[PID.BLOCK_ENTITY_DATA] = require("protocol.handlers.BlockEntityHandler")
    self.handlers[PID.LEVEL_SOUND_EVENT] = require("protocol.handlers.SoundHandler")
    self.handlers[PID.SET_LOCAL_PLAYER_AS_INITIALIZED] = require("protocol.handlers.InitHandler")
    self.handlers[PID.PLAYER_AUTH_INPUT] = require("protocol.handlers.AuthInputHandler")
    self.handlers[PID.ITEM_STACK_REQUEST] = require("protocol.handlers.ItemStackHandler")
    self.handlers[PID.MOB_EQUIPMENT] = require("protocol.handlers.MobEquipmentHandler")
    self.handlers[PID.EMOTE] = require("protocol.handlers.EmoteHandler")
    self.handlers[PID.ANIMATE] = require("protocol.handlers.AnimateHandler")
    self.handlers[PID.BLOCK_PICK_REQUEST] = require("protocol.handlers.BlockPickHandler")
    self.handlers[PID.MODAL_FORM_RESPONSE] = require("protocol.handlers.FormResponseHandler")
    self.handlers[PID.CLIENT_CACHE_STATUS] = require("protocol.handlers.CacheStatusHandler")
    self.handlers[PID.NETWORK_STACK_LATENCY] = require("protocol.handlers.LatencyHandler")
    self.handlers[PID.PACKET_VIOLATION_WARNING] = require("protocol.handlers.ViolationHandler")
    self.handlers[PID.MULTIPLAYER_SETTINGS] = require("protocol.handlers.MultiplayerSettingsHandler")
end

function ProtocolManager:handlePacket(player, raw_data)
    -- Decompress if needed
    local data = self:decompress(player, raw_data)
    if not data then return end
    
    local buf = BitBuffer.new(data)
    
    -- Process all batched packets
    while buf:remaining() > 0 do
        local pkt_len = buf:readVarInt()
        if pkt_len <= 0 or pkt_len > buf:remaining() then break end
        
        local pkt_data = buf:readBytes(pkt_len)
        local pkt_buf = BitBuffer.new(pkt_data)
        local packet_id = pkt_buf:readVarInt()
        
        local handler = self.handlers[packet_id]
        if handler then
            local ok, err = pcall(handler.handle, handler, player, pkt_buf)
            if not ok then
                Logger.error(string.format("Error handling packet 0x%02X: %s", packet_id, tostring(err)))
            end
        else
            Logger.debug(string.format("Unhandled packet 0x%02X from %s", packet_id, 
                player and player.name or "unknown"))
        end
    end
end

function ProtocolManager:decompress(player, data)
    if not data or #data == 0 then return nil end
    
    local algo = data:byte(1)
    
    if algo == 0xFF then
        -- No compression
        return data:sub(2)
    elseif algo == 0x00 then
        -- zlib deflate
        local ok, result = pcall(zlib.decompress, data:sub(2))
        if ok then return result end
        Logger.debug("Decompression failed, trying raw")
        return data:sub(2)
    elseif algo == 0x02 then
        -- Snappy (fallback to no compression attempt)
        return data:sub(2)
    else
        -- Legacy: try as uncompressed
        return data
    end
end

function ProtocolManager:buildPacket(packet_id, ...)
    local buf = BitBuffer.new()
    buf:writeVarInt(packet_id)
    return buf
end

function ProtocolManager:sendPacket(player, packet_id, data_buf)
    if not player or not player.connection then return end
    
    local packet_data = data_buf:tostring()
    
    -- Build outer buffer with length prefix
    local outer = BitBuffer.new()
    local id_buf = BitBuffer.new()
    id_buf:writeVarInt(packet_id)
    local full_packet = id_buf:tostring() .. packet_data
    outer:writeVarInt(#full_packet)
    outer:writeBytes(full_packet)
    
    -- Compress
    local compressed = self:compress(outer:tostring(), player)
    
    -- Send via RakNet
    self.server.raknet:sendToPlayer(player, compressed)
end

function ProtocolManager:compress(data, player)
    local threshold = 256
    local algo_byte
    local compressed
    
    if #data > threshold then
        -- Use zlib compression
        local ok, result = pcall(zlib.compress, data)
        if ok then
            algo_byte = "\x00"
            compressed = result
        else
            algo_byte = "\xFF"
            compressed = data
        end
    else
        algo_byte = "\xFF"
        compressed = data
    end
    
    return algo_byte .. compressed
end

-- Helper: send play status
function ProtocolManager:sendPlayStatus(player, status)
    local buf = BitBuffer.new()
    buf:writeInt(status)
    self:sendPacket(player, ProtocolManager.PACKET_ID.PLAY_STATUS, buf)
end

-- Helper: send disconnect
function ProtocolManager:sendDisconnect(player, message, hide_disconnect)
    local buf = BitBuffer.new()
    buf:writeBool(hide_disconnect or false)
    buf:writeString(message or "Disconnected")
    buf:writeString(message or "Disconnected")
    self:sendPacket(player, ProtocolManager.PACKET_ID.DISCONNECT, buf)
end

-- Helper: send text message
function ProtocolManager:sendMessage(player, message, type_, xuid)
    type_ = type_ or 0
    xuid = xuid or ""
    local buf = BitBuffer.new()
    buf:writeByte(type_)
    buf:writeBool(false) -- needs translation
    if type_ == 1 or type_ == 2 then
        buf:writeString(player.name or "Server")
    end
    buf:writeString(message)
    if type_ == 1 or type_ == 2 then
        buf:writeVarInt(0) -- param count
    end
    buf:writeString(xuid)
    buf:writeString("") -- platform chat id
    self:sendPacket(player, ProtocolManager.PACKET_ID.TEXT, buf)
end

-- Helper: broadcast to all players
function ProtocolManager:broadcast(packet_id, data_buf)
    local players = self.server.players:getAll()
    for _, player in ipairs(players) do
        self:sendPacket(player, packet_id, data_buf)
    end
end

return ProtocolManager
