-- MineLua World Manager
-- Manages multiple worlds, supports MCBE world format

local Logger = require("utils.Logger")
local World = require("world.World")

local WorldManager = {}
WorldManager.__index = WorldManager

function WorldManager.new(server)
    local self = setmetatable({}, WorldManager)
    self.server = server
    self.worlds = {} -- name -> World
    self.default_world = nil
    self.worlds_dir = "worlds"
    return self
end

function WorldManager:loadAll()
    -- Create worlds directory if needed
    os.execute("mkdir -p " .. self.worlds_dir)
    
    local default_name = self.server.config.default_world or "world"
    
    -- Check if worlds directory has subfolders
    local handle = io.popen(string.format(
        "find %s -maxdepth 1 -mindepth 1 -type d 2>/dev/null", self.worlds_dir))
    
    local found_worlds = {}
    if handle then
        for path in handle:lines() do
            local name = path:match("([^/\\]+)$")
            if name then
                table.insert(found_worlds, {name = name, path = path})
            end
        end
        handle:close()
    end
    
    -- Also check for level.dat in world folders (MCBE format)
    local loaded = 0
    for _, w in ipairs(found_worlds) do
        local ok, err = pcall(self.load, self, w.name)
        if ok then
            loaded = loaded + 1
        else
            Logger.error(string.format("Failed to load world '%s': %s", w.name, tostring(err)))
        end
    end
    
    -- If no worlds found, create default
    if loaded == 0 then
        Logger.info(string.format("No worlds found, creating default world '%s'...", default_name))
        self:createNew(default_name)
    end
    
    -- Set default world
    self.default_world = self.worlds[default_name] 
        or self.worlds[next(self.worlds)]
    
    if self.default_world then
        Logger.info(string.format("Default world: %s", self.default_world.name))
    else
        Logger.error("No worlds available!")
    end
    
    Logger.info(string.format("Loaded %d world(s)", self:count()))
end

function WorldManager:load(name)
    if self.worlds[name] then
        return self.worlds[name]
    end
    
    local path = self.worlds_dir .. "/" .. name
    
    -- Check if world folder exists
    local f = io.open(path .. "/level.dat", "rb")
    local has_level_dat = f ~= nil
    if f then f:close() end
    
    Logger.info(string.format("Loading world '%s'...", name))
    
    local world = World.new(self.server, name, path)
    
    if has_level_dat then
        world:loadLevelDat()
    else
        -- Create minimal world structure
        world:initialize()
    end
    
    self.worlds[name] = world
    
    Logger.info(string.format("World '%s' loaded (seed: %d, spawn: %.0f,%.0f,%.0f)",
        name, world.seed, world.spawn_x, world.spawn_y, world.spawn_z))
    
    return world
end

function WorldManager:createNew(name, generator, seed)
    local path = self.worlds_dir .. "/" .. name
    os.execute("mkdir -p " .. path)
    os.execute("mkdir -p " .. path .. "/db")
    os.execute("mkdir -p " .. path .. "/players")
    
    local world = World.new(self.server, name, path)
    world.seed = seed or math.random(0, 2^30)
    world.generator_type = generator or "default"
    world:initialize()
    world:save()
    
    self.worlds[name] = world
    Logger.info(string.format("Created new world '%s' with seed %d", name, world.seed))
    
    return world
end

function WorldManager:getDefault()
    return self.default_world
end

function WorldManager:getByName(name)
    return self.worlds[name]
end

function WorldManager:getAll()
    local list = {}
    for _, world in pairs(self.worlds) do
        table.insert(list, world)
    end
    return list
end

function WorldManager:count()
    local c = 0
    for _ in pairs(self.worlds) do c = c + 1 end
    return c
end

function WorldManager:tick(ticks)
    for _, world in pairs(self.worlds) do
        world:tick(ticks)
    end
end

function WorldManager:saveAll()
    for name, world in pairs(self.worlds) do
        local ok, err = pcall(world.save, world)
        if not ok then
            Logger.error(string.format("Failed to save world '%s': %s", name, tostring(err)))
        end
    end
end

function WorldManager:printList()
    print(string.format("Loaded worlds (%d):", self:count()))
    for name, world in pairs(self.worlds) do
        print(string.format("  - %s (seed: %d, players: %d, chunks: %d)", 
            name, world.seed, world:getPlayerCount(), world:getLoadedChunkCount()))
    end
end

return WorldManager
