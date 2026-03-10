-- MineLua Server Core
-- Handles main server loop, player management, world management

local socket = require("socket")
local Logger = require("utils.Logger")
local RakNet = require("network.RakNet")
local WorldManager = require("world.WorldManager")
local PluginManager = require("plugin.PluginManager")
local PlayerManager = require("server.PlayerManager")
local EventManager = require("server.EventManager")
local ProtocolManager = require("protocol.ProtocolManager")
local Scheduler   = require("server.Scheduler")
local BanManager  = require("server.BanManager")

local Server = {}
Server.__index = Server

function Server.new(config)
    local self = setmetatable({}, Server)
    
    self.config = config
    self.running = false
    self.ticks = 0
    self.start_time = os.time()
    
    -- Core managers
    self.players = PlayerManager.new(self)
    self.worlds = WorldManager.new(self)
    self.plugins = PluginManager.new(self)
    self.events = EventManager.new(self)
    self.protocol = ProtocolManager.new(self)
    self.scheduler = Scheduler.new(self)
    
    -- Network
    self.raknet = RakNet.new(self)
    
    -- Server properties
    self.motd     = config.motd     or "MineLua Server"
    self.sub_motd = config.sub_motd or "Powered by MineLua"
    self.max_players = config.max_players or 20
    self.port = config.port or 19132
    self.host = config.host or "0.0.0.0"
    self.game_mode = config.game_mode or "survival"
    self.difficulty = config.difficulty or "normal"
    self.view_distance = config.view_distance or 10
    self.tick_rate = 20 -- 20 TPS
    
    return self
end

function Server:start()
    Logger.info("Initializing server components...")
    
    -- Load worlds
    Logger.info("Loading worlds...")
    self.worlds:loadAll()
    
    -- Load plugins
    Logger.info("Loading plugins...")
    self.plugins:loadAll()
    
    -- Start RakNet UDP server
    Logger.info(string.format("Starting RakNet on %s:%d", self.host, self.port))
    self.raknet:bind(self.host, self.port)
    
    self.running = true
    Logger.info(string.format("Server started! MOTD: %s", self.motd))
    Logger.info(string.format("Max players: %d | Game mode: %s | Difficulty: %s", 
        self.max_players, self.game_mode, self.difficulty))
    Logger.info("Type 'help' for a list of commands")
    
    -- Fire server start event
    self.events:fire("ServerStart", {server = self})
    
    -- Main server loop
    self:mainLoop()
end

function Server:mainLoop()
    local tick_interval = 1.0 / self.tick_rate
    local last_tick = socket.gettime()
    local last_save = os.time()
    local save_interval = self.config.auto_save_interval or 300 -- 5 minutes
    
    -- Non-blocking stdin for commands
    io.input():setvbuf("no")
    
    while self.running do
        local current_time = socket.gettime()
        local delta = current_time - last_tick
        
        if delta >= tick_interval then
            last_tick = current_time
            self:tick(delta)
            
            -- Auto-save
            if os.time() - last_save >= save_interval then
                self:save()
                last_save = os.time()
            end
        end
        
        -- Handle network packets
        self.raknet:update()
        
        -- Handle console input (non-blocking)
        self:handleConsole()
        
        -- Small sleep to prevent CPU spin
        socket.sleep(0.001)
    end
    
    self:shutdown()
end

function Server:tick(delta)
    self.ticks = self.ticks + 1
    
    -- Tick scheduler
    self.scheduler:tick(self.ticks)
    
    -- Tick worlds
    self.worlds:tick(self.ticks)
    
    -- Tick players
    self.players:tick(self.ticks)
    
    -- Fire tick event
    if self.ticks % 20 == 0 then
        self.events:fire("ServerTick", {ticks = self.ticks, uptime = os.time() - self.start_time})
    end
end

function Server:handleConsole()
    -- Non-blocking console input
    local line = io.read("*l")
    if line and #line > 0 then
        self:dispatchCommand(nil, line)
    end
end

function Server:dispatchCommand(sender, command)
    local args = {}
    local cmd = command:match("^(%S+)") or ""
    for arg in command:gmatch("%S+") do
        table.insert(args, arg)
    end
    table.remove(args, 1)
    cmd = cmd:lower()
    
    -- Built-in commands
    if cmd == "stop" or cmd == "shutdown" then
        Logger.info("Stopping server...")
        self.running = false
        
    elseif cmd == "help" then
        print("=== MineLua Commands ===")
        print("stop          - Stop the server")
        print("list          - List online players")
        print("say <msg>     - Broadcast message")
        print("save          - Save all worlds")
        print("reload        - Reload plugins")
        print("tps           - Show TPS info")
        print("worlds        - List loaded worlds")
        print("plugins       - List loaded plugins")
        print("kick <player> - Kick a player")
        print("op <player>   - Give operator status")
        
    elseif cmd == "list" then
        local count = self.players:count()
        print(string.format("Players (%d/%d): %s", count, self.max_players, 
            self.players:getNameList()))
        
    elseif cmd == "say" then
        local msg = table.concat(args, " ")
        self:broadcastMessage("[Server] " .. msg)
        Logger.info("[Console] " .. msg)
        
    elseif cmd == "save" then
        self:save()
        
    elseif cmd == "reload" then
        self.plugins:reloadAll()
        print("Plugins reloaded!")
        
    elseif cmd == "tps" then
        print(string.format("TPS: %d | Uptime: %ds | Ticks: %d", 
            self.tick_rate, os.time() - self.start_time, self.ticks))
        
    elseif cmd == "worlds" then
        self.worlds:printList()
        
    elseif cmd == "plugins" then
        self.plugins:printList()
        
    elseif cmd == "kick" then
        if args[1] then
            local player = self.players:getByName(args[1])
            if player then
                local reason = #args > 1 and table.concat(args, " ", 2) or "Kicked by operator"
                player:kick(reason)
            else
                print("Player not found: " .. args[1])
            end
        end
        
    elseif cmd == "op" then
        if args[1] then
            self:opPlayer(args[1])
        end
        
    else
        -- Let plugins handle unknown commands
        local handled = self.events:fire("ConsoleCommand", {
            command = cmd,
            args = args,
            sender = sender
        })
        if not handled then
            print("Unknown command: " .. cmd .. ". Type 'help' for commands.")
        end
    end
end

function Server:broadcastMessage(message)
    Logger.info("[Broadcast] " .. message)
    self.players:broadcast(message)
end

function Server:save()
    Logger.info("Saving worlds...")
    self.worlds:saveAll()
    Logger.info("All worlds saved!")
end

function Server:opPlayer(name)
    local ops = self:loadOps()
    ops[name] = true
    self:saveOps(ops)
    Logger.info(name .. " is now an operator")
    local player = self.players:getByName(name)
    if player then
        player:setOp(true)
        player:sendMessage("You are now an operator")
    end
end

function Server:loadOps()
    local ops = {}
    local f = io.open("config/ops.txt", "r")
    if f then
        for line in f:lines() do
            local name = line:match("^%s*(.-)%s*$")
            if #name > 0 then ops[name] = true end
        end
        f:close()
    end
    return ops
end

function Server:saveOps(ops)
    local f = io.open("config/ops.txt", "w")
    if f then
        for name, _ in pairs(ops) do
            f:write(name .. "\n")
        end
        f:close()
    end
end

function Server:isBanned(name)
    return BanManager.isBanned(name)
end

function Server:isOp(name)
    local ops = self:loadOps()
    return ops[name] == true
end

function Server:getProtocolVersion()
    return require("protocol.ProtocolManager").CURRENT_PROTOCOL
end

function Server:getVersion()
    return "1.0.0"
end

function Server:shutdown()
    Logger.info("Shutting down MineLua server...")
    self.events:fire("ServerStop", {server = self})
    self.plugins:unloadAll()
    self.worlds:saveAll()
    self.raknet:close()
    Logger.info("Server stopped. Goodbye!")
end

return Server
