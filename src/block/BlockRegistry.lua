-- MineLua Block Registry
-- Complete registry of all Minecraft Bedrock Edition blocks

local BlockRegistry = {}
BlockRegistry.__index = BlockRegistry

local instance = nil

function BlockRegistry.getInstance()
    if not instance then
        instance = setmetatable({}, BlockRegistry)
        instance.blocks = {}
        instance.blocks_by_name = {}
        instance.custom_blocks = {}
        instance:loadBlocks()
    end
    return instance
end

-- Shorthand
function BlockRegistry:get(id_or_name)
    if type(id_or_name) == "number" then
        return self.blocks[id_or_name]
    else
        local name = id_or_name:lower()
        if not name:find(":") then
            name = "minecraft:" .. name
        end
        return self.blocks_by_name[name]
    end
end

function BlockRegistry:register(block)
    if not block.id then
        error("Block must have an id")
    end
    self.blocks[block.id] = block
    if block.name then
        self.blocks_by_name[block.name] = block
    end
end

function BlockRegistry:registerCustom(block)
    table.insert(self.custom_blocks, block)
    self:register(block)
end

function BlockRegistry:getCustomBlocks()
    return self.custom_blocks
end

function BlockRegistry:loadBlocks()
    -- Load all blocks from data file
    local ok, blocks_data = pcall(require, "data.blocks")
    if ok and blocks_data then
        for _, b in ipairs(blocks_data) do
            self:register(b)
        end
    else
        -- Load built-in block definitions
        self:loadBuiltinBlocks()
    end
end

function BlockRegistry:loadBuiltinBlocks()
    -- Define all standard MCBE blocks
    local blocks = {
        -- Basic blocks
        {id=0,  name="minecraft:air",           display="Air",              hardness=0,    tool="none",   transparent=true},
        {id=1,  name="minecraft:stone",          display="Stone",            hardness=1.5,  tool="pickaxe", blast=6.0},
        {id=2,  name="minecraft:grass",          display="Grass Block",      hardness=0.6,  tool="shovel"},
        {id=3,  name="minecraft:dirt",           display="Dirt",             hardness=0.5,  tool="shovel"},
        {id=4,  name="minecraft:cobblestone",    display="Cobblestone",      hardness=2.0,  tool="pickaxe"},
        {id=5,  name="minecraft:planks",         display="Oak Planks",       hardness=2.0,  tool="axe",    flammable=true},
        {id=6,  name="minecraft:sapling",        display="Oak Sapling",      hardness=0,    tool="none",   transparent=true},
        {id=7,  name="minecraft:bedrock",        display="Bedrock",          hardness=-1,   tool="none"},
        {id=8,  name="minecraft:flowing_water",  display="Flowing Water",    hardness=100,  tool="none",   liquid=true, transparent=true},
        {id=9,  name="minecraft:water",          display="Water",            hardness=100,  tool="none",   liquid=true, transparent=true},
        {id=10, name="minecraft:flowing_lava",   display="Flowing Lava",     hardness=100,  tool="none",   liquid=true, light=15},
        {id=11, name="minecraft:lava",           display="Lava",             hardness=100,  tool="none",   liquid=true, light=15},
        {id=12, name="minecraft:sand",           display="Sand",             hardness=0.5,  tool="shovel", gravity=true},
        {id=13, name="minecraft:gravel",         display="Gravel",           hardness=0.6,  tool="shovel", gravity=true},
        {id=14, name="minecraft:gold_ore",       display="Gold Ore",         hardness=3.0,  tool="pickaxe",min_tier=2},
        {id=15, name="minecraft:iron_ore",       display="Iron Ore",         hardness=3.0,  tool="pickaxe",min_tier=1},
        {id=16, name="minecraft:coal_ore",       display="Coal Ore",         hardness=3.0,  tool="pickaxe",min_tier=0},
        {id=17, name="minecraft:log",            display="Oak Log",          hardness=2.0,  tool="axe",    flammable=true},
        {id=18, name="minecraft:leaves",         display="Oak Leaves",       hardness=0.2,  tool="shears", transparent=true, flammable=true},
        {id=19, name="minecraft:sponge",         display="Sponge",           hardness=0.6,  tool="any"},
        {id=20, name="minecraft:glass",          display="Glass",            hardness=0.3,  tool="none",   transparent=true},
        {id=21, name="minecraft:lapis_ore",      display="Lapis Lazuli Ore", hardness=3.0,  tool="pickaxe",min_tier=1},
        {id=22, name="minecraft:lapis_block",    display="Lapis Lazuli Block",hardness=3.0, tool="pickaxe",min_tier=1},
        {id=24, name="minecraft:sandstone",      display="Sandstone",        hardness=0.8,  tool="pickaxe"},
        {id=25, name="minecraft:noteblock",      display="Note Block",       hardness=0.8,  tool="axe"},
        {id=30, name="minecraft:web",            display="Cobweb",           hardness=4.0,  tool="shears"},
        {id=31, name="minecraft:tallgrass",      display="Grass",            hardness=0,    tool="shears", transparent=true},
        {id=32, name="minecraft:deadbush",       display="Dead Bush",        hardness=0,    tool="shears", transparent=true},
        {id=35, name="minecraft:wool",           display="White Wool",       hardness=0.8,  tool="shears", flammable=true},
        {id=37, name="minecraft:yellow_flower",  display="Dandelion",        hardness=0,    tool="any",    transparent=true},
        {id=38, name="minecraft:red_flower",     display="Poppy",            hardness=0,    tool="any",    transparent=true},
        {id=39, name="minecraft:brown_mushroom", display="Brown Mushroom",   hardness=0,    tool="any",    transparent=true, light=1},
        {id=40, name="minecraft:red_mushroom",   display="Red Mushroom",     hardness=0,    tool="any",    transparent=true},
        {id=41, name="minecraft:gold_block",     display="Gold Block",       hardness=3.0,  tool="pickaxe",min_tier=2},
        {id=42, name="minecraft:iron_block",     display="Iron Block",       hardness=5.0,  tool="pickaxe",min_tier=1},
        {id=45, name="minecraft:brick_block",    display="Bricks",           hardness=2.0,  tool="pickaxe"},
        {id=46, name="minecraft:tnt",            display="TNT",              hardness=0,    tool="any",    flammable=true},
        {id=47, name="minecraft:bookshelf",      display="Bookshelf",        hardness=1.5,  tool="axe",    flammable=true},
        {id=48, name="minecraft:mossy_cobblestone", display="Mossy Cobblestone", hardness=2.0, tool="pickaxe"},
        {id=49, name="minecraft:obsidian",       display="Obsidian",         hardness=50.0, tool="pickaxe",min_tier=3, blast=1200},
        {id=50, name="minecraft:torch",          display="Torch",            hardness=0,    tool="any",    transparent=true, light=14},
        {id=52, name="minecraft:mob_spawner",    display="Monster Spawner",  hardness=5.0,  tool="pickaxe"},
        {id=54, name="minecraft:chest",          display="Chest",            hardness=2.5,  tool="axe"},
        {id=56, name="minecraft:diamond_ore",    display="Diamond Ore",      hardness=3.0,  tool="pickaxe",min_tier=2},
        {id=57, name="minecraft:diamond_block",  display="Diamond Block",    hardness=5.0,  tool="pickaxe",min_tier=2},
        {id=58, name="minecraft:crafting_table", display="Crafting Table",   hardness=2.5,  tool="axe"},
        {id=60, name="minecraft:farmland",       display="Farmland",         hardness=0.6,  tool="shovel"},
        {id=61, name="minecraft:furnace",        display="Furnace",          hardness=3.5,  tool="pickaxe"},
        {id=73, name="minecraft:redstone_ore",   display="Redstone Ore",     hardness=3.0,  tool="pickaxe",min_tier=2},
        {id=79, name="minecraft:ice",            display="Ice",              hardness=0.5,  tool="pickaxe", transparent=true},
        {id=80, name="minecraft:snow",           display="Snow Block",       hardness=0.2,  tool="shovel"},
        {id=81, name="minecraft:cactus",         display="Cactus",           hardness=0.4,  tool="any"},
        {id=82, name="minecraft:clay",           display="Clay",             hardness=0.6,  tool="shovel"},
        {id=85, name="minecraft:fence",          display="Oak Fence",        hardness=2.0,  tool="axe",    flammable=true},
        {id=86, name="minecraft:pumpkin",        display="Pumpkin",          hardness=1.0,  tool="axe"},
        {id=87, name="minecraft:netherrack",     display="Netherrack",       hardness=0.4,  tool="pickaxe"},
        {id=88, name="minecraft:soul_sand",      display="Soul Sand",        hardness=0.5,  tool="shovel"},
        {id=89, name="minecraft:glowstone",      display="Glowstone",        hardness=0.3,  tool="any",    light=15},
        {id=98, name="minecraft:stonebrick",     display="Stone Bricks",     hardness=1.5,  tool="pickaxe"},
        {id=112, name="minecraft:nether_brick",  display="Nether Bricks",    hardness=2.0,  tool="pickaxe"},
        {id=116, name="minecraft:enchanting_table", display="Enchanting Table", hardness=5.0, tool="pickaxe", min_tier=1},
        {id=121, name="minecraft:end_stone",     display="End Stone",        hardness=3.0,  tool="pickaxe"},
        {id=129, name="minecraft:emerald_ore",   display="Emerald Ore",      hardness=3.0,  tool="pickaxe",min_tier=2},
        {id=133, name="minecraft:emerald_block", display="Emerald Block",    hardness=5.0,  tool="pickaxe",min_tier=2},
        {id=137, name="minecraft:command_block", display="Command Block",    hardness=-1,   tool="none"},
        {id=138, name="minecraft:beacon",        display="Beacon",           hardness=3.0,  tool="any",    transparent=true, light=15},
        {id=152, name="minecraft:redstone_block",display="Block of Redstone",hardness=5.0, tool="pickaxe",min_tier=1},
        {id=155, name="minecraft:quartz_block",  display="Block of Quartz",  hardness=0.8,  tool="pickaxe"},
        {id=168, name="minecraft:prismarine",    display="Prismarine",       hardness=1.5,  tool="pickaxe"},
        {id=169, name="minecraft:sea_lantern",   display="Sea Lantern",      hardness=0.3,  tool="any",    light=15},
        {id=170, name="minecraft:hay_block",     display="Hay Bale",         hardness=0.5,  tool="axe"},
        {id=172, name="minecraft:hardened_clay", display="Terracotta",       hardness=1.25, tool="pickaxe"},
        {id=173, name="minecraft:coal_block",    display="Block of Coal",    hardness=5.0,  tool="pickaxe",min_tier=0},
        {id=174, name="minecraft:packed_ice",    display="Packed Ice",       hardness=0.5,  tool="pickaxe"},
        -- 1.9+ blocks
        {id=198, name="minecraft:end_rod",       display="End Rod",          hardness=0,    tool="any",    transparent=true, light=14},
        {id=199, name="minecraft:chorus_plant",  display="Chorus Plant",     hardness=0.4,  tool="axe"},
        {id=200, name="minecraft:chorus_flower", display="Chorus Flower",    hardness=0.4,  tool="axe"},
        {id=201, name="minecraft:purpur_block",  display="Purpur Block",     hardness=1.5,  tool="pickaxe"},
        {id=206, name="minecraft:end_bricks",    display="End Stone Bricks", hardness=3.0,  tool="pickaxe"},
        -- 1.10+ blocks  
        {id=215, name="minecraft:red_nether_brick", display="Red Nether Bricks", hardness=2.0, tool="pickaxe"},
        {id=216, name="minecraft:bone_block",    display="Bone Block",       hardness=2.0,  tool="pickaxe"},
        {id=218, name="minecraft:observer",      display="Observer",         hardness=3.5,  tool="pickaxe"},
        -- 1.13+ blocks
        {id=235, name="minecraft:white_glazed_terracotta",  display="White Glazed Terracotta",  hardness=1.4, tool="pickaxe"},
        {id=251, name="minecraft:concrete",      display="White Concrete",   hardness=1.8,  tool="pickaxe"},
        {id=252, name="minecraft:concrete_powder",display="White Concrete Powder", hardness=0.5, tool="shovel", gravity=true},
        -- 1.16 Nether Update
        {id=469, name="minecraft:crimson_stem",  display="Crimson Stem",     hardness=2.0,  tool="axe"},
        {id=470, name="minecraft:warped_stem",   display="Warped Stem",      hardness=2.0,  tool="axe"},
        {id=471, name="minecraft:crimson_planks",display="Crimson Planks",   hardness=2.0,  tool="axe"},
        {id=472, name="minecraft:warped_planks", display="Warped Planks",    hardness=2.0,  tool="axe"},
        {id=478, name="minecraft:soul_fire",     display="Soul Fire",        hardness=0,    tool="any",    transparent=true, light=10},
        {id=479, name="minecraft:shroomlight",   display="Shroomlight",      hardness=1.0,  tool="hoe",    light=15},
        {id=480, name="minecraft:weeping_vines", display="Weeping Vines",    hardness=0,    tool="shears", transparent=true},
        {id=486, name="minecraft:ancient_debris",display="Ancient Debris",   hardness=30.0, tool="pickaxe",min_tier=3, blast=1200},
        {id=490, name="minecraft:crying_obsidian",display="Crying Obsidian", hardness=50.0, tool="pickaxe",min_tier=3, light=10},
        {id=491, name="minecraft:soul_soil",     display="Soul Soil",        hardness=0.5,  tool="shovel"},
        {id=495, name="minecraft:basalt",        display="Basalt",           hardness=1.25, tool="pickaxe"},
        {id=496, name="minecraft:polished_basalt",display="Polished Basalt", hardness=1.25, tool="pickaxe"},
        {id=497, name="minecraft:smooth_basalt", display="Smooth Basalt",    hardness=1.25, tool="pickaxe"},
        {id=499, name="minecraft:target",        display="Target",           hardness=0.5,  tool="hoe"},
        {id=500, name="minecraft:lodestone",     display="Lodestone",        hardness=3.5,  tool="pickaxe",min_tier=0},
        {id=501, name="minecraft:warped_wart_block", display="Warped Wart Block", hardness=1.0, tool="hoe"},
        {id=503, name="minecraft:nether_sprouts",display="Nether Sprouts",   hardness=0,    tool="shears", transparent=true},
        {id=507, name="minecraft:blackstone",    display="Blackstone",       hardness=1.5,  tool="pickaxe"},
        {id=508, name="minecraft:polished_blackstone", display="Polished Blackstone", hardness=2.0, tool="pickaxe"},
        {id=527, name="minecraft:gilded_blackstone", display="Gilded Blackstone", hardness=1.5, tool="pickaxe"},
        {id=535, name="minecraft:respawn_anchor",display="Respawn Anchor",   hardness=50.0, tool="pickaxe",min_tier=3},
        -- 1.17 Caves & Cliffs
        {id=540, name="minecraft:powder_snow",   display="Powder Snow",      hardness=0.25, tool="shovel"},
        {id=541, name="minecraft:sculk_sensor",  display="Sculk Sensor",     hardness=1.5,  tool="hoe",    light=1},
        {id=543, name="minecraft:amethyst_block",display="Amethyst Block",   hardness=1.5,  tool="pickaxe"},
        {id=544, name="minecraft:budding_amethyst",display="Budding Amethyst",hardness=1.5, tool="none"},
        {id=545, name="minecraft:amethyst_cluster",display="Amethyst Cluster",hardness=1.5, tool="pickaxe",transparent=true, light=5},
        {id=547, name="minecraft:tuff",          display="Tuff",             hardness=1.5,  tool="pickaxe"},
        {id=548, name="minecraft:calcite",       display="Calcite",          hardness=0.75, tool="pickaxe"},
        {id=549, name="minecraft:dripstone_block",display="Dripstone Block", hardness=1.5,  tool="pickaxe"},
        {id=551, name="minecraft:pointed_dripstone",display="Pointed Dripstone",hardness=1.5,tool="pickaxe",transparent=true},
        {id=553, name="minecraft:copper_ore",    display="Copper Ore",       hardness=3.0,  tool="pickaxe",min_tier=1},
        {id=555, name="minecraft:raw_copper_block",display="Block of Raw Copper",hardness=5.0,tool="pickaxe",min_tier=1},
        {id=556, name="minecraft:raw_gold_block",display="Block of Raw Gold",hardness=5.0,  tool="pickaxe",min_tier=2},
        {id=557, name="minecraft:raw_iron_block",display="Block of Raw Iron",hardness=5.0,  tool="pickaxe",min_tier=1},
        {id=558, name="minecraft:copper_block",  display="Copper Block",     hardness=3.0,  tool="pickaxe",min_tier=1},
        {id=572, name="minecraft:deepslate",     display="Deepslate",        hardness=3.0,  tool="pickaxe"},
        {id=586, name="minecraft:moss_block",    display="Moss Block",       hardness=0.1,  tool="hoe"},
        {id=587, name="minecraft:moss_carpet",   display="Moss Carpet",      hardness=0.1,  tool="hoe",    transparent=true},
        {id=589, name="minecraft:rooted_dirt",   display="Rooted Dirt",      hardness=0.5,  tool="shovel"},
        {id=590, name="minecraft:hanging_roots", display="Hanging Roots",    hardness=0,    tool="shears", transparent=true},
        {id=591, name="minecraft:big_dripleaf",  display="Big Dripleaf",     hardness=0.1,  tool="axe",    transparent=true},
        {id=592, name="minecraft:small_dripleaf",display="Small Dripleaf",   hardness=0,    tool="shears", transparent=true},
        {id=593, name="minecraft:glow_lichen",   display="Glow Lichen",      hardness=0.2,  tool="shears", transparent=true, light=7},
        -- 1.19 Wild Update
        {id=610, name="minecraft:mud",           display="Mud",              hardness=0.5,  tool="shovel"},
        {id=611, name="minecraft:mangrove_log",  display="Mangrove Log",     hardness=2.0,  tool="axe"},
        {id=612, name="minecraft:mangrove_leaves",display="Mangrove Leaves", hardness=0.2,  tool="shears"},
        {id=615, name="minecraft:sculk",         display="Sculk",            hardness=0.2,  tool="hoe"},
        {id=616, name="minecraft:sculk_catalyst",display="Sculk Catalyst",   hardness=3.0,  tool="hoe",    light=6},
        {id=617, name="minecraft:sculk_shrieker",display="Sculk Shrieker",   hardness=3.0,  tool="hoe"},
        {id=618, name="minecraft:sculk_vein",    display="Sculk Vein",       hardness=0.2,  tool="shears", transparent=true},
        -- 1.20 Trails & Tales
        {id=650, name="minecraft:bamboo_block",  display="Block of Bamboo",  hardness=2.0,  tool="axe"},
        {id=651, name="minecraft:bamboo_planks", display="Bamboo Planks",    hardness=2.0,  tool="axe"},
        {id=652, name="minecraft:cherry_log",    display="Cherry Log",       hardness=2.0,  tool="axe"},
        {id=653, name="minecraft:cherry_leaves", display="Cherry Leaves",    hardness=0.2,  tool="shears"},
        {id=654, name="minecraft:cherry_planks", display="Cherry Planks",    hardness=2.0,  tool="axe"},
        {id=655, name="minecraft:decorated_pot", display="Decorated Pot",    hardness=0,    tool="any"},
        {id=656, name="minecraft:suspicious_sand",display="Suspicious Sand", hardness=0.25, tool="brush"},
        {id=657, name="minecraft:suspicious_gravel",display="Suspicious Gravel",hardness=0.25,tool="brush"},
        {id=660, name="minecraft:pink_petals",   display="Pink Petals",      hardness=0,    tool="any",    transparent=true},
        -- 1.21 Tricky Trials
        {id=680, name="minecraft:trial_spawner", display="Trial Spawner",    hardness=50.0, tool="pickaxe"},
        {id=681, name="minecraft:vault",         display="Vault",            hardness=50.0, tool="pickaxe"},
        {id=682, name="minecraft:copper_bulb",   display="Copper Bulb",      hardness=3.0,  tool="pickaxe",min_tier=1, light=15},
        {id=683, name="minecraft:tuff_bricks",   display="Tuff Bricks",      hardness=1.5,  tool="pickaxe"},
        {id=684, name="minecraft:chiseled_tuff",  display="Chiseled Tuff",   hardness=1.5,  tool="pickaxe"},
    }
    
    for _, block in ipairs(blocks) do
        self:register(block)
    end
end

-- Make BlockRegistry callable as singleton
return setmetatable(BlockRegistry, {
    __call = function(cls)
        return cls.getInstance()
    end,
    __index = function(cls, key)
        local instance = cls.getInstance()
        return instance[key]
    end
})
