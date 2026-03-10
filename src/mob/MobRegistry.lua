-- MineLua Mob Registry — all MCBE entities / mobs

local MobRegistry = {}
MobRegistry.__index = MobRegistry

local _inst
function MobRegistry.getInstance()
    if not _inst then
        _inst = setmetatable({}, MobRegistry)
        _inst.mobs = {}
        _inst.by_name = {}
        _inst:_load()
    end
    return _inst
end

function MobRegistry:get(id_or_name)
    if type(id_or_name) == "number" then return self.mobs[id_or_name] end
    local n = id_or_name:lower()
    if not n:find(":") then n = "minecraft:" .. n end
    return self.by_name[n]
end

function MobRegistry:register(mob)
    self.mobs[mob.id] = mob
    if mob.name then self.by_name[mob.name] = mob end
end

function MobRegistry:_load()
    local list = {
        -- ── Passive mobs ──
        {id=11,  name="minecraft:chicken",       display="Chicken",       category="passive",   hp=4,   attack=0},
        {id=12,  name="minecraft:cow",           display="Cow",           category="passive",   hp=10,  attack=0},
        {id=13,  name="minecraft:pig",           display="Pig",           category="passive",   hp=10,  attack=0},
        {id=14,  name="minecraft:sheep",         display="Sheep",         category="passive",   hp=8,   attack=0},
        {id=16,  name="minecraft:wolf",          display="Wolf",          category="neutral",   hp=8,   attack=4},
        {id=17,  name="minecraft:villager",      display="Villager",      category="passive",   hp=20,  attack=0},
        {id=18,  name="minecraft:mooshroom",     display="Mooshroom",     category="passive",   hp=10,  attack=0},
        {id=19,  name="minecraft:squid",         display="Squid",         category="passive",   hp=10,  attack=0},
        {id=20,  name="minecraft:rabbit",        display="Rabbit",        category="passive",   hp=3,   attack=0},
        {id=22,  name="minecraft:bat",           display="Bat",           category="passive",   hp=6,   attack=0},
        {id=23,  name="minecraft:horse",         display="Horse",         category="passive",   hp=30,  attack=0},
        {id=24,  name="minecraft:donkey",        display="Donkey",        category="passive",   hp=30,  attack=0},
        {id=25,  name="minecraft:mule",          display="Mule",          category="passive",   hp=30,  attack=0},
        {id=26,  name="minecraft:skeleton_horse",display="Skeleton Horse",category="passive",   hp=15,  attack=0},
        {id=27,  name="minecraft:zombie_horse",  display="Zombie Horse",  category="passive",   hp=15,  attack=0},
        {id=28,  name="minecraft:polar_bear",    display="Polar Bear",    category="neutral",   hp=30,  attack=6},
        {id=29,  name="minecraft:llama",         display="Llama",         category="passive",   hp=30,  attack=1},
        {id=31,  name="minecraft:parrot",        display="Parrot",        category="passive",   hp=6,   attack=0},
        {id=37,  name="minecraft:dolphin",       display="Dolphin",       category="neutral",   hp=10,  attack=3},
        {id=38,  name="minecraft:cod",           display="Cod",           category="passive",   hp=3,   attack=0},
        {id=39,  name="minecraft:salmon",        display="Salmon",        category="passive",   hp=3,   attack=0},
        {id=40,  name="minecraft:tropicalfish",  display="Tropical Fish", category="passive",   hp=3,   attack=0},
        {id=41,  name="minecraft:pufferfish",    display="Pufferfish",    category="passive",   hp=3,   attack=0},
        {id=45,  name="minecraft:turtle",        display="Turtle",        category="passive",   hp=30,  attack=0},
        {id=46,  name="minecraft:cat",           display="Cat",           category="passive",   hp=10,  attack=0},
        {id=47,  name="minecraft:panda",         display="Panda",         category="neutral",   hp=20,  attack=6},
        {id=48,  name="minecraft:ocelot",        display="Ocelot",        category="passive",   hp=10,  attack=0},
        {id=49,  name="minecraft:fox",           display="Fox",           category="passive",   hp=10,  attack=2},
        {id=50,  name="minecraft:bee",           display="Bee",           category="neutral",   hp=10,  attack=2},
        {id=51,  name="minecraft:strider",       display="Strider",       category="passive",   hp=20,  attack=0},
        {id=52,  name="minecraft:hoglin",        display="Hoglin",        category="hostile",   hp=40,  attack=6},
        {id=53,  name="minecraft:zoglin",        display="Zoglin",        category="hostile",   hp=40,  attack=6},
        {id=54,  name="minecraft:piglin",        display="Piglin",        category="neutral",   hp=16,  attack=5},
        {id=55,  name="minecraft:piglin_brute",  display="Piglin Brute",  category="hostile",   hp=50,  attack=7},
        {id=56,  name="minecraft:axolotl",       display="Axolotl",       category="passive",   hp=14,  attack=2},
        {id=57,  name="minecraft:goat",          display="Goat",          category="neutral",   hp=10,  attack=2},
        {id=58,  name="minecraft:glow_squid",    display="Glow Squid",    category="passive",   hp=10,  attack=0},
        {id=59,  name="minecraft:warden",        display="Warden",        category="hostile",   hp=500, attack=30},
        {id=60,  name="minecraft:frog",          display="Frog",          category="passive",   hp=10,  attack=0},
        {id=61,  name="minecraft:tadpole",       display="Tadpole",       category="passive",   hp=6,   attack=0},
        {id=62,  name="minecraft:allay",         display="Allay",         category="passive",   hp=20,  attack=0},
        {id=63,  name="minecraft:camel",         display="Camel",         category="passive",   hp=32,  attack=0},
        {id=64,  name="minecraft:sniffer",       display="Sniffer",       category="passive",   hp=14,  attack=0},
        {id=65,  name="minecraft:armadillo",     display="Armadillo",     category="passive",   hp=12,  attack=0},
        {id=66,  name="minecraft:bogged",        display="Bogged",        category="hostile",   hp=16,  attack=3},
        {id=67,  name="minecraft:breeze",        display="Breeze",        category="hostile",   hp=30,  attack=1},
        {id=68,  name="minecraft:wind_charge",   display="Wind Charge",   category="projectile",hp=1,   attack=1},
        -- ── Hostile mobs ──
        {id=32,  name="minecraft:zombie",        display="Zombie",        category="hostile",   hp=20,  attack=3},
        {id=33,  name="minecraft:creeper",       display="Creeper",       category="hostile",   hp=20,  attack=0},
        {id=34,  name="minecraft:skeleton",      display="Skeleton",      category="hostile",   hp=20,  attack=3},
        {id=35,  name="minecraft:spider",        display="Spider",        category="neutral",   hp=16,  attack=2},
        {id=36,  name="minecraft:enderman",      display="Enderman",      category="neutral",   hp=40,  attack=7},
        {id=42,  name="minecraft:slime",         display="Slime",         category="hostile",   hp=16,  attack=3},
        {id=43,  name="minecraft:ghast",         display="Ghast",         category="hostile",   hp=10,  attack=0},
        {id=44,  name="minecraft:zombie_pigman", display="Zombified Piglin",category="neutral",  hp=20,  attack=9},
        {id=70,  name="minecraft:silverfish",    display="Silverfish",    category="hostile",   hp=8,   attack=1},
        {id=71,  name="minecraft:cave_spider",   display="Cave Spider",   category="hostile",   hp=12,  attack=2},
        {id=72,  name="minecraft:witch",         display="Witch",         category="hostile",   hp=26,  attack=0},
        {id=73,  name="minecraft:endermite",     display="Endermite",     category="hostile",   hp=8,   attack=2},
        {id=74,  name="minecraft:guardian",      display="Guardian",      category="hostile",   hp=30,  attack=6},
        {id=75,  name="minecraft:elder_guardian",display="Elder Guardian",category="hostile",   hp=80,  attack=8},
        {id=76,  name="minecraft:vindicator",    display="Vindicator",    category="hostile",   hp=24,  attack=13},
        {id=77,  name="minecraft:evoker",        display="Evoker",        category="hostile",   hp=24,  attack=0},
        {id=78,  name="minecraft:vex",           display="Vex",           category="hostile",   hp=14,  attack=9},
        {id=79,  name="minecraft:shulker",       display="Shulker",       category="hostile",   hp=30,  attack=0},
        {id=80,  name="minecraft:blaze",         display="Blaze",         category="hostile",   hp=20,  attack=6},
        {id=81,  name="minecraft:magma_cube",    display="Magma Cube",    category="hostile",   hp=16,  attack=6},
        {id=82,  name="minecraft:wither_skeleton",display="Wither Skeleton",category="hostile",hp=20,  attack=8},
        {id=83,  name="minecraft:stray",         display="Stray",         category="hostile",   hp=20,  attack=3},
        {id=84,  name="minecraft:husk",          display="Husk",          category="hostile",   hp=20,  attack=3},
        {id=85,  name="minecraft:drowned",       display="Drowned",       category="hostile",   hp=20,  attack=3},
        {id=86,  name="minecraft:phantom",       display="Phantom",       category="hostile",   hp=20,  attack=6},
        {id=87,  name="minecraft:pillager",      display="Pillager",      category="hostile",   hp=24,  attack=4},
        {id=88,  name="minecraft:ravager",       display="Ravager",       category="hostile",   hp=100, attack=12},
        -- ── Bosses ──
        {id=52,  name="minecraft:wither",        display="Wither",        category="boss",      hp=300, attack=15},
        {id=53,  name="minecraft:ender_dragon",  display="Ender Dragon",  category="boss",      hp=200, attack=6},
        -- ── NPCs / Other ──
        {id=90,  name="minecraft:npc",           display="NPC",           category="passive",   hp=20,  attack=0},
        {id=91,  name="minecraft:wandering_trader",display="Wandering Trader",category="passive",hp=20, attack=0},
        {id=92,  name="minecraft:trader_llama",  display="Trader Llama",  category="passive",   hp=30,  attack=1},
        {id=93,  name="minecraft:iron_golem",    display="Iron Golem",    category="neutral",   hp=100, attack=21},
        {id=94,  name="minecraft:snow_golem",    display="Snow Golem",    category="passive",   hp=4,   attack=0},
        {id=95,  name="minecraft:elder_guardian",display="Elder Guardian",category="hostile",   hp=80,  attack=8},
    }
    for _, mob in ipairs(list) do self:register(mob) end
end

function MobRegistry:getAll() return self.mobs end

return setmetatable(MobRegistry, {
    __call = function(cls) return cls.getInstance() end,
    __index = function(cls, k) return cls.getInstance()[k] end,
})
