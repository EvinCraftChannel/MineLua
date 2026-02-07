local AdminTools = {
    name = "AdminTools",
    description = "Admin command plugin",
    ops = {}
}

function AdminTools:onEnable()
    local file = io.open("ops.json", "r")
    if file then
        self.ops = cjson.decode(file:read("*all"))
        file:close()
    end
end

function AdminTools:isOp(player)
    if player == "CONSOLE" then return true end
    return self.ops[player.username] == true
end

function AdminTools:onCommand(player, command, args)
    if command == "pl" or command == "plugin" then
        local list = ""
        local PluginManager = require("PluginManager") 
        for name, _ in pairs(PluginManager.plugins) do
            list = list .. name .. ", "
        end
        local msg = "[Server] Plugins: " .. list:sub(1, -3)
        Core:sendMessage(player, msg)
        return true
    end

    if command == "op" then
        if player ~= "CONSOLE" then 
            Core:sendMessage(player, "§cThis command can only be executed via terminal!")
            return true
        end
        
        local targetName = args[1]
        if targetName then
            self.ops[targetName] = true
            print("[Admin] " .. targetName .. " now is Operator.")
        end
        return true
    end

    if not self:isOp(player) then
        Core:sendMessage(player, "§cKamu tidak memiliki izin untuk menggunakan perintah ini!")
        return true
    end

    -- /gamemode <0|1>
    if command == "gamemode" or command == "gm" then
        local mode = tonumber(args[1]) or 0
        player.gamemode = mode
        -- Paket PlayStatus atau paket data khusus gamemode
        Core:sendPlayStatus(player, 3) -- Refresh status
        Core:sendMessage(player, "§aGamemode diubah ke " .. mode)

    -- /tp <x> <y> <z> atau /tp <target>
    elseif command == "tp" then
        local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
        if x and y and z then
            player.x, player.y, player.z = x, y, z
            Core:sendMovePlayer(player, x, y, z)
            Core:sendMessage(player, "§aBerhasil teleportasi!")
        end

    -- /give <id> <count>
    elseif command == "give" then
        local itemId = tonumber(args[1])
        local count = tonumber(args[2]) or 1
        if itemId then
            Core:setInventorySlot(player, 0, itemId, count)
            Core:sendMessage(player, "§aMemberikan item " .. itemId)
        end

    -- /kick <nama>
    elseif command == "kick" then
        local targetName = args[1]
        local target = Core:getPlayerByName(targetName)
        if target then
            -- Logika disconnect di Core
            Core:disconnectPlayer(target, "Dikick oleh Admin")
            Core:sendMessage(player, "§a" .. targetName .. " telah dikeluarkan.")
        else
            Core:sendMessage(player, "§cPemain tidak ditemukan.")
        end
    end

    return true
end

return AdminTools
