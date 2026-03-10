-- MineLua World
-- Represents a Minecraft world with chunk storage and generation

local Logger = require("utils.Logger")
local Chunk = require("world.Chunk")
local ChunkGenerator = require("world.ChunkGenerator")
local BitBuffer = require("utils.BitBuffer")

local World = {}
World.__index = World

-- Dimensions
World.DIMENSION = {
    OVERWORLD = 0,
    NETHER = 1,
    END = 2,
}

function World.new(server, name, path)
    local self = setmetatable({}, World)
    
    self.server = server
    self.name = name
    self.path = path
    self.id = name
    
    -- World properties
    self.seed = math.random(0, 2^30)
    self.dimension = World.DIMENSION.OVERWORLD
    self.time = 6000 -- noon
    self.day_cycle = true
    self.weather = "clear"
    self.rain_level = 0
    self.lightning_level = 0
    
    -- Spawn position
    self.spawn_x = 0
    self.spawn_y = 64
    self.spawn_z = 0
    
    -- Generator
    self.generator_type = "default"
    self.generator = nil
    
    -- Chunk storage
    self.chunks = {} -- "cx,cz" -> Chunk
    self.max_loaded_chunks = 4096
    
    -- Game rules
    self.game_rules = {
        {name = "commandBlockOutput", type = 1, value = true, editable = true},
        {name = "doDaylightCycle", type = 1, value = true, editable = true},
        {name = "doEntityDrops", type = 1, value = true, editable = true},
        {name = "doFireTick", type = 1, value = true, editable = true},
        {name = "doImmediateRespawn", type = 1, value = false, editable = true},
        {name = "doInsomnia", type = 1, value = true, editable = true},
        {name = "doMobLoot", type = 1, value = true, editable = true},
        {name = "doMobSpawning", type = 1, value = true, editable = true},
        {name = "doTileDrops", type = 1, value = true, editable = true},
        {name = "doWeatherCycle", type = 1, value = true, editable = true},
        {name = "drowningDamage", type = 1, value = true, editable = true},
        {name = "fallDamage", type = 1, value = true, editable = true},
        {name = "fireDamage", type = 1, value = true, editable = true},
        {name = "freezeDamage", type = 1, value = true, editable = true},
        {name = "functionCommandLimit", type = 2, value = 10000, editable = true},
        {name = "keepInventory", type = 1, value = false, editable = true},
        {name = "maxCommandChainLength", type = 2, value = 65536, editable = true},
        {name = "mobGriefing", type = 1, value = true, editable = true},
        {name = "naturalRegeneration", type = 1, value = true, editable = true},
        {name = "pvp", type = 1, value = true, editable = true},
        {name = "randomTickSpeed", type = 2, value = 1, editable = true},
        {name = "respawnBlocksExplode", type = 1, value = true, editable = true},
        {name = "sendCommandFeedback", type = 1, value = true, editable = true},
        {name = "showCoordinates", type = 1, value = false, editable = true},
        {name = "showDeathMessages", type = 1, value = true, editable = true},
        {name = "spawnRadius", type = 2, value = 5, editable = true},
        {name = "tntExplodes", type = 1, value = true, editable = true},
    }
    
    -- Block updates queue
    self.block_updates = {}
    
    -- Entities
    self.entities = {}
    
    -- Pending drops
    self.item_drops = {}
    
    return self
end

function World:initialize()
    -- Create world directories
    os.execute("mkdir -p " .. self.path)
    os.execute("mkdir -p " .. self.path .. "/db")
    os.execute("mkdir -p " .. self.path .. "/players")
    
    -- Initialize chunk generator
    self.generator = ChunkGenerator.new(self.seed, self.generator_type)
    
    -- Generate spawn chunks
    Logger.info(string.format("Generating spawn chunks for world '%s'...", self.name))
    for cx = -2, 2 do
        for cz = -2, 2 do
            self:getOrGenerateChunk(cx, cz)
        end
    end
    
    -- Find safe spawn
    self:findSafeSpawn()
end

function World:loadLevelDat()
    -- Initialize generator first
    self.generator = ChunkGenerator.new(self.seed, self.generator_type)
    
    -- Try to read level.dat (MCBE format - binary NBT)
    local path = self.path .. "/level.dat"
    local f = io.open(path, "rb")
    if not f then return end
    
    -- Skip 8 byte header (version + size)
    f:seek("set", 8)
    local data = f:read("*a")
    f:close()
    
    if not data or #data < 10 then return end
    
    -- Basic NBT parsing for key fields
    local seed = self:parseNBTField(data, "RandomSeed")
    local spawn_x = self:parseNBTField(data, "SpawnX")
    local spawn_y = self:parseNBTField(data, "SpawnY")
    local spawn_z = self:parseNBTField(data, "SpawnZ")
    local time = self:parseNBTField(data, "Time")
    local level_name = self:parseNBTField(data, "LevelName")
    
    if seed then self.seed = seed end
    if spawn_x then self.spawn_x = spawn_x end
    if spawn_y then self.spawn_y = spawn_y end
    if spawn_z then self.spawn_z = spawn_z end
    if time then self.time = time end
    if level_name then self.display_name = level_name end
    
    -- Reinit generator with correct seed
    self.generator = ChunkGenerator.new(self.seed, self.generator_type)
    
    Logger.info(string.format("Loaded level.dat for '%s' (seed: %d)", self.name, self.seed))
end

function World:parseNBTField(data, field_name)
    -- Very basic NBT field search
    local pos = 1
    while pos < #data - 10 do
        local tag_type = data:byte(pos)
        if tag_type == 0 then
            pos = pos + 1
        elseif tag_type == 3 then -- TAG_Int
            local name_len = data:byte(pos+1) * 256 + data:byte(pos+2)
            if name_len < 64 and pos + 2 + name_len < #data then
                local name = data:sub(pos+3, pos+2+name_len)
                if name == field_name then
                    local v = 0
                    for i = 0, 3 do
                        v = v + data:byte(pos + 3 + name_len + i) * (2^(i*8))
                    end
                    return v
                end
                pos = pos + 3 + name_len + 4
            else
                pos = pos + 1
            end
        elseif tag_type == 4 then -- TAG_Long (seed)
            local name_len = data:byte(pos+1) * 256 + data:byte(pos+2)
            if name_len < 64 and pos + 2 + name_len < #data then
                local name = data:sub(pos+3, pos+2+name_len)
                if name == field_name then
                    local v = 0
                    for i = 0, 7 do
                        v = v + data:byte(pos + 3 + name_len + i) * (2^(i*8))
                    end
                    return v
                end
                pos = pos + 3 + name_len + 8
            else
                pos = pos + 1
            end
        elseif tag_type == 8 then -- TAG_String
            local name_len = data:byte(pos+1) * 256 + data:byte(pos+2)
            if name_len < 64 and pos + 2 + name_len < #data then
                local name = data:sub(pos+3, pos+2+name_len)
                local val_len_pos = pos + 3 + name_len
                if val_len_pos + 2 < #data then
                    local val_len = data:byte(val_len_pos) * 256 + data:byte(val_len_pos+1)
                    if name == field_name then
                        return data:sub(val_len_pos+2, val_len_pos+1+val_len)
                    end
                    pos = val_len_pos + 2 + val_len
                else
                    pos = pos + 1
                end
            else
                pos = pos + 1
            end
        else
            pos = pos + 1
        end
    end
    return nil
end

function World:findSafeSpawn()
    -- Find a safe Y position at spawn
    local chunk = self:getOrGenerateChunk(0, 0)
    local y = 128
    
    -- Find first solid block from top
    for test_y = 120, 1, -1 do
        local block = chunk:getBlock(math.floor(self.spawn_x) % 16, test_y, math.floor(self.spawn_z) % 16)
        if block and block.id ~= 0 then
            self.spawn_y = test_y + 1
            break
        end
    end
end

function World:getOrGenerateChunk(cx, cz)
    local key = cx .. "," .. cz
    
    if self.chunks[key] then
        return self.chunks[key]
    end
    
    -- Try to load from disk
    local chunk = self:loadChunkFromDisk(cx, cz)
    
    if not chunk then
        -- Generate new chunk
        chunk = self:generateChunk(cx, cz)
    end
    
    self.chunks[key] = chunk
    
    -- Unload far chunks if too many loaded
    if self:getLoadedChunkCount() > self.max_loaded_chunks then
        self:unloadFarChunks()
    end
    
    return chunk
end

function World:generateChunk(cx, cz)
    local chunk = Chunk.new(cx, cz, self)
    
    if self.generator then
        self.generator:generate(chunk)
    else
        -- Fallback: flat world
        self:generateFlatChunk(chunk)
    end
    
    return chunk
end

function World:generateFlatChunk(chunk)
    -- Simple flat world: bedrock, stone, dirt, grass
    for x = 0, 15 do
        for z = 0, 15 do
            chunk:setBlock(x, 0, z, 7, 0)  -- Bedrock
            for y = 1, 3 do
                chunk:setBlock(x, y, z, 1, 0)  -- Stone
            end
            for y = 4, 5 do
                chunk:setBlock(x, y, z, 3, 0)  -- Dirt
            end
            chunk:setBlock(x, 6, z, 2, 0)  -- Grass
        end
    end
    
    chunk:setBiome(1) -- Plains biome everywhere
end

function World:loadChunkFromDisk(cx, cz)
    -- Try LevelDB format (MCBE default)
    local leveldb_ok, leveldb = pcall(require, "leveldb")
    if leveldb_ok then
        return self:loadChunkLevelDB(cx, cz, leveldb)
    end
    
    -- Fallback: try custom binary format
    local path = string.format("%s/db/chunk_%d_%d.bin", self.path, cx, cz)
    local f = io.open(path, "rb")
    if not f then return nil end
    
    local data = f:read("*a")
    f:close()
    
    if not data or #data < 10 then return nil end
    
    local chunk = Chunk.new(cx, cz, self)
    chunk:deserialize(data)
    return chunk
end

function World:loadChunkLevelDB(cx, cz, leveldb)
    -- MCBE LevelDB chunk key format
    local function buildKey(cx, cz, tag, sub_chunk)
        local buf = BitBuffer.new()
        buf:writeLInt(cx)
        buf:writeLInt(cz)
        buf:writeByte(tag)
        if sub_chunk then
            buf:writeByte(sub_chunk)
        end
        return buf:tostring()
    end
    
    local ok, db = pcall(leveldb.open, self.path .. "/db")
    if not ok then return nil end
    
    local chunk = Chunk.new(cx, cz, self)
    local has_data = false
    
    -- Try to load sub-chunks (tag 0x2F = SubChunkPrefix)
    for y = 0, 15 do
        local key = buildKey(cx, cz, 0x2F, y)
        local ok2, data = pcall(db.get, db, key)
        if ok2 and data then
            chunk:loadSubChunkData(y, data)
            has_data = true
        end
    end
    
    -- Load 2D data (biomes, etc.) - tag 0x2D
    local key2d = buildKey(cx, cz, 0x2D)
    local ok3, data2d = pcall(db.get, db, key2d)
    if ok3 and data2d then
        chunk:load2DData(data2d)
    end
    
    pcall(db.close, db)
    
    if has_data then return chunk end
    return nil
end

function World:saveChunkToDisk(chunk)
    local path = string.format("%s/db/chunk_%d_%d.bin", self.path, chunk.cx, chunk.cz)
    local f = io.open(path, "wb")
    if f then
        f:write(chunk:serialize())
        f:close()
    end
end

function World:getBlock(x, y, z)
    local cx = math.floor(x / 16)
    local cz = math.floor(z / 16)
    local lx = x % 16
    local lz = z % 16
    
    local chunk = self:getOrGenerateChunk(cx, cz)
    return chunk:getBlock(lx, y, lz)
end

function World:setBlock(x, y, z, block_id, block_data)
    local cx = math.floor(x / 16)
    local cz = math.floor(z / 16)
    local lx = x % 16
    local lz = z % 16
    
    local chunk = self:getOrGenerateChunk(cx, cz)
    local old_block = chunk:getBlock(lx, y, lz)
    
    chunk:setBlock(lx, y, lz, block_id, block_data or 0)
    
    -- Fire event
    self.server.events:fire("BlockUpdate", {
        world = self,
        x = x, y = y, z = z,
        old_block = old_block,
        new_block = {id = block_id, data = block_data or 0}
    })
    
    -- Send update to nearby players
    self:broadcastBlockUpdate(x, y, z, block_id, block_data or 0)
end

function World:broadcastBlockUpdate(x, y, z, block_id, block_data)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    
    buf:writeZigZag(x)
    buf:writeVarInt(y)
    buf:writeZigZag(z)
    buf:writeVarInt(block_id)
    buf:writeVarInt(block_data)
    buf:writeByte(0) -- flags
    buf:writeVarInt(0) -- data layer
    
    -- Send to all players in this world
    for _, player in ipairs(self:getPlayers()) do
        local dx = math.abs(player.x - x)
        local dz = math.abs(player.z - z)
        if dx <= player.view_distance * 16 and dz <= player.view_distance * 16 then
            self.server.protocol:sendPacket(player, PID.UPDATE_BLOCK, buf)
        end
    end
end

function World:dropItem(x, y, z, item)
    table.insert(self.item_drops, {
        x = x + (math.random() - 0.5) * 0.5,
        y = y + 0.1,
        z = z + (math.random() - 0.5) * 0.5,
        vx = (math.random() - 0.5) * 0.2,
        vy = 0.3,
        vz = (math.random() - 0.5) * 0.2,
        item = item,
        age = 0,
        pickup_delay = 10
    })
end

function World:getSpawnPoint()
    return self.spawn_x, self.spawn_y, self.spawn_z
end

function World:setSpawnPoint(x, y, z)
    self.spawn_x = x
    self.spawn_y = y
    self.spawn_z = z
end

function World:getGameRules()
    return self.game_rules
end

function World:setGameRule(name, value)
    for _, rule in ipairs(self.game_rules) do
        if rule.name == name then
            rule.value = value
            -- Broadcast to players
            self:broadcastGameRuleChange(name, rule.type, value)
            return true
        end
    end
    return false
end

function World:getGameRule(name)
    for _, rule in ipairs(self.game_rules) do
        if rule.name == name then
            return rule.value
        end
    end
    return nil
end

function World:broadcastGameRuleChange(name, type_, value)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeVarInt(1) -- count
    buf:writeString(name)
    buf:writeBool(true) -- editable
    buf:writeVarInt(type_)
    if type_ == 1 then buf:writeBool(value)
    elseif type_ == 2 then buf:writeVarInt(value)
    elseif type_ == 3 then buf:writeFloat(value)
    end
    
    for _, player in ipairs(self:getPlayers()) do
        self.server.protocol:sendPacket(player, PID.GAME_RULES_CHANGED, buf)
    end
end

function World:getPlayers()
    local players = {}
    for _, player in ipairs(self.server.players:getAll()) do
        if player.world == self then
            table.insert(players, player)
        end
    end
    return players
end

function World:getPlayerCount()
    return #self:getPlayers()
end

function World:getLoadedChunkCount()
    local c = 0
    for _ in pairs(self.chunks) do c = c + 1 end
    return c
end

function World:getDimensionCount()
    -- Number of sub-chunks (vertical sections)
    return 16
end

function World:unloadFarChunks()
    -- Simple strategy: unload chunks with no nearby players
    local players = self:getPlayers()
    local to_unload = {}
    
    for key, chunk in pairs(self.chunks) do
        local nearby = false
        for _, player in ipairs(players) do
            local pcx = math.floor(player.x / 16)
            local pcz = math.floor(player.z / 16)
            if math.abs(chunk.cx - pcx) <= player.view_distance + 2 and
               math.abs(chunk.cz - pcz) <= player.view_distance + 2 then
                nearby = true
                break
            end
        end
        if not nearby then
            table.insert(to_unload, key)
        end
    end
    
    -- Save and unload
    for _, key in ipairs(to_unload) do
        local chunk = self.chunks[key]
        if chunk and chunk.modified then
            self:saveChunkToDisk(chunk)
        end
        self.chunks[key] = nil
    end
end

function World:tick(ticks)
    -- Day/night cycle
    if self.day_cycle and ticks % 2 == 0 then
        self.time = (self.time + 1) % 24000
        
        -- Broadcast time to players every 200 ticks
        if ticks % 200 == 0 then
            self:broadcastTime()
        end
    end
    
    -- Random tick speed
    local rts = self:getGameRule("randomTickSpeed") or 1
    if rts > 0 and ticks % 4 == 0 then
        self:doRandomTicks(rts)
    end
    
    -- Process block updates
    self:processBlockUpdates()
    
    -- Mob spawning
    if ticks % 40 == 0 and self:getGameRule("doMobSpawning") ~= false then
        -- self:spawnMobs()
    end
    
    -- Item drop physics
    self:tickItemDrops()
end

function World:broadcastTime()
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local buf = BitBuffer.new()
    buf:writeVarInt(self.time)
    
    for _, player in ipairs(self:getPlayers()) do
        self.server.protocol:sendPacket(player, PID.SET_TIME, buf)
    end
end

function World:doRandomTicks(speed)
    -- Select random chunks to tick
    local keys = {}
    for key in pairs(self.chunks) do
        table.insert(keys, key)
    end
    
    local num_chunks = math.min(#keys, 10) -- max 10 chunks per tick
    for i = 1, num_chunks do
        local idx = math.random(#keys)
        local chunk = self.chunks[keys[idx]]
        if chunk then
            chunk:randomTick(speed)
        end
    end
end

function World:processBlockUpdates()
    local updates = self.block_updates
    self.block_updates = {}
    
    for _, update in ipairs(updates) do
        local block = self:getBlock(update.x, update.y, update.z)
        if block then
            -- Process block update logic
            local BlockRegistry = require("block.BlockRegistry")
            local block_def = BlockRegistry:get(block.id)
            if block_def and block_def.onUpdate then
                block_def:onUpdate(self, update.x, update.y, update.z)
            end
        end
    end
end

function World:tickItemDrops()
    local to_remove = {}
    
    for i, drop in ipairs(self.item_drops) do
        drop.age = drop.age + 1
        
        -- Physics
        drop.vy = drop.vy - 0.04 -- gravity
        drop.x = drop.x + drop.vx
        drop.y = drop.y + drop.vy
        drop.z = drop.z + drop.vz
        drop.vx = drop.vx * 0.98
        drop.vz = drop.vz * 0.98
        
        -- Ground collision
        local block_below = self:getBlock(math.floor(drop.x), math.floor(drop.y), math.floor(drop.z))
        if block_below and block_below.id ~= 0 then
            drop.y = math.floor(drop.y) + 1
            drop.vy = 0
        end
        
        -- Despawn after 5 minutes (6000 ticks)
        if drop.age > 6000 then
            table.insert(to_remove, i)
        end
        
        -- Check pickup
        if drop.pickup_delay <= 0 then
            for _, player in ipairs(self:getPlayers()) do
                local dx = player.x - drop.x
                local dy = player.y - drop.y
                local dz = player.z - drop.z
                if math.sqrt(dx*dx + dy*dy + dz*dz) <= 1.5 then
                    -- Pickup!
                    if player.inventory:addItem(drop.item) then
                        table.insert(to_remove, i)
                        break
                    end
                end
            end
        else
            drop.pickup_delay = drop.pickup_delay - 1
        end
    end
    
    -- Remove in reverse order
    table.sort(to_remove, function(a,b) return a > b end)
    for _, i in ipairs(to_remove) do
        table.remove(self.item_drops, i)
    end
end

function World:save()
    Logger.info(string.format("Saving world '%s'...", self.name))
    
    -- Save all modified chunks
    local saved = 0
    for key, chunk in pairs(self.chunks) do
        if chunk.modified then
            self:saveChunkToDisk(chunk)
            chunk.modified = false
            saved = saved + 1
        end
    end
    
    -- Save level.dat
    self:saveLevelDat()
    
    Logger.info(string.format("Saved world '%s' (%d chunks)", self.name, saved))
end

function World:saveLevelDat()
    -- Write a minimal level.dat
    local path = self.path .. "/level.dat"
    -- Write binary NBT header + basic data
    local f = io.open(path, "wb")
    if not f then return end
    
    -- Header (8 bytes: version=8, data size)
    local data = self:buildMinimalNBT()
    local header = BitBuffer.new()
    header:writeLInt(8) -- version
    header:writeLInt(#data)
    
    f:write(header:tostring())
    f:write(data)
    f:close()
end

function World:buildMinimalNBT()
    -- Build minimal NBT compound for level.dat
    local buf = BitBuffer.new()
    
    local function writeTag(tag_type, name, value_writer)
        buf:writeByte(tag_type)
        buf:writeLShort(#name)
        buf:writeBytes(name)
        value_writer()
    end
    
    -- TAG_Compound start
    buf:writeByte(10)
    buf:writeLShort(0)
    
    -- StorageVersion
    buf:writeByte(3) -- TAG_Int
    buf:writeLShort(15)
    buf:writeBytes("StorageVersion")
    buf:writeLInt(9)
    
    -- RandomSeed
    buf:writeByte(4) -- TAG_Long
    buf:writeLShort(10)
    buf:writeBytes("RandomSeed")
    buf:writeLInt64(self.seed)
    
    -- SpawnX, SpawnY, SpawnZ
    buf:writeByte(3) buf:writeLShort(6) buf:writeBytes("SpawnX") buf:writeLInt(math.floor(self.spawn_x))
    buf:writeByte(3) buf:writeLShort(6) buf:writeBytes("SpawnY") buf:writeLInt(math.floor(self.spawn_y))
    buf:writeByte(3) buf:writeLShort(6) buf:writeBytes("SpawnZ") buf:writeLInt(math.floor(self.spawn_z))
    
    -- Time
    buf:writeByte(4) buf:writeLShort(4) buf:writeBytes("Time") buf:writeLInt64(self.time)
    
    -- LevelName
    local name = self.display_name or self.name
    buf:writeByte(8) buf:writeLShort(9) buf:writeBytes("LevelName")
    buf:writeLShort(#name) buf:writeBytes(name)
    
    -- TAG_End
    buf:writeByte(0)
    
    return buf:tostring()
end

return World
