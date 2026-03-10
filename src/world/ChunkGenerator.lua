-- MineLua Chunk Generator
-- Procedural world generation with noise-based terrain

local ChunkGenerator = {}
ChunkGenerator.__index = ChunkGenerator

-- Block IDs (full MCBE registry excerpt)
ChunkGenerator.BLOCKS = {
    AIR = 0,
    STONE = 1,
    GRASS = 2,
    DIRT = 3,
    COBBLESTONE = 4,
    WOOD_PLANKS = 5,
    SAPLING = 6,
    BEDROCK = 7,
    WATER = 8,
    STATIONARY_WATER = 9,
    LAVA = 10,
    STATIONARY_LAVA = 11,
    SAND = 12,
    GRAVEL = 13,
    GOLD_ORE = 14,
    IRON_ORE = 15,
    COAL_ORE = 16,
    LOG = 17,
    LEAVES = 18,
    SPONGE = 19,
    GLASS = 20,
    LAPIS_ORE = 21,
    LAPIS_BLOCK = 22,
    DISPENSER = 23,
    SANDSTONE = 24,
    NOTEBLOCK = 25,
    BED = 26,
    POWERED_RAIL = 27,
    DETECTOR_RAIL = 28,
    WEB = 30,
    TALL_GRASS = 31,
    DEAD_SHRUB = 32,
    WOOL = 35,
    YELLOW_FLOWER = 37,
    RED_FLOWER = 38,
    BROWN_MUSHROOM = 39,
    RED_MUSHROOM = 40,
    GOLD_BLOCK = 41,
    IRON_BLOCK = 42,
    DOUBLE_STONE_SLAB = 43,
    STONE_SLAB = 44,
    BRICK = 45,
    TNT = 46,
    BOOKSHELF = 47,
    MOSSY_COBBLESTONE = 48,
    OBSIDIAN = 49,
    TORCH = 50,
    FIRE = 51,
    MOB_SPAWNER = 52,
    OAK_STAIRS = 53,
    CHEST = 54,
    DIAMOND_ORE = 56,
    DIAMOND_BLOCK = 57,
    WORKBENCH = 58,
    FARMLAND = 60,
    FURNACE = 61,
    SIGN = 63,
    DOOR = 64,
    LADDER = 65,
    RAIL = 66,
    STONE_STAIRS = 67,
    WALL_SIGN = 68,
    LEVER = 69,
    STONE_PRESSURE_PLATE = 70,
    WOOD_PRESSURE_PLATE = 72,
    REDSTONE_ORE = 73,
    LIT_REDSTONE_ORE = 74,
    REDSTONE_TORCH = 76,
    STONE_BUTTON = 77,
    SNOW_LAYER = 78,
    ICE = 79,
    SNOW = 80,
    CACTUS = 81,
    CLAY = 82,
    SUGAR_CANE = 83,
    FENCE = 85,
    PUMPKIN = 86,
    NETHERRACK = 87,
    SOUL_SAND = 88,
    GLOWSTONE = 89,
    PORTAL = 90,
    LIT_PUMPKIN = 91,
    CAKE = 92,
    TRAPDOOR = 96,
    MONSTER_EGG = 97,
    STONEBRICK = 98,
    BROWN_MUSHROOM_BLOCK = 99,
    RED_MUSHROOM_BLOCK = 100,
    IRON_BARS = 101,
    GLASS_PANE = 102,
    MELON = 103,
    MELON_STEM = 105,
    VINE = 106,
    FENCE_GATE = 107,
    BRICK_STAIRS = 108,
    STONE_BRICK_STAIRS = 109,
    MYCELIUM = 110,
    WATERLILY = 111,
    NETHER_BRICK = 112,
    NETHER_BRICK_FENCE = 113,
    NETHER_BRICK_STAIRS = 114,
    ENCHANTMENT_TABLE = 116,
    BREWING_STAND = 117,
    END_PORTAL = 120,
    END_STONE = 121,
    DRAGON_EGG = 122,
    REDSTONE_LAMP = 123,
    LIT_REDSTONE_LAMP = 124,
    WOODEN_SLAB = 126,
    SANDSTONE_STAIRS = 128,
    EMERALD_ORE = 129,
    ENDER_CHEST = 130,
    TRIPWIRE_HOOK = 131,
    TRIPWIRE = 132,
    EMERALD_BLOCK = 133,
    SPRUCE_STAIRS = 134,
    BIRCH_STAIRS = 135,
    JUNGLE_STAIRS = 136,
    COMMAND_BLOCK = 137,
    BEACON = 138,
    COBBLESTONE_WALL = 139,
    FLOWER_POT = 140,
    CARROTS = 141,
    POTATOES = 142,
    WOOD_BUTTON = 143,
    SKULL = 144,
    ANVIL = 145,
    TRAPPED_CHEST = 146,
    HEAVY_WEIGHTED_PRESSURE_PLATE = 147,
    LIGHT_WEIGHTED_PRESSURE_PLATE = 148,
    DAYLIGHT_DETECTOR = 151,
    REDSTONE_BLOCK = 152,
    QUARTZ_ORE = 153,
    HOPPER = 154,
    QUARTZ_BLOCK = 155,
    QUARTZ_STAIRS = 156,
    ACTIVATOR_RAIL = 157,
    DROPPER = 158,
    HARDENED_CLAY = 172,
    COAL_BLOCK = 173,
    PACKED_ICE = 174,
    DOUBLE_PLANT = 175,
    STAINED_GLASS = 241,
    PODZOL = 243,
    BEETROOT = 244,
    STONECUTTER = 245,
    GLOWING_OBSIDIAN = 246,
    NETHER_REACTOR = 247,
    -- New blocks (1.16+)
    CRYING_OBSIDIAN = 248,
    NETHER_GOLD_ORE = 162,
    ANCIENT_DEBRIS = 526,
    CRIMSON_NYLIUM = 487,
    WARPED_NYLIUM = 488,
    SHROOMLIGHT = 485,
    -- 1.17+
    COPPER_ORE = 566,
    AMETHYST_BLOCK = 590,
    CALCITE = 589,
    TUFF = 588,
    DEEPSLATE = 633,
    DEEPSLATE_COAL_ORE = 634,
    DEEPSLATE_IRON_ORE = 635,
    DEEPSLATE_GOLD_ORE = 636,
    DEEPSLATE_DIAMOND_ORE = 637,
    DEEPSLATE_LAPIS_ORE = 638,
    DEEPSLATE_REDSTONE_ORE = 639,
    DEEPSLATE_COPPER_ORE = 640,
    DEEPSLATE_EMERALD_ORE = 641,
}

-- Biome IDs
ChunkGenerator.BIOMES = {
    OCEAN = 0,
    PLAINS = 1,
    DESERT = 2,
    MOUNTAINS = 3,
    FOREST = 4,
    TAIGA = 5,
    SWAMP = 6,
    RIVER = 7,
    NETHER = 8,
    THE_END = 9,
    FROZEN_OCEAN = 10,
    FROZEN_RIVER = 11,
    SNOWY_TUNDRA = 12,
    SNOWY_MOUNTAINS = 13,
    MUSHROOM_FIELDS = 14,
    BEACH = 16,
    DESERT_HILLS = 17,
    WOODED_HILLS = 18,
    TAIGA_HILLS = 19,
    MOUNTAIN_EDGE = 20,
    JUNGLE = 21,
    JUNGLE_HILLS = 22,
    BAMBOO_JUNGLE = 168,
    SAVANNA = 35,
    SAVANNA_PLATEAU = 36,
    BADLANDS = 37,
    DARK_FOREST = 29,
    SNOWY_TAIGA = 30,
    BIRCH_FOREST = 27,
    TALL_BIRCH_FOREST = 155,
    FLOWER_FOREST = 132,
    LUKEWARM_OCEAN = 44,
    WARM_OCEAN = 45,
    DEEP_OCEAN = 24,
    STONE_SHORE = 25,
}

function ChunkGenerator.new(seed, type_)
    local self = setmetatable({}, ChunkGenerator)
    self.seed = seed or 12345
    self.type = type_ or "default"
    
    -- Initialize noise tables
    self:initNoise()
    
    return self
end

function ChunkGenerator:initNoise()
    -- Permutation table for Perlin noise
    local p = {}
    math.randomseed(self.seed)
    for i = 0, 255 do
        p[i] = i
    end
    -- Shuffle
    for i = 255, 1, -1 do
        local j = math.random(0, i)
        p[i], p[j] = p[j], p[i]
    end
    -- Duplicate
    self.perm = {}
    for i = 0, 511 do
        self.perm[i] = p[i % 256]
    end
    
    -- Noise scale settings
    self.terrain_scale = 0.005
    self.detail_scale = 0.02
    self.biome_scale = 0.002
    self.cave_scale = 0.05
end

function ChunkGenerator:fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

function ChunkGenerator:lerp(t, a, b)
    return a + t * (b - a)
end

function ChunkGenerator:grad(hash, x, y, z)
    local h = hash & 15
    local u = h < 8 and x or y
    local v = h < 4 and y or (h == 12 or h == 14) and x or z
    return ((h & 1) == 0 and u or -u) + ((h & 2) == 0 and v or -v)
end

function ChunkGenerator:noise3d(x, y, z)
    local X = math.floor(x) & 255
    local Y = math.floor(y) & 255
    local Z = math.floor(z) & 255
    
    x = x - math.floor(x)
    y = y - math.floor(y)
    z = z - math.floor(z)
    
    local u = self:fade(x)
    local v = self:fade(y)
    local w = self:fade(z)
    
    local p = self.perm
    local A = (p[X] + Y) & 511
    local AA = (p[A] + Z) & 511
    local AB = (p[A + 1] + Z) & 511
    local B = (p[X + 1] + Y) & 511
    local BA = (p[B] + Z) & 511
    local BB = (p[B + 1] + Z) & 511
    
    return self:lerp(w,
        self:lerp(v,
            self:lerp(u, self:grad(p[AA], x, y, z),
                         self:grad(p[BA], x-1, y, z)),
            self:lerp(u, self:grad(p[AB], x, y-1, z),
                         self:grad(p[BB], x-1, y-1, z))),
        self:lerp(v,
            self:lerp(u, self:grad(p[AA+1], x, y, z-1),
                         self:grad(p[BA+1], x-1, y, z-1)),
            self:lerp(u, self:grad(p[AB+1], x, y-1, z-1),
                         self:grad(p[BB+1], x-1, y-1, z-1))))
end

function ChunkGenerator:octaveNoise(x, y, octaves, persistence, scale)
    local value = 0
    local amplitude = 1.0
    local total_amplitude = 0
    local frequency = scale
    
    for i = 1, octaves do
        value = value + self:noise3d(x * frequency, 0, y * frequency) * amplitude
        total_amplitude = total_amplitude + amplitude
        amplitude = amplitude * persistence
        frequency = frequency * 2
    end
    
    return value / total_amplitude
end

function ChunkGenerator:noise2d(x, z, scale)
    scale = scale or self.terrain_scale
    return self:octaveNoise(x, z, 4, 0.5, scale)
end

function ChunkGenerator:getBiomeAt(x, z)
    local temperature = self:noise2d(x, z, self.biome_scale * 0.7) 
    local humidity = self:noise2d(x + 1000, z + 1000, self.biome_scale)
    
    if temperature > 0.4 then
        if humidity < -0.2 then
            return self.BIOMES.DESERT
        elseif humidity < 0.2 then
            return self.BIOMES.SAVANNA
        else
            return self.BIOMES.JUNGLE
        end
    elseif temperature > 0.1 then
        if humidity < -0.1 then
            return self.BIOMES.PLAINS
        elseif humidity < 0.3 then
            return self.BIOMES.FOREST
        else
            return self.BIOMES.DARK_FOREST
        end
    elseif temperature > -0.2 then
        if humidity < 0.0 then
            return self.BIOMES.MOUNTAINS
        else
            return self.BIOMES.TAIGA
        end
    else
        return self.BIOMES.SNOWY_TUNDRA
    end
end

function ChunkGenerator:getTerrainHeight(world_x, world_z)
    local base = 64
    local noise = self:noise2d(world_x, world_z, self.terrain_scale)
    local detail = self:noise2d(world_x, world_z, self.detail_scale) * 0.3
    
    local height = base + (noise + detail) * 30
    return math.max(1, math.floor(height))
end

function ChunkGenerator:isCave(x, y, z)
    local n1 = self:noise3d(x * self.cave_scale, y * self.cave_scale * 0.5, z * self.cave_scale)
    local n2 = self:noise3d(x * self.cave_scale + 100, y * self.cave_scale * 0.5 + 100, z * self.cave_scale + 100)
    return math.abs(n1) < 0.08 and math.abs(n2) < 0.08
end

function ChunkGenerator:generate(chunk)
    if self.type == "flat" then
        return self:generateFlat(chunk)
    elseif self.type == "nether" then
        return self:generateNether(chunk)
    elseif self.type == "void" then
        return self:generateVoid(chunk)
    else
        return self:generateOverworld(chunk)
    end
end

function ChunkGenerator:generateOverworld(chunk)
    local B = self.BLOCKS
    local cx = chunk.cx
    local cz = chunk.cz
    
    for x = 0, 15 do
        for z = 0, 15 do
            local world_x = cx * 16 + x
            local world_z = cz * 16 + z
            
            local biome = self:getBiomeAt(world_x, world_z)
            chunk:setBiome(biome, x, z)
            
            local height = self:getTerrainHeight(world_x, world_z)
            local water_level = 62
            
            for y = 0, 255 do
                local block_id = B.AIR
                
                if y == 0 then
                    block_id = B.BEDROCK
                elseif y <= 4 then
                    -- More bedrock with noise
                    if math.random() < (5 - y) / 5 then
                        block_id = B.BEDROCK
                    else
                        block_id = B.STONE
                    end
                elseif y < height then
                    -- Underground
                    if self:isCave(world_x, y, world_z) and y > 5 then
                        block_id = B.AIR
                        -- Lava in deep caves
                        if y < 11 then
                            block_id = B.STATIONARY_LAVA
                        end
                    else
                        block_id = B.STONE
                        
                        -- Ore generation
                        block_id = self:generateOre(world_x, y, world_z, block_id)
                    end
                    
                elseif y == height then
                    -- Surface layer
                    if biome == self.BIOMES.DESERT then
                        block_id = B.SAND
                    elseif biome == self.BIOMES.SNOWY_TUNDRA then
                        block_id = B.GRASS
                    elseif y < water_level then
                        block_id = B.DIRT
                    else
                        block_id = B.GRASS
                    end
                    
                elseif y < height + 3 then
                    -- Sub-surface
                    if biome == self.BIOMES.DESERT then
                        block_id = B.SAND
                    else
                        block_id = B.DIRT
                    end
                    
                elseif y <= water_level and height < water_level then
                    -- Ocean/river
                    block_id = B.STATIONARY_WATER
                end
                
                if block_id ~= B.AIR then
                    chunk:setBlock(x, y, z, block_id, 0)
                end
            end
            
            -- Surface decorations
            if height > water_level then
                self:generateSurfaceFeatures(chunk, x, z, world_x, world_z, height, biome)
            end
            
            -- Snow layer in cold biomes
            if biome == self.BIOMES.SNOWY_TUNDRA and height > water_level then
                chunk:setBlock(x, height + 1, z, B.SNOW_LAYER, 0)
            end
        end
    end
    
    -- Tree generation
    self:generateTrees(chunk, cx, cz)
end

function ChunkGenerator:generateOre(x, y, z, default_block)
    local B = self.BLOCKS
    local r = math.random()
    
    if y < 16 and r < 0.003 then
        return B.DIAMOND_ORE
    elseif y < 32 and r < 0.005 then
        return B.GOLD_ORE
    elseif y < 64 and r < 0.008 then
        return B.IRON_ORE
    elseif y < 80 and r < 0.015 then
        return B.COAL_ORE
    elseif y < 32 and r < 0.004 and r > 0.003 then
        return B.REDSTONE_ORE
    elseif y < 32 and r < 0.002 then
        return B.LAPIS_ORE
    elseif y < 28 and r < 0.003 then
        return B.EMERALD_ORE
    elseif y < 64 and r < 0.006 then
        return B.COPPER_ORE
    end
    
    -- Deepslate at y < 16
    if y < 16 then
        return B.DEEPSLATE
    end
    
    return default_block
end

function ChunkGenerator:generateSurfaceFeatures(chunk, x, z, world_x, world_z, height, biome)
    local B = self.BLOCKS
    local r = math.random()
    
    if biome == self.BIOMES.PLAINS or biome == self.BIOMES.FOREST then
        if r < 0.05 then
            chunk:setBlock(x, height + 1, z, B.TALL_GRASS, 1)
        elseif r < 0.07 then
            chunk:setBlock(x, height + 1, z, B.YELLOW_FLOWER, 0)
        elseif r < 0.09 then
            chunk:setBlock(x, height + 1, z, B.RED_FLOWER, 0)
        end
    elseif biome == self.BIOMES.DESERT then
        if r < 0.02 then
            -- Cactus (1-3 tall)
            local cactus_height = math.random(1, 3)
            for cy = 1, cactus_height do
                chunk:setBlock(x, height + cy, z, B.CACTUS, 0)
            end
        elseif r < 0.03 then
            chunk:setBlock(x, height + 1, z, B.DEAD_SHRUB, 0)
        end
    elseif biome == self.BIOMES.JUNGLE then
        if r < 0.15 then
            chunk:setBlock(x, height + 1, z, B.TALL_GRASS, 2)
        end
    end
end

function ChunkGenerator:generateTrees(chunk, cx, cz)
    local B = self.BLOCKS
    
    -- Use seeded random for consistent tree placement
    local chunk_seed = (cx * 374761393) ~ (cz * 1234567891)
    math.randomseed(self.seed ~ chunk_seed)
    
    local tree_count = math.random(1, 4)
    
    for _ = 1, tree_count do
        local tx = math.random(2, 13)
        local tz = math.random(2, 13)
        local world_x = cx * 16 + tx
        local world_z = cz * 16 + tz
        
        local biome = self:getBiomeAt(world_x, world_z)
        
        -- Only place trees in forest/plains biomes
        if biome == self.BIOMES.FOREST or 
           (biome == self.BIOMES.PLAINS and math.random() < 0.3) or
           biome == self.BIOMES.TAIGA then
            
            local height = self:getTerrainHeight(world_x, world_z)
            local block = chunk:getBlock(tx, height, tz)
            
            if block and block.id == B.GRASS then
                if biome == self.BIOMES.TAIGA then
                    self:generateSpruceTree(chunk, tx, height + 1, tz)
                else
                    self:generateOakTree(chunk, tx, height + 1, tz)
                end
            end
        end
    end
    
    -- Reset random
    math.randomseed(os.time())
end

function ChunkGenerator:generateOakTree(chunk, x, y, z)
    local B = self.BLOCKS
    local trunk_height = math.random(4, 6)
    
    -- Trunk
    for ty = 0, trunk_height - 1 do
        if y + ty < 256 then
            chunk:setBlock(x, y + ty, z, B.LOG, 0)
        end
    end
    
    -- Leaves
    for lx = -2, 2 do
        for lz = -2, 2 do
            for ly = trunk_height - 2, trunk_height + 1 do
                local bx = x + lx
                local by = y + ly
                local bz = z + lz
                if bx >= 0 and bx < 16 and bz >= 0 and bz < 16 and by < 256 then
                    local dist = math.abs(lx) + math.abs(lz)
                    if dist <= 2 and not (dist == 2 and ly == trunk_height + 1) then
                        local existing = chunk:getBlock(bx, by, bz)
                        if not existing or existing.id == 0 then
                            chunk:setBlock(bx, by, bz, B.LEAVES, 0)
                        end
                    end
                end
            end
        end
    end
end

function ChunkGenerator:generateSpruceTree(chunk, x, y, z)
    local B = self.BLOCKS
    local trunk_height = math.random(6, 10)
    
    -- Trunk
    for ty = 0, trunk_height - 1 do
        if y + ty < 256 then
            chunk:setBlock(x, y + ty, z, B.LOG, 1) -- spruce log
        end
    end
    
    -- Conical leaves
    for layer = 0, trunk_height - 1 do
        local radius = math.max(0, math.floor((trunk_height - layer) / 2.5))
        for lx = -radius, radius do
            for lz = -radius, radius do
                local by = y + layer + 1
                local bx = x + lx
                local bz = z + lz
                if bx >= 0 and bx < 16 and bz >= 0 and bz < 16 and by < 256 then
                    if math.abs(lx) + math.abs(lz) <= radius + 1 then
                        local existing = chunk:getBlock(bx, by, bz)
                        if not existing or existing.id == 0 then
                            chunk:setBlock(bx, by, bz, B.LEAVES, 1) -- spruce leaves
                        end
                    end
                end
            end
        end
    end
end

function ChunkGenerator:generateFlat(chunk)
    local B = self.BLOCKS
    
    for x = 0, 15 do
        for z = 0, 15 do
            chunk:setBlock(x, 0, z, B.BEDROCK, 0)
            chunk:setBlock(x, 1, z, B.STONE, 0)
            chunk:setBlock(x, 2, z, B.STONE, 0)
            chunk:setBlock(x, 3, z, B.DIRT, 0)
            chunk:setBlock(x, 4, z, B.GRASS, 0)
            chunk:setBiome(self.BIOMES.PLAINS, x, z)
        end
    end
end

function ChunkGenerator:generateNether(chunk)
    local B = self.BLOCKS
    
    for x = 0, 15 do
        for z = 0, 15 do
            local world_x = chunk.cx * 16 + x
            local world_z = chunk.cz * 16 + z
            chunk:setBiome(self.BIOMES.NETHER, x, z)
            
            for y = 0, 127 do
                if y == 0 or y == 127 then
                    chunk:setBlock(x, y, z, B.BEDROCK, 0)
                elseif y == 1 or y == 2 then
                    if math.random() < 0.5 then
                        chunk:setBlock(x, y, z, B.BEDROCK, 0)
                    else
                        chunk:setBlock(x, y, z, B.NETHERRACK, 0)
                    end
                elseif y < 32 then
                    chunk:setBlock(x, y, z, B.STATIONARY_LAVA, 0)
                else
                    local n = self:noise3d(world_x * 0.05, y * 0.05, world_z * 0.05)
                    if n > -0.1 then
                        chunk:setBlock(x, y, z, B.NETHERRACK, 0)
                    end
                end
            end
        end
    end
end

function ChunkGenerator:generateVoid(chunk)
    -- Void world - only a small platform at spawn
    local B = self.BLOCKS
    if chunk.cx == 0 and chunk.cz == 0 then
        for x = 0, 15 do
            for z = 0, 15 do
                chunk:setBlock(x, 64, z, B.GRASS, 0)
                chunk:setBlock(x, 63, z, B.DIRT, 0)
                chunk:setBlock(x, 62, z, B.STONE, 0)
            end
        end
    end
end

return ChunkGenerator
