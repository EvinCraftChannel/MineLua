-- MineLua Player Manager
local PlayerManager = {}
PlayerManager.__index = PlayerManager

function PlayerManager.new(server)
    local self = setmetatable({}, PlayerManager)
    self.server = server
    self.players = {} -- id -> Player
    return self
end

function PlayerManager:add(player)
    self.players[player.id] = player
    require("utils.Logger").info(string.format("PlayerManager: added player id=%d", player.id))
end

function PlayerManager:remove(player)
    if player then
        player:close()
        self.players[player.id] = nil
    end
end

function PlayerManager:getById(id)
    return self.players[id]
end

function PlayerManager:getByName(name)
    local lower = name:lower()
    for _, player in pairs(self.players) do
        if player.name and player.name:lower() == lower then
            return player
        end
    end
    return nil
end

function PlayerManager:getAll()
    local list = {}
    for _, p in pairs(self.players) do
        table.insert(list, p)
    end
    return list
end

function PlayerManager:count()
    local c = 0
    for _ in pairs(self.players) do c = c + 1 end
    return c
end

function PlayerManager:getNameList()
    local names = {}
    for _, p in pairs(self.players) do
        table.insert(names, p.name or "?")
    end
    return table.concat(names, ", ")
end

function PlayerManager:broadcast(message)
    for _, player in pairs(self.players) do
        if player.spawned then
            player:sendMessage(message)
        end
    end
end

function PlayerManager:tick(ticks)
    for _, player in pairs(self.players) do
        player:tick(ticks)
    end
end

return PlayerManager
