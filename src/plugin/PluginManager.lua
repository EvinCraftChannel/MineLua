-- MineLua Plugin Manager
-- Loads and manages .plug plugin files
-- A .plug file is a ZIP archive containing:
--   - main.lua (entry point)
--   - plugin.yml (metadata)
--   - textures/ (optional textures)
--   - data/ (optional data files)

local Logger = require("utils.Logger")
local EventManager = require("server.EventManager")

-- Try to load zip library
local zip_ok, zip = pcall(require, "zip")
if not zip_ok then
    zip_ok, zip = pcall(require, "luazip")
end

local PluginManager = {}
PluginManager.__index = PluginManager

function PluginManager.new(server)
    local self = setmetatable({}, PluginManager)
    self.server = server
    self.plugins = {} -- name -> Plugin
    self.plugin_dir = "plugins"
    return self
end

function PluginManager:loadAll()
    -- Create plugins directory if needed
    os.execute("mkdir -p " .. self.plugin_dir)
    
    local count = 0
    
    -- Scan for .plug files
    local handle = io.popen(string.format("find %s -maxdepth 1 -name '*.plug' 2>/dev/null", 
        self.plugin_dir))
    if handle then
        for path in handle:lines() do
            local ok, err = pcall(self.loadPlugin, self, path)
            if ok then
                count = count + 1
            else
                Logger.error(string.format("Failed to load plugin '%s': %s", path, tostring(err)))
            end
        end
        handle:close()
    end
    
    -- Also scan for folder-based plugins (for development)
    handle = io.popen(string.format("find %s -maxdepth 1 -mindepth 1 -type d 2>/dev/null",
        self.plugin_dir))
    if handle then
        for path in handle:lines() do
            local main = path .. "/main.lua"
            local f = io.open(main, "r")
            if f then
                f:close()
                local ok, err = pcall(self.loadFolderPlugin, self, path)
                if ok then
                    count = count + 1
                else
                    Logger.error(string.format("Failed to load plugin '%s': %s", path, tostring(err)))
                end
            end
        end
        handle:close()
    end
    
    Logger.info(string.format("Loaded %d plugin(s)", count))
end

function PluginManager:loadPlugin(path)
    -- Extract plugin name from path
    local name = path:match("([^/\\]+)%.plug$") or path
    
    Logger.info(string.format("Loading plugin: %s", name))
    
    -- Check if zip is available for .plug files
    if not zip_ok then
        Logger.warn("ZIP library not available, trying to treat .plug as raw Lua")
        return self:loadRawPlugin(path, name)
    end
    
    -- Open .plug file as zip archive
    local archive = zip.open(path)
    if not archive then
        Logger.error(string.format("Cannot open plugin archive: %s", path))
        return false
    end
    
    -- Read plugin.yml metadata
    local meta_file = archive:open("plugin.yml")
    if not meta_file then
        meta_file = archive:open("plugin.json")
    end
    
    local metadata = {name = name, version = "1.0", author = "Unknown"}
    if meta_file then
        local content = meta_file:read("*a")
        meta_file:close()
        local ok, parsed = pcall(self:parseYAML, content)
        if ok and parsed then
            metadata = parsed
            metadata.name = metadata.name or name
        end
    end
    
    -- Read main.lua
    local main_file = archive:open("main.lua")
    if not main_file then
        main_file = archive:open("src/main.lua")
    end
    
    if not main_file then
        archive:close()
        error("Plugin has no main.lua: " .. path)
    end
    
    local main_code = main_file:read("*a")
    main_file:close()
    
    -- Extract textures and other files to temp directory
    local extract_dir = "/tmp/minelua_plugins/" .. name
    os.execute("mkdir -p " .. extract_dir)
    
    -- Extract all files from archive
    for file_entry in archive:files() do
        local entry_name = file_entry:name()
        if entry_name ~= "main.lua" and entry_name ~= "plugin.yml" then
            -- Create directories as needed
            local entry_dir = extract_dir .. "/" .. entry_name:match("(.+)/[^/]+$") or ""
            if entry_dir ~= "" then
                os.execute("mkdir -p " .. entry_dir)
            end
            
            local ef = archive:open(entry_name)
            if ef then
                local content = ef:read("*a")
                ef:close()
                local out_path = extract_dir .. "/" .. entry_name
                local out = io.open(out_path, "wb")
                if out then
                    out:write(content)
                    out:close()
                end
            end
        end
    end
    
    archive:close()
    
    -- Create plugin environment and load
    return self:createPlugin(name, metadata, main_code, extract_dir, path)
end

function PluginManager:loadFolderPlugin(path)
    local name = path:match("([^/\\]+)$") or path
    Logger.info(string.format("Loading plugin (folder): %s", name))
    
    -- Read plugin.yml
    local metadata = {name = name, version = "1.0", author = "Unknown"}
    local yml_path = path .. "/plugin.yml"
    local f = io.open(yml_path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, parsed = pcall(self.parseYAML, self, content)
        if ok and parsed then
            metadata = parsed
            metadata.name = metadata.name or name
        end
    end
    
    -- Read main.lua
    local main_path = path .. "/main.lua"
    f = io.open(main_path, "r")
    if not f then
        error("No main.lua in plugin folder: " .. path)
    end
    local main_code = f:read("*a")
    f:close()
    
    return self:createPlugin(name, metadata, main_code, path, path)
end

function PluginManager:loadRawPlugin(path, name)
    local f = io.open(path, "r")
    if not f then return false end
    local code = f:read("*a")
    f:close()
    return self:createPlugin(name, {name=name}, code, self.plugin_dir, path)
end

function PluginManager:createPlugin(name, metadata, main_code, data_dir, source_path)
    -- Create isolated plugin environment
    local plugin_env = {
        -- Standard Lua
        print = function(...) Logger.info("[" .. name .. "] " .. table.concat({...}, "\t")) end,
        tostring = tostring,
        tonumber = tonumber,
        type = type,
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        select = select,
        unpack = table.unpack or unpack,
        error = error,
        pcall = pcall,
        xpcall = xpcall,
        assert = assert,
        setmetatable = setmetatable,
        getmetatable = getmetatable,
        rawget = rawget,
        rawset = rawset,
        rawequal = rawequal,
        rawlen = rawlen,
        math = math,
        string = string,
        table = table,
        io = {
            -- Restricted IO - only plugin data dir
            open = function(p, mode)
                local safe_path = data_dir .. "/" .. p:gsub("%.%.", "")
                return io.open(safe_path, mode)
            end
        },
        os = {
            time = os.time,
            clock = os.clock,
            date = os.date,
            difftime = os.difftime,
        },
        
        -- MineLua Plugin API
        Server = self:createServerAPI(),
        Logger = {
            info = function(msg) Logger.info("[" .. name .. "] " .. msg) end,
            warn = function(msg) Logger.warn("[" .. name .. "] " .. msg) end,
            error = function(msg) Logger.error("[" .. name .. "] " .. msg) end,
            debug = function(msg) Logger.debug("[" .. name .. "] " .. msg) end,
        },
        PluginInfo = metadata,
        DataDir = data_dir,
    }
    plugin_env._G = plugin_env
    
    -- Add require for plugin sub-modules
    plugin_env.require = function(mod)
        -- Allow requiring files within the plugin
        local mod_path = data_dir .. "/" .. mod:gsub("%.", "/") .. ".lua"
        local f = io.open(mod_path, "r")
        if f then
            local code = f:read("*a")
            f:close()
            local chunk, err = load(code, mod, "t", plugin_env)
            if chunk then
                return chunk()
            else
                error("Cannot load module " .. mod .. ": " .. (err or ""))
            end
        end
        -- Allow requiring standard MineLua API modules
        local safe_modules = {
            "utils.json", "utils.Logger", "utils.Config"
        }
        for _, safe in ipairs(safe_modules) do
            if mod == safe then
                return require(safe)
            end
        end
        error("Cannot require module in plugin: " .. mod)
    end
    
    -- Load and execute plugin code
    local chunk, err = load(main_code, name .. "/main.lua", "t", plugin_env)
    if not chunk then
        error("Syntax error in plugin " .. name .. ": " .. (err or ""))
    end
    
    local ok, result = pcall(chunk)
    if not ok then
        error("Error executing plugin " .. name .. ": " .. tostring(result))
    end
    
    -- Check if plugin returns an object with onLoad
    local plugin_obj = result or plugin_env
    
    -- Store plugin
    local plugin_record = {
        name = metadata.name or name,
        version = metadata.version or "1.0",
        author = metadata.author or "Unknown",
        description = metadata.description or "",
        env = plugin_env,
        obj = plugin_obj,
        data_dir = data_dir,
        source = source_path,
        enabled = true,
        listeners = {},
    }
    
    self.plugins[plugin_record.name] = plugin_record
    
    -- Call onLoad if defined
    if type(plugin_obj) == "table" and type(plugin_obj.onLoad) == "function" then
        plugin_obj:onLoad()
    elseif type(plugin_env.onLoad) == "function" then
        plugin_env.onLoad()
    end
    
    Logger.info(string.format("Plugin '%s' v%s by %s loaded successfully",
        plugin_record.name, plugin_record.version, plugin_record.author))
    
    return true
end

function PluginManager:createServerAPI()
    local server = self.server
    
    return {
        -- Player management
        getPlayer = function(name)
            return server.players:getByName(name)
        end,
        getOnlinePlayers = function()
            return server.players:getAll()
        end,
        getPlayerCount = function()
            return server.players:count()
        end,
        broadcastMessage = function(message)
            server:broadcastMessage(message)
        end,
        
        -- World management
        getDefaultWorld = function()
            return server.worlds:getDefault()
        end,
        getWorld = function(name)
            return server.worlds:getByName(name)
        end,
        getWorlds = function()
            return server.worlds:getAll()
        end,
        loadWorld = function(name)
            return server.worlds:load(name)
        end,
        
        -- Event system
        registerEvent = function(event_name, callback, priority)
            return server.events:register(event_name, callback, priority)
        end,
        unregisterEvent = function(listener_id)
            server.events:unregister(listener_id)
        end,
        fireEvent = function(event_name, data)
            return server.events:fire(event_name, data)
        end,
        
        -- Scheduler
        scheduleTask = function(delay, callback)
            return server.scheduler:after(delay, callback)
        end,
        scheduleRepeating = function(delay, interval, callback)
            return server.scheduler:repeating(delay, interval, callback)
        end,
        cancelTask = function(task_id)
            server.scheduler:cancel(task_id)
        end,
        
        -- Commands
        registerCommand = function(name, executor, description, usage)
            server.events:register("ConsoleCommand", function(event)
                if event.command == name:lower() then
                    executor(event.sender, event.args)
                    return true
                end
            end)
            server.events:register("PlayerCommand", function(event)
                if event.command == name:lower() then
                    executor(event.player, event.args)
                    return true
                end
            end)
        end,
        
        -- Config
        getConfig = function()
            return server.config
        end,
        
        -- Utils
        getLogger = function(name)
            return {
                info = function(msg) Logger.info("[" .. name .. "] " .. msg) end,
                warn = function(msg) Logger.warn("[" .. name .. "] " .. msg) end,
                error = function(msg) Logger.error("[" .. name .. "] " .. msg) end,
                debug = function(msg) Logger.debug("[" .. name .. "] " .. msg) end,
            }
        end,
        
        -- Items and blocks  
        getItem = function(id_or_name)
            return require("item.ItemRegistry"):get(id_or_name)
        end,
        getBlock = function(id_or_name)
            return require("block.BlockRegistry"):get(id_or_name)
        end,
        
        -- Version info
        getVersion = function()
            return server:getVersion()
        end,
        getProtocols = function()
            return require("protocol.ProtocolManager").PROTOCOLS
        end,
    }
end

function PluginManager:reloadAll()
    Logger.info("Reloading all plugins...")
    
    -- Unload current plugins
    for name, plugin in pairs(self.plugins) do
        self:unloadPlugin(plugin)
    end
    self.plugins = {}
    
    -- Reload
    self:loadAll()
end

function PluginManager:unloadPlugin(plugin)
    if not plugin then return end
    
    -- Call onUnload if defined
    if plugin.obj and type(plugin.obj.onUnload) == "function" then
        pcall(plugin.obj.onUnload, plugin.obj)
    elseif plugin.env and type(plugin.env.onUnload) == "function" then
        pcall(plugin.env.onUnload)
    end
    
    -- Unregister all listeners
    for _, listener_id in ipairs(plugin.listeners or {}) do
        self.server.events:unregister(listener_id)
    end
    
    Logger.info(string.format("Plugin '%s' unloaded", plugin.name))
end

function PluginManager:unloadAll()
    for _, plugin in pairs(self.plugins) do
        self:unloadPlugin(plugin)
    end
    self.plugins = {}
end

function PluginManager:getPlugin(name)
    return self.plugins[name]
end

function PluginManager:printList()
    local count = 0
    for name, plugin in pairs(self.plugins) do
        print(string.format("  [%s] %s v%s by %s - %s", 
            plugin.enabled and "ON" or "OFF",
            plugin.name, plugin.version, plugin.author,
            plugin.description))
        count = count + 1
    end
    if count == 0 then
        print("  No plugins loaded")
    end
    print(string.format("Total: %d plugin(s)", count))
end

-- Simple YAML parser (subset)
function PluginManager:parseYAML(content)
    local result = {}
    for line in content:gmatch("[^\n]+") do
        local key, value = line:match("^%s*([%w_%-]+)%s*:%s*(.+)$")
        if key and value then
            -- Remove quotes
            value = value:match('^"(.*)"$') or value:match("^'(.*)'$") or value
            -- Type conversion
            if value == "true" then value = true
            elseif value == "false" then value = false
            elseif tonumber(value) then value = tonumber(value)
            end
            result[key] = value
        end
    end
    return result
end

return PluginManager
