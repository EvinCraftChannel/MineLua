-- MineLua Chunk
-- 16x256x16 (or 16x384x16 for 1.18+) block storage

local BitBuffer = require("utils.BitBuffer")

local Chunk = {}
Chunk.__index = Chunk

-- SubChunk version
local SUB_CHUNK_VERSION = 8

function Chunk.new(cx, cz, world)
    local self = setmetatable({}, Chunk)
    
    self.cx = cx
    self.cz = cz
    self.world = world
    self.modified = false
    
    -- 16 sub-chunks (0-15), each 16x16x16 blocks
    -- For 1.18+ support: 24 sub-chunks (-4 to 19)
    self.sub_chunks = {}
    
    -- Biome data: 256 values (16x16)
    self.biomes = {}
    for i = 1, 256 do
        self.biomes[i] = 1 -- plains by default
    end
    
    -- Height map
    self.height_map = {}
    for i = 1, 256 do
        self.height_map[i] = 0
    end
    
    -- Block entities (chests, signs, etc.)
    self.block_entities = {}
    
    return self
end

function Chunk:getOrCreateSubChunk(sy)
    if not self.sub_chunks[sy] then
        self.sub_chunks[sy] = SubChunk.new(sy)
    end
    return self.sub_chunks[sy]
end

function Chunk:getBlock(x, y, z)
    local sy = math.floor(y / 16)
    local ly = y % 16
    
    if sy < 0 or sy > 15 then
        return {id = 0, data = 0} -- out of bounds
    end
    
    local sub = self.sub_chunks[sy]
    if not sub then
        return {id = 0, data = 0} -- air
    end
    
    local id, data = sub:getBlock(x, ly, z)
    return {id = id, data = data}
end

function Chunk:setBlock(x, y, z, block_id, block_data)
    local sy = math.floor(y / 16)
    local ly = y % 16
    
    if sy < 0 or sy > 15 then return end
    
    local sub = self:getOrCreateSubChunk(sy)
    sub:setBlock(x, ly, z, block_id, block_data or 0)
    
    -- Update height map
    local hm_idx = z * 16 + x + 1
    if block_id ~= 0 then
        if y > self.height_map[hm_idx] then
            self.height_map[hm_idx] = y
        end
    end
    
    self.modified = true
end

function Chunk:setBiome(biome_id, x, z)
    if x and z then
        local idx = z * 16 + x + 1
        self.biomes[idx] = biome_id
    else
        -- Set entire chunk biome
        for i = 1, 256 do
            self.biomes[i] = biome_id
        end
    end
    self.modified = true
end

function Chunk:getBiome(x, z)
    local idx = z * 16 + x + 1
    return self.biomes[idx] or 1
end

function Chunk:getBiomeData()
    -- 256 biome bytes
    local data = {}
    for _, biome in ipairs(self.biomes) do
        table.insert(data, string.char(biome & 0xFF))
    end
    return table.concat(data)
end

function Chunk:getSubChunks()
    local list = {}
    for sy = 0, 15 do
        if self.sub_chunks[sy] then
            table.insert(list, self.sub_chunks[sy])
        else
            table.insert(list, SubChunk.new(sy)) -- empty sub-chunk
        end
    end
    return list
end

function Chunk:getDimensionCount()
    return 16 -- 16 sub-chunks for standard height
end

function Chunk:getBlockEntities()
    return self.block_entities
end

function Chunk:addBlockEntity(be)
    table.insert(self.block_entities, be)
    self.modified = true
end

function Chunk:getBlockEntity(x, y, z)
    for _, be in ipairs(self.block_entities) do
        if be.x == x and be.y == y and be.z == z then
            return be
        end
    end
    return nil
end

function Chunk:randomTick(speed)
    -- Random tick for each sub-chunk
    for sy, sub in pairs(self.sub_chunks) do
        for _ = 1, speed do
            local x = math.random(0, 15)
            local y = math.random(0, 15)
            local z = math.random(0, 15)
            local id, data = sub:getBlock(x, y, z)
            if id ~= 0 then
                local BlockRegistry = require("block.BlockRegistry")
                local block_def = BlockRegistry:get(id)
                if block_def and block_def.onRandomTick then
                    local world_y = sy * 16 + y
                    block_def:onRandomTick(
                        self.world,
                        self.cx * 16 + x,
                        world_y,
                        self.cz * 16 + z,
                        data
                    )
                end
            end
        end
    end
end

function Chunk:serialize()
    local buf = BitBuffer.new()
    
    -- Chunk header
    buf:writeLInt(self.cx)
    buf:writeLInt(self.cz)
    buf:writeByte(16) -- sub-chunk count
    
    -- Sub-chunks
    for sy = 0, 15 do
        local sub = self.sub_chunks[sy]
        if sub then
            buf:writeByte(1) -- has data
            buf:writeBytes(sub:serialize())
        else
            buf:writeByte(0) -- empty
        end
    end
    
    -- Biomes
    buf:writeBytes(self:getBiomeData())
    
    -- Height map
    for _, h in ipairs(self.height_map) do
        buf:writeByte(math.min(255, h))
    end
    
    return buf:tostring()
end

function Chunk:deserialize(data)
    local buf = BitBuffer.new(data)
    
    if buf:remaining() < 8 then return end
    
    local cx = buf:readLInt()
    local cz = buf:readLInt()
    
    if cx ~= self.cx or cz ~= self.cz then
        -- Different chunk coordinates, skip
        return
    end
    
    local sub_count = buf:readByte()
    
    for sy = 0, sub_count - 1 do
        if buf:remaining() < 1 then break end
        local has_data = buf:readByte()
        if has_data == 1 then
            local sub = SubChunk.new(sy)
            sub:deserialize(buf)
            self.sub_chunks[sy] = sub
        end
    end
    
    -- Biomes
    if buf:remaining() >= 256 then
        for i = 1, 256 do
            self.biomes[i] = buf:readByte()
        end
    end
end

function Chunk:loadSubChunkData(sy, data)
    local sub = SubChunk.new(sy)
    local buf = BitBuffer.new(data)
    
    local version = buf:readByte()
    
    if version == SUB_CHUNK_VERSION then
        -- Paletted storage
        local storage_count = buf:readByte()
        
        for s = 1, storage_count do
            local bits_per_block = buf:readByte() >> 1
            
            if bits_per_block == 0 then
                -- All same block
                local block_id = buf:readLInt()
                for x = 0, 15 do
                    for y = 0, 15 do
                        for z = 0, 15 do
                            sub:setBlock(x, y, z, block_id, 0)
                        end
                    end
                end
            else
                -- Read palette indices
                local indices_per_word = math.floor(32 / bits_per_block)
                local num_words = math.ceil(4096 / indices_per_word)
                local indices = {}
                
                for w = 1, num_words do
                    if buf:remaining() < 4 then break end
                    local word = buf:readLInt()
                    for i = 0, indices_per_word - 1 do
                        local mask = (1 << bits_per_block) - 1
                        local idx = (word >> (bits_per_block * i)) & mask
                        table.insert(indices, idx)
                    end
                end
                
                -- Read palette
                if buf:remaining() < 4 then break end
                local palette_size = buf:readLInt()
                local palette = {}
                for p = 1, palette_size do
                    if buf:remaining() < 4 then break end
                    -- Read block state NBT (simplified - just read ID)
                    local block_id = buf:readLInt() -- simplified
                    table.insert(palette, block_id)
                end
                
                -- Apply indices to blocks
                local block_idx = 1
                for x = 0, 15 do
                    for z = 0, 15 do
                        for y = 0, 15 do
                            local palette_idx = (indices[block_idx] or 0) + 1
                            local block_id = palette[palette_idx] or 0
                            sub:setBlock(x, y, z, block_id, 0)
                            block_idx = block_idx + 1
                        end
                    end
                end
            end
            
            if s == 1 then break end -- Only read first storage layer for now
        end
    else
        -- Legacy format
        for x = 0, 15 do
            for z = 0, 15 do
                for y = 0, 15 do
                    if buf:remaining() < 1 then break end
                    sub:setBlock(x, y, z, buf:readByte(), 0)
                end
            end
        end
    end
    
    self.sub_chunks[sy] = sub
end

function Chunk:load2DData(data)
    if #data < 256 then return end
    for i = 1, 256 do
        self.biomes[i] = data:byte(i)
    end
end

-- ==================== SubChunk ====================

SubChunk = {}
SubChunk.__index = SubChunk

function SubChunk.new(sy)
    local self = setmetatable({}, SubChunk)
    self.sy = sy
    -- Compact block storage: flat array of 4096 block IDs + 4096 block data nibbles
    self.blocks = {} -- index -> block_id (0 = air)
    self.block_data = {} -- index -> data nibble
    return self
end

function SubChunk:blockIndex(x, y, z)
    return y * 256 + z * 16 + x + 1
end

function SubChunk:getBlock(x, y, z)
    local idx = self:blockIndex(x, y, z)
    return self.blocks[idx] or 0, self.block_data[idx] or 0
end

function SubChunk:setBlock(x, y, z, id, data)
    local idx = self:blockIndex(x, y, z)
    self.blocks[idx] = id
    self.block_data[idx] = data or 0
end

function SubChunk:serialize()
    -- Serialize as paletted sub-chunk (version 8)
    local buf = BitBuffer.new()
    buf:writeByte(SUB_CHUNK_VERSION)
    buf:writeByte(1) -- 1 storage layer
    
    -- Build palette
    local palette_map = {}
    local palette = {}
    
    for idx = 1, 4096 do
        local id = self.blocks[idx] or 0
        if not palette_map[id] then
            palette_map[id] = #palette
            table.insert(palette, id)
        end
    end
    
    -- Determine bits per block
    local palette_size = #palette
    local bits_per_block = 1
    while (1 << bits_per_block) < palette_size do
        bits_per_block = bits_per_block + 1
    end
    bits_per_block = math.max(1, bits_per_block)
    
    buf:writeByte(bits_per_block << 1) -- flags
    
    -- Write indices
    local indices_per_word = math.floor(32 / bits_per_block)
    local word = 0
    local bit_pos = 0
    local written = 0
    
    for x = 0, 15 do
        for z = 0, 15 do
            for y = 0, 15 do
                local idx = self:blockIndex(x, y, z)
                local id = self.blocks[idx] or 0
                local palette_idx = palette_map[id] or 0
                
                word = word | (palette_idx << bit_pos)
                bit_pos = bit_pos + bits_per_block
                written = written + 1
                
                if bit_pos >= 32 then
                    buf:writeLInt(word)
                    word = 0
                    bit_pos = 0
                end
            end
        end
    end
    
    if bit_pos > 0 then
        buf:writeLInt(word)
    end
    
    -- Write palette
    buf:writeLInt(palette_size)
    for _, id in ipairs(palette) do
        -- Write block state NBT (simplified)
        buf:writeLInt(id)
    end
    
    return buf:tostring()
end

function SubChunk:deserialize(buf)
    -- Read our custom format
    for idx = 1, 4096 do
        if buf:remaining() < 2 then break end
        self.blocks[idx] = buf:readShort()
        self.block_data[idx] = buf:readByte()
    end
end

function SubChunk:isEmpty()
    for _, v in pairs(self.blocks) do
        if v and v ~= 0 then return false end
    end
    return true
end

return Chunk
