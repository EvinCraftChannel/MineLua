-- MineLua Player
-- Represents a connected player with all attributes and methods

local Logger = require("utils.Logger")
local BitBuffer = require("utils.BitBuffer")
local Inventory = require("server.Inventory")
local Position = require("utils.Position")

local Player = {}
Player.__index = Player

-- Game modes
Player.GAMEMODE = {
    SURVIVAL = 0,
    CREATIVE = 1,
    ADVENTURE = 2,
    SPECTATOR = 6,
}

-- Permissions
Player.PERMISSION = {
    VISITOR = 0,
    MEMBER = 1,
    OPERATOR = 2,
    CUSTOM = 3,
}

local entity_id_counter = 1

function Player.new(server, connection)
    local self = setmetatable({}, Player)
    
    self.server = server
    self.connection = connection
    
    -- Identity
    self.id = entity_id_counter
    entity_id_counter = entity_id_counter + 1
    self.name = "Player"
    self.uuid = ""
    self.xuid = ""
    self.device_id = ""
    self.platform = 0
    self.client_random_id = 0
    self.skin = nil
    
    -- Position
    self.world = nil
    self.x = 0
    self.y = 64
    self.z = 0
    self.yaw = 0
    self.pitch = 0
    self.head_yaw = 0
    
    -- State
    self.spawned = false
    self.alive = true
    self.on_ground = false
    self.sneaking = false
    self.sprinting = false
    self.swimming = false
    self.flying = false
    self.op = false
    self.initialized = false
    
    -- Game properties
    self.health = 20.0
    self.max_health = 20.0
    self.food = 20
    self.food_saturation = 5.0
    self.experience = 0
    self.experience_level = 0
    self.game_mode = Player.GAMEMODE.SURVIVAL
    self.permission = Player.PERMISSION.MEMBER
    
    -- Inventory
    self.inventory = Inventory.new(self, 36)
    self.armor = Inventory.new(self, 4)
    self.offhand = Inventory.new(self, 1)
    self.crafting = Inventory.new(self, 4)
    self.selected_slot = 0
    
    -- Chunk tracking
    self.loaded_chunks = {}
    self.view_distance = server.view_distance or 10
    self.chunk_radius = self.view_distance
    
    -- Protocol
    self.protocol_version = 0
    self.game_version = "unknown"
    
    -- Active containers
    self.open_container = nil
    
    -- Metadata
    self.metadata = {}
    self.effects = {}
    self.score = 0
    self.display_name = nil
    self.locale = "en_US"
    self.latency = 0
    
    -- Login time
    self.login_time = os.time()
    
    return self
end

function Player:spawn()
    if self.spawned then return end
    
    -- Load player data
    self:loadData()
    
    -- Assign default world
    if not self.world then
        self.world = self.server.worlds:getDefault()
    end
    
    if not self.world then
        Logger.error("No default world found!")
        self:kick("Server configuration error: no world loaded")
        return
    end
    
    -- Set spawn position from world
    if self.x == 0 and self.y == 64 and self.z == 0 then
        local sx, sy, sz = self.world:getSpawnPoint()
        self.x, self.y, self.z = sx, sy, sz
    end
    
    -- Send start game packet
    self:sendStartGame()
    
    -- Send world data
    self:sendChunks()
    
    -- Send inventory
    self:sendInventory()
    
    -- Notify play status
    self.server.protocol:sendPlayStatus(self,
        require("protocol.ProtocolManager").PLAY_STATUS.PLAYER_SPAWN)
    
    self.spawned = true
    self.alive = true
    
    -- Fire event
    self.server.events:fire("PlayerJoin", {player = self})
    
    -- Announce join
    if self.server.config.announce_player_join ~= false then
        self.server:broadcastMessage(string.format("§e%s joined the game", self.name))
    end
    
    Logger.info(string.format("Player '%s' spawned at %.1f,%.1f,%.1f in world '%s'",
        self.name, self.x, self.y, self.z, self.world.name))
end

function Player:sendStartGame()
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local server = self.server
    local world = self.world
    
    local buf = BitBuffer.new()
    
    -- Entity IDs
    buf:writeLInt64(self.id) -- entity id (runtime)
    buf:writeLInt64(self.id) -- entity unique id
    
    -- Game mode
    buf:writeVarInt(self.game_mode)
    
    -- Player position
    buf:writeFloat(self.x)
    buf:writeFloat(self.y)
    buf:writeFloat(self.z)
    
    -- Rotation
    buf:writeFloat(self.yaw)
    buf:writeFloat(self.pitch)
    
    -- World settings
    local seed = world.seed or 0
    buf:writeLInt64(seed) -- level seed
    buf:writeVarInt(1) -- spawn biome type (default)
    buf:writeString("plains") -- user defined biome name
    buf:writeVarInt(world.dimension or 0) -- dimension
    buf:writeVarInt(1) -- generator (1=infinite)
    buf:writeVarInt(server.config.game_mode == "creative" and 1 or 0) -- world game mode
    buf:writeBool(false) -- hardcore
    buf:writeVarInt(self:getDifficultyValue()) -- difficulty
    
    -- Spawn position
    local sx, sy, sz = world:getSpawnPoint()
    buf:writeZigZag(sx)
    buf:writeVarInt(sy)
    buf:writeZigZag(sz)
    
    buf:writeBool(false) -- has achievements disabled
    buf:writeVarInt(world.time or 0) -- day cycle stop time
    buf:writeVarInt(0) -- edu edition offer
    buf:writeBool(false) -- edu features enabled
    buf:writeString("") -- edu product uuid
    buf:writeFloat(0.0) -- rain level
    buf:writeFloat(0.0) -- lightning level
    buf:writeBool(false) -- confirmed platform locked content
    buf:writeBool(true) -- is multiplayer
    buf:writeBool(true) -- broadcast to lan
    buf:writeVarInt(4) -- xbox live broadcast intent
    buf:writeVarInt(4) -- platform broadcast intent
    buf:writeBool(true) -- commands enabled
    buf:writeBool(false) -- texture packs required
    
    -- Game rules
    local game_rules = world:getGameRules()
    buf:writeVarInt(#game_rules)
    for _, rule in ipairs(game_rules) do
        buf:writeString(rule.name)
        buf:writeBool(rule.editable ~= false)
        buf:writeVarInt(rule.type) -- 1=bool, 2=int, 3=float
        if rule.type == 1 then
            buf:writeBool(rule.value)
        elseif rule.type == 2 then
            buf:writeVarInt(rule.value)
        elseif rule.type == 3 then
            buf:writeFloat(rule.value)
        end
    end
    
    -- Experiments
    buf:writeInt(0) -- experiment count
    buf:writeBool(false) -- experiments previously used
    
    buf:writeBool(false) -- bonus chest enabled
    buf:writeBool(false) -- start with map
    buf:writeVarInt(self:getPermissionLevel()) -- permission level
    buf:writeInt(4) -- chunk tick range
    buf:writeBool(false) -- locked behavior pack
    buf:writeBool(false) -- locked texture pack  
    buf:writeBool(false) -- from locked world template
    buf:writeBool(false) -- msa gamertag only xbox
    buf:writeBool(false) -- from world template
    buf:writeBool(false) -- world template option locked
    buf:writeBool(false) -- only spawn v1 villagers
    buf:writeBool(false) -- persona disabled
    buf:writeBool(false) -- custom skins disabled
    buf:writeBool(false) -- emote chat muted
    
    buf:writeString("1.20.80") -- game version
    buf:writeInt(0) -- limited world width
    buf:writeInt(0) -- limited world height  
    buf:writeBool(false) -- nether type
    buf:writeString("") -- edu shared uri resource
    buf:writeBool(false) -- force experimental
    buf:writeByte(1) -- chat restriction level
    buf:writeBool(false) -- disable player interactions
    
    -- Level ID and world name
    buf:writeString(world.id or "MineLua")
    buf:writeString(world.name or "World")
    
    -- Template content identity
    buf:writeString("")
    buf:writeBool(world.is_trial or false)
    
    -- Movement settings
    buf:writeByte(0) -- server authoritative movement
    buf:writeLInt64(world.time or 0) -- current tick
    buf:writeZigZag(0) -- enchantment seed
    
    -- Block properties
    local block_registry = require("block.BlockRegistry")
    local custom_blocks = block_registry:getCustomBlocks()
    buf:writeVarInt(#custom_blocks)
    for _, block in ipairs(custom_blocks) do
        buf:writeString(block.name)
        buf:writeBytes(block.nbt or "\x0A\x00\x00") -- NBT compound
    end
    
    -- Item overrides
    buf:writeShort(0)
    
    -- Multiplayer correlation id
    buf:writeString(self:generateMultiplayerId())
    
    -- Server engine
    buf:writeBool(false) -- inventory server authoritative
    buf:writeString("MineLua") -- server engine
    
    -- Player property data (NBT)
    buf:writeBytes("\x0A\x00\x00") -- empty compound NBT
    
    buf:writeLInt64(0) -- block registry checksum
    buf:writeBytes("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00") -- world template id (UUID)
    buf:writeBool(false) -- client side generation
    buf:writeBool(false) -- has hashed block palette
    buf:writeBool(false) -- use block network id hashes
    
    server.protocol:sendPacket(self, PID.START_GAME, buf)
end

function Player:sendChunks()
    -- Send initial chunks around player
    local cx = math.floor(self.x / 16)
    local cz = math.floor(self.z / 16)
    local radius = math.min(self.chunk_radius, 8) -- Start with smaller radius
    
    local chunks_sent = 0
    for dx = -radius, radius do
        for dz = -radius, radius do
            if math.sqrt(dx*dx + dz*dz) <= radius then
                local chunk_x = cx + dx
                local chunk_z = cz + dz
                local key = chunk_x .. "," .. chunk_z
                
                if not self.loaded_chunks[key] then
                    self:sendChunk(chunk_x, chunk_z)
                    self.loaded_chunks[key] = true
                    chunks_sent = chunks_sent + 1
                end
            end
        end
    end
    
    -- Send network chunk publisher update
    self:sendNetworkChunkPublisher()
end

function Player:sendChunk(cx, cz)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local chunk = self.world:getOrGenerateChunk(cx, cz)
    
    local buf = BitBuffer.new()
    buf:writeZigZag(cx)
    buf:writeZigZag(cz)
    buf:writeVarInt(chunk:getDimensionCount()) -- sub chunk count
    buf:writeBool(true) -- cache enabled
    
    -- Sub-chunks
    local sub_chunks = chunk:getSubChunks()
    for _, sub in ipairs(sub_chunks) do
        buf:writeBytes(sub:serialize())
    end
    
    -- 2D biome data (256 bytes)
    local biome_data = chunk:getBiomeData()
    buf:writeBytes(biome_data)
    
    -- Border blocks
    buf:writeByte(0)
    
    -- Block entities
    local block_entities = chunk:getBlockEntities()
    for _, be in ipairs(block_entities) do
        buf:writeBytes(be:serializeNBT())
    end
    
    self.server.protocol:sendPacket(self, PID.LEVEL_CHUNK, buf)
end

function Player:sendNetworkChunkPublisher()
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    
    buf:writeZigZag(math.floor(self.x))
    buf:writeVarInt(math.floor(self.y))
    buf:writeZigZag(math.floor(self.z))
    buf:writeVarInt(self.chunk_radius * 16)
    buf:writeInt(0) -- saved chunks count
    
    self.server.protocol:sendPacket(self, PID.NETWORK_CHUNK_PUBLISHER_UPDATE, buf)
end

function Player:sendInventory()
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    
    buf:writeByte(0x00) -- window id (inventory)
    buf:writeVarInt(#self.inventory.slots)
    
    for _, item in ipairs(self.inventory.slots) do
        self:writeItemStack(buf, item)
    end
    
    self.server.protocol:sendPacket(self, PID.INVENTORY_CONTENT, buf)
end

function Player:writeItemStack(buf, item)
    if not item or item.id == 0 then
        buf:writeShort(0) -- air
        return
    end
    
    buf:writeShort(item.id)
    buf:writeShort(item.count)
    buf:writeShort(item.damage or 0)
    
    -- Has NBT
    if item.nbt then
        buf:writeShort(0xFFFF)
        buf:writeByte(1) -- version
        buf:writeBytes(item.nbt)
    else
        buf:writeShort(0)
    end
    
    buf:writeVarInt(0) -- can place on count
    buf:writeVarInt(0) -- can destroy count
    buf:writeLInt64(0) -- blocking tick
end

function Player:tick(ticks)
    if not self.spawned then return end
    
    -- Update chunks if moved
    self:updateChunks()
    
    -- Health regeneration
    if ticks % 80 == 0 and self.health < self.max_health and self.food >= 18 then
        self:heal(1)
    end
    
    -- Food depletion
    if ticks % 80 == 0 and self.game_mode == Player.GAMEMODE.SURVIVAL then
        -- Deduct food if sprinting or swimming
        if self.sprinting or self.swimming then
            self.food = math.max(0, self.food - 1)
        end
    end
    
    -- Starvation damage
    if self.food == 0 and ticks % 80 == 0 and self.game_mode == Player.GAMEMODE.SURVIVAL then
        if self.health > 1 then
            self:damage(1, "starvation")
        end
    end
end

function Player:updateChunks()
    local cx = math.floor(self.x / 16)
    local cz = math.floor(self.z / 16)
    local radius = self.chunk_radius
    
    -- Load new chunks in view
    for dx = -radius, radius do
        for dz = -radius, radius do
            if math.sqrt(dx*dx + dz*dz) <= radius then
                local key = (cx+dx) .. "," .. (cz+dz)
                if not self.loaded_chunks[key] then
                    self:sendChunk(cx+dx, cz+dz)
                    self.loaded_chunks[key] = true
                end
            end
        end
    end
end

function Player:sendMessage(message)
    self.server.protocol:sendMessage(self, message, 0)
end

function Player:sendTitle(title, subtitle, fade_in, stay, fade_out)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    
    -- Set title
    local buf = BitBuffer.new()
    buf:writeVarInt(2) -- SET_TITLE
    buf:writeVarInt(fade_in or 10)
    buf:writeVarInt(stay or 70)
    buf:writeVarInt(fade_out or 20)
    buf:writeString("")
    buf:writeString("")
    self.server.protocol:sendPacket(self, PID.SET_TITLE, buf)
    
    buf = BitBuffer.new()
    buf:writeVarInt(0) -- CLEAR
    buf:writeVarInt(0) buf:writeVarInt(0) buf:writeVarInt(0)
    buf:writeString("") buf:writeString("")
    self.server.protocol:sendPacket(self, PID.SET_TITLE, buf)
    
    buf = BitBuffer.new()
    buf:writeVarInt(1) -- SUBTITLE
    buf:writeVarInt(0) buf:writeVarInt(0) buf:writeVarInt(0)
    buf:writeString(subtitle or "")
    buf:writeString("")
    self.server.protocol:sendPacket(self, PID.SET_TITLE, buf)
    
    buf = BitBuffer.new()
    buf:writeVarInt(2) -- TITLE
    buf:writeVarInt(0) buf:writeVarInt(0) buf:writeVarInt(0)
    buf:writeString(title or "")
    buf:writeString("")
    self.server.protocol:sendPacket(self, PID.SET_TITLE, buf)
end

function Player:sendActionBar(message)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeVarInt(5) -- ACTION_BAR
    buf:writeVarInt(0) buf:writeVarInt(0) buf:writeVarInt(0)
    buf:writeString(message)
    buf:writeString("")
    self.server.protocol:sendPacket(self, PID.SET_TITLE, buf)
end

function Player:sendForm(form_id, form_data)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local json = require("utils.json")
    local buf = BitBuffer.new()
    buf:writeVarInt(form_id)
    buf:writeString(json.encode(form_data))
    self.server.protocol:sendPacket(self, PID.MODAL_FORM_REQUEST, buf)
end

function Player:transfer(address, port)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeString(address)
    buf:writeShort(port or 19132)
    buf:writeBool(false)
    self.server.protocol:sendPacket(self, PID.TRANSFER, buf)
end

function Player:heal(amount)
    self.health = math.min(self.max_health, self.health + amount)
    self:sendHealth()
end

function Player:damage(amount, cause)
    if self.game_mode == Player.GAMEMODE.CREATIVE then return end
    
    local event = self.server.events:fire("EntityDamage", {
        entity = self,
        damage = amount,
        cause = cause,
        cancel = false
    })
    
    if event and event.cancel then return end
    amount = event and event.damage or amount
    
    self.health = math.max(0, self.health - amount)
    self:sendHealth()
    
    if self.health <= 0 then
        self:die(cause)
    end
end

function Player:die(cause)
    self.alive = false
    
    local event = self.server.events:fire("PlayerDeath", {
        player = self,
        cause = cause
    })
    
    -- Drop inventory
    if not (event and event.keep_inventory) then
        self:dropInventory()
    end
    
    -- Announce death
    local death_msg = self:getDeathMessage(cause)
    self.server:broadcastMessage(death_msg)
    
    Logger.info(string.format("Player '%s' died: %s", self.name, cause or "unknown"))
    
    -- Respawn after 1 second
    self.server.scheduler:after(20, function()
        self:respawn()
    end)
end

function Player:respawn()
    self.health = self.max_health
    self.food = 20
    self.alive = true
    self.effects = {}
    
    local sx, sy, sz = self.world:getSpawnPoint()
    self:teleport(sx, sy, sz)
    
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeFloat(sx)
    buf:writeFloat(sy)
    buf:writeFloat(sz)
    buf:writeByte(1) -- state: player spawned
    buf:writeLInt64(self.id)
    
    self.server.protocol:sendPacket(self, PID.RESPAWN, buf)
    self.server.protocol:sendPlayStatus(self,
        require("protocol.ProtocolManager").PLAY_STATUS.PLAYER_SPAWN)
    
    self.server.events:fire("PlayerRespawn", {player = self})
end

function Player:getDeathMessage(cause)
    local messages = {
        starvation = string.format("%s starved to death", self.name),
        void = string.format("%s fell out of the world", self.name),
        fall = string.format("%s hit the ground too hard", self.name),
        fire = string.format("%s went up in flames", self.name),
        lava = string.format("%s tried to swim in lava", self.name),
        drown = string.format("%s drowned", self.name),
    }
    return messages[cause] or string.format("%s died", self.name)
end

function Player:dropInventory()
    for i, item in ipairs(self.inventory.slots) do
        if item and item.id ~= 0 then
            self.world:dropItem(self.x, self.y, self.z, item)
            self.inventory.slots[i] = nil
        end
    end
end

function Player:teleport(x, y, z, yaw, pitch)
    self.x = x
    self.y = y
    self.z = z
    if yaw then self.yaw = yaw end
    if pitch then self.pitch = pitch end
    
    -- Clear loaded chunks to force reload
    self.loaded_chunks = {}
    
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeLInt64(self.id)
    buf:writeFloat(x)
    buf:writeFloat(y)
    buf:writeFloat(z)
    buf:writeFloat(self.yaw)
    buf:writeFloat(self.pitch)
    buf:writeByte(0) -- mode: teleport
    buf:writeBool(self.on_ground)
    buf:writeLInt64(0) -- riding entity id
    buf:writeVarInt(4) -- teleport cause
    buf:writeVarInt(0) -- source entity type
    buf:writeLInt64(0) -- tick
    
    self.server.protocol:sendPacket(self, PID.MOVE_PLAYER, buf)
    
    -- Resend chunks
    self:sendChunks()
    
    self.server.events:fire("PlayerTeleport", {player = self, x=x, y=y, z=z})
end

function Player:changeDimension(dimension, x, y, z)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeVarInt(dimension)
    buf:writeFloat(x or self.x)
    buf:writeFloat(y or self.y)
    buf:writeFloat(z or self.z)
    buf:writeBool(false)
    self.server.protocol:sendPacket(self, PID.CHANGE_DIMENSION, buf)
    
    self.loaded_chunks = {}
end

function Player:sendHealth()
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeFloat(self.health)
    self.server.protocol:sendPacket(self, PID.SET_HEALTH, buf)
end

function Player:setGameMode(mode)
    self.game_mode = mode
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeVarInt(mode)
    self.server.protocol:sendPacket(self, PID.SET_PLAYER_GAME_TYPE, buf)
end

function Player:setOp(is_op)
    self.op = is_op
    if is_op then
        self.permission = Player.PERMISSION.OPERATOR
    else
        self.permission = Player.PERMISSION.MEMBER
    end
    self:sendAdventureSettings()
end

function Player:isOp()
    return self.op or self.server:isOp(self.name)
end

function Player:getPermissionLevel()
    if self:isOp() then return 2 end
    return 1
end

function Player:getDifficultyValue()
    local difficulty_map = {
        peaceful = 0,
        easy = 1,
        normal = 2,
        hard = 3
    }
    return difficulty_map[self.server.difficulty] or 2
end

function Player:sendAdventureSettings()
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    
    local flags = 0
    if self.game_mode == Player.GAMEMODE.CREATIVE then
        flags = flags | 0x0008 -- auto jump
        flags = flags | 0x0100 -- no clip (creative)
    end
    if self.flying then flags = flags | 0x0200 end
    
    buf:writeVarInt(flags)
    buf:writeVarInt(0) -- command permission
    buf:writeVarInt(0) -- action permissions
    buf:writeVarInt(self:getPermissionLevel()) -- permission level
    buf:writeVarInt(0) -- custom stored permissions
    buf:writeLInt64(self.id)
    
    self.server.protocol:sendPacket(self, PID.ADVENTURE_SETTINGS, buf)
end

function Player:addEffect(effect_id, amplifier, duration, particles)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeByte(1) -- add
    buf:writeLInt64(self.id)
    buf:writeVarInt(effect_id)
    buf:writeVarInt(amplifier or 0)
    buf:writeBool(particles ~= false)
    buf:writeVarInt(duration or 300)
    
    self.server.protocol:sendPacket(self, PID.MOB_EFFECT, buf)
    
    self.effects[effect_id] = {
        amplifier = amplifier or 0,
        duration = duration or 300,
        particles = particles ~= false
    }
end

function Player:removeEffect(effect_id)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeByte(2) -- remove
    buf:writeLInt64(self.id)
    buf:writeVarInt(effect_id)
    
    self.server.protocol:sendPacket(self, PID.MOB_EFFECT, buf)
    self.effects[effect_id] = nil
end

function Player:playSound(sound, x, y, z, volume, pitch)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeString(sound)
    buf:writeZigZag(math.floor((x or self.x) * 8))
    buf:writeZigZag(math.floor((y or self.y) * 8))
    buf:writeZigZag(math.floor((z or self.z) * 8))
    buf:writeFloat(volume or 1.0)
    buf:writeFloat(pitch or 1.0)
    self.server.protocol:sendPacket(self, PID.PLAY_SOUND, buf)
end

function Player:kick(reason)
    Logger.info(string.format("Kicking player '%s': %s", self.name, reason))
    self.server.protocol:sendDisconnect(self, reason)
    self:close()
end

function Player:close()
    if self.spawned then
        self:saveData()
        if self.server.config.announce_player_leave ~= false then
            self.server:broadcastMessage(string.format("§e%s left the game", self.name))
        end
    end
    self.spawned = false
    self.server.events:fire("PlayerQuit", {player = self})
end

function Player:loadData()
    local path = string.format("worlds/%s/players/%s.dat", 
        self.world and self.world.name or "world", self.xuid ~= "" and self.xuid or self.name)
    
    local f = io.open(path, "r")
    if not f then return end
    
    local ok, data = pcall(require("utils.json").decode, f:read("*a"))
    f:close()
    
    if not ok or not data then return end
    
    self.x = data.x or self.x
    self.y = data.y or self.y
    self.z = data.z or self.z
    self.yaw = data.yaw or self.yaw
    self.pitch = data.pitch or self.pitch
    self.health = data.health or self.health
    self.food = data.food or self.food
    self.game_mode = data.game_mode or self.game_mode
    self.experience = data.experience or 0
    self.experience_level = data.experience_level or 0
    self.op = data.op or false
    
    -- Load inventory
    if data.inventory then
        for i, item in ipairs(data.inventory) do
            self.inventory.slots[i] = item
        end
    end
end

function Player:saveData()
    if not self.world then return end
    
    local dir = string.format("worlds/%s/players", self.world.name)
    os.execute("mkdir -p " .. dir)
    
    local path = string.format("%s/%s.dat", dir, self.xuid ~= "" and self.xuid or self.name)
    
    local data = {
        name = self.name,
        xuid = self.xuid,
        x = self.x,
        y = self.y,
        z = self.z,
        yaw = self.yaw,
        pitch = self.pitch,
        health = self.health,
        food = self.food,
        game_mode = self.game_mode,
        experience = self.experience,
        experience_level = self.experience_level,
        op = self.op,
        inventory = self.inventory.slots,
        last_seen = os.time()
    }
    
    local f = io.open(path, "w")
    if f then
        f:write(require("utils.json").encode(data))
        f:close()
    end
end

function Player:generateMultiplayerId()
    return string.format("{%s}", self.uuid or "00000000-0000-0000-0000-000000000000")
end

function Player:getDisplayName()
    return self.display_name or self.name
end

function Player:getPosition()
    return {x = self.x, y = self.y, z = self.z}
end

function Player:getWorld()
    return self.world
end

function Player:isOnline()
    return self.spawned and self.connection ~= nil
end

return Player
