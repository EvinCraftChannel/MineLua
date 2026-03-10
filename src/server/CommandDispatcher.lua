-- MineLua Command Dispatcher
-- Handles commands sent by players in-game

local Logger = require("utils.Logger")

local CommandDispatcher = {}
CommandDispatcher.commands = {}

function CommandDispatcher.register(name, handler, description, usage, permission)
    CommandDispatcher.commands[name:lower()] = {
        handler     = handler,
        description = description or "",
        usage       = usage or "/" .. name,
        permission  = permission or "member",
    }
end

function CommandDispatcher.dispatch(player, cmd, args)
    local entry = CommandDispatcher.commands[cmd]
    if not entry then
        player:sendMessage("§cUnknown command: /" .. cmd .. ". Type /help for help.")
        return false
    end

    -- Permission check
    if entry.permission == "op" and not player:isOp() then
        player:sendMessage("§cYou don't have permission to use this command.")
        return false
    end

    local ok, err = pcall(entry.handler, player, args)
    if not ok then
        Logger.error("Command /" .. cmd .. " error: " .. tostring(err))
        player:sendMessage("§cAn error occurred while executing the command.")
    end
    return true
end

-- ───────────────────────────── Built-in commands ─────────────────────────────

CommandDispatcher.register("help", function(player, args)
    player:sendMessage("§e=== MineLua Commands ===")
    for name, entry in pairs(CommandDispatcher.commands) do
        player:sendMessage(string.format("§a/%s§r - %s", name, entry.description))
    end
end, "Show command list")

CommandDispatcher.register("me", function(player, args)
    local action = table.concat(args, " ")
    player.server:broadcastMessage(string.format("§d* %s %s", player.name, action))
end, "Perform an action")

CommandDispatcher.register("msg", function(player, args)
    if not args[1] then player:sendMessage("§cUsage: /msg <player> <message>") return end
    local target = player.server.players:getByName(args[1])
    if not target then player:sendMessage("§cPlayer not found.") return end
    local msg = table.concat(args, " ", 2)
    target:sendMessage(string.format("§7[%s → You]: %s", player.name, msg))
    player:sendMessage(string.format("§7[You → %s]: %s", target.name, msg))
end, "Send a private message", "/msg <player> <message>")

CommandDispatcher.register("w", function(player, args)
    CommandDispatcher.dispatch(player, "msg", args)
end, "Alias for /msg")

CommandDispatcher.register("tell", function(player, args)
    CommandDispatcher.dispatch(player, "msg", args)
end, "Alias for /msg")

CommandDispatcher.register("gamemode", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    local modes = {s=0,survival=0,c=1,creative=1,a=2,adventure=2,sp=6,spectator=6,
                   ["0"]=0,["1"]=1,["2"]=2,["6"]=6}
    local mode_id = modes[(args[1] or ""):lower()]
    if mode_id == nil then
        player:sendMessage("§cUsage: /gamemode <survival|creative|adventure|spectator>") return
    end
    local target = args[2] and player.server.players:getByName(args[2]) or player
    if not target then player:sendMessage("§cPlayer not found.") return end
    target:setGameMode(mode_id)
    local names = {[0]="Survival",[1]="Creative",[2]="Adventure",[6]="Spectator"}
    player:sendMessage("§aSet " .. target.name .. "'s game mode to " .. (names[mode_id] or mode_id))
end, "Change game mode", "/gamemode <mode> [player]", "op")

CommandDispatcher.register("gm", function(player, args)
    CommandDispatcher.dispatch(player, "gamemode", args)
end, "Alias for /gamemode", "/gm <mode>", "op")

CommandDispatcher.register("tp", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if #args == 1 then
        local target = player.server.players:getByName(args[1])
        if not target then player:sendMessage("§cPlayer not found.") return end
        player:teleport(target.x, target.y, target.z)
        player:sendMessage("§aTeleported to " .. target.name)
    elseif #args == 2 then
        local from = player.server.players:getByName(args[1])
        local to   = player.server.players:getByName(args[2])
        if not from or not to then player:sendMessage("§cPlayer not found.") return end
        from:teleport(to.x, to.y, to.z)
        player:sendMessage("§aTeleported " .. from.name .. " to " .. to.name)
    elseif #args >= 3 then
        local x = tonumber(args[1]) local y = tonumber(args[2]) local z = tonumber(args[3])
        if not x or not y or not z then player:sendMessage("§cInvalid coordinates.") return end
        player:teleport(x, y, z)
        player:sendMessage(string.format("§aTeleported to %.1f, %.1f, %.1f", x, y, z))
    else
        player:sendMessage("§cUsage: /tp <player> | /tp <x> <y> <z>")
    end
end, "Teleport", "/tp <player|x y z>", "op")

CommandDispatcher.register("spawn", function(player, args)
    local sx, sy, sz = player.world:getSpawnPoint()
    player:teleport(sx, sy, sz)
    player:sendMessage("§aTeleported to spawn.")
end, "Teleport to spawn")

CommandDispatcher.register("kill", function(player, args)
    if args[1] then
        if not player:isOp() then player:sendMessage("§cNo permission.") return end
        local target = player.server.players:getByName(args[1])
        if not target then player:sendMessage("§cPlayer not found.") return end
        target:damage(target.health + 1, "kill_command")
    else
        player:damage(player.health + 1, "kill_command")
    end
end, "Kill a player", "/kill [player]")

CommandDispatcher.register("give", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if #args < 2 then player:sendMessage("§cUsage: /give <player> <item> [count]") return end
    local target = player.server.players:getByName(args[1])
    if not target then player:sendMessage("§cPlayer not found.") return end
    local item_id = tonumber(args[2])
    if not item_id then
        local reg = require("block.BlockRegistry")
        local b = reg:get(args[2])
        item_id = b and b.id or 0
    end
    local count = tonumber(args[3]) or 1
    if item_id == 0 then player:sendMessage("§cItem not found: " .. args[2]) return end
    target.inventory:addItem({id=item_id, count=count, damage=0})
    target:sendInventory()
    player:sendMessage(string.format("§aGave %d of item %d to %s", count, item_id, target.name))
end, "Give items to a player", "/give <player> <item> [count]", "op")

CommandDispatcher.register("clear", function(player, args)
    if not player:isOp() and args[1] then player:sendMessage("§cNo permission.") return end
    local target = args[1] and player.server.players:getByName(args[1]) or player
    if not target then player:sendMessage("§cPlayer not found.") return end
    target.inventory:clear()
    target:sendInventory()
    player:sendMessage("§aCleared " .. target.name .. "'s inventory.")
end, "Clear inventory", "/clear [player]")

CommandDispatcher.register("time", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    local sub = args[1] or ""
    if sub == "set" then
        local presets = {day=1000, noon=6000, sunset=12000, night=13000, midnight=18000, sunrise=23000}
        local t = tonumber(args[2]) or presets[args[2]] or 0
        player.world.time = t
        player:sendMessage("§aTime set to " .. t)
    elseif sub == "add" then
        local t = tonumber(args[2]) or 0
        player.world.time = (player.world.time + t) % 24000
        player:sendMessage("§aAdded " .. t .. " ticks")
    elseif sub == "query" then
        player:sendMessage("§aTime: " .. player.world.time)
    else
        player:sendMessage("§cUsage: /time <set|add|query> [value]")
    end
end, "Manage world time", "/time <set|add|query> [value]", "op")

CommandDispatcher.register("weather", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    local w = args[1] or "clear"
    player.world.weather = w
    player:sendMessage("§aWeather set to " .. w)
end, "Set weather", "/weather <clear|rain|thunder>", "op")

CommandDispatcher.register("difficulty", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    local d = args[1] or "normal"
    player.server.difficulty = d
    player:sendMessage("§aDifficulty set to " .. d)
end, "Set difficulty", "/difficulty <peaceful|easy|normal|hard>", "op")

CommandDispatcher.register("seed", function(player, args)
    player:sendMessage("§aSeed: " .. player.world.seed)
end, "Show world seed")

CommandDispatcher.register("pos", function(player, args)
    player:sendMessage(string.format("§aYour position: §f%.1f, %.1f, %.1f", player.x, player.y, player.z))
end, "Show your position")

CommandDispatcher.register("list", function(player, args)
    local server = player.server
    local count  = server.players:count()
    player:sendMessage(string.format("§aOnline (%d/%d): §f%s",
        count, server.max_players, server.players:getNameList()))
end, "List online players")

CommandDispatcher.register("kick", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if not args[1] then player:sendMessage("§cUsage: /kick <player> [reason]") return end
    local target = player.server.players:getByName(args[1])
    if not target then player:sendMessage("§cPlayer not found.") return end
    local reason = #args > 1 and table.concat(args, " ", 2) or "Kicked by operator"
    target:kick(reason)
    player:sendMessage("§aKicked " .. target.name)
end, "Kick a player", "/kick <player> [reason]", "op")

CommandDispatcher.register("ban", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if not args[1] then player:sendMessage("§cUsage: /ban <player>") return end
    local server = player.server
    local bans = {}
    local bf = io.open("config/bans.txt","r")
    if bf then for l in bf:lines() do bans[l:match("^%s*(.-)%s*$")] = true end bf:close() end
    bans[args[1]] = true
    local wf = io.open("config/bans.txt","w")
    if wf then for n in pairs(bans) do wf:write(n.."\n") end wf:close() end
    local target = server.players:getByName(args[1])
    if target then target:kick("You have been banned.") end
    player:sendMessage("§aBanned " .. args[1])
end, "Ban a player", "/ban <player>", "op")

CommandDispatcher.register("op", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if not args[1] then player:sendMessage("§cUsage: /op <player>") return end
    player.server:opPlayer(args[1])
    player:sendMessage("§aGranted op to " .. args[1])
end, "Grant operator", "/op <player>", "op")

CommandDispatcher.register("deop", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if not args[1] then player:sendMessage("§cUsage: /deop <player>") return end
    local ops = player.server:loadOps()
    ops[args[1]] = nil
    player.server:saveOps(ops)
    local t = player.server.players:getByName(args[1])
    if t then t:setOp(false) end
    player:sendMessage("§aRemoved op from " .. args[1])
end, "Remove operator", "/deop <player>", "op")

CommandDispatcher.register("say", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    local msg = table.concat(args, " ")
    player.server:broadcastMessage("[" .. player.name .. "] " .. msg)
end, "Broadcast a message", "/say <message>", "op")

CommandDispatcher.register("title", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if not args[1] or not args[2] then
        player:sendMessage("§cUsage: /title <player> title|subtitle|actionbar <text>") return
    end
    local target = player.server.players:getByName(args[1])
    if not target then player:sendMessage("§cPlayer not found.") return end
    local sub = args[2]:lower()
    local text = table.concat(args, " ", 3)
    if sub == "title"     then target:sendTitle(text, "")
    elseif sub == "subtitle" then target:sendTitle("", text)
    elseif sub == "actionbar" then target:sendActionBar(text)
    end
end, "Send title", "/title <player> <title|subtitle|actionbar> <text>", "op")

CommandDispatcher.register("effect", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if #args < 2 then player:sendMessage("§cUsage: /effect <player> <effect> [duration] [amplifier]") return end
    local target = player.server.players:getByName(args[1])
    if not target then player:sendMessage("§cPlayer not found.") return end
    local effect_id = tonumber(args[2]) or 0
    local duration  = tonumber(args[3]) or 300
    local amplifier = tonumber(args[4]) or 0
    target:addEffect(effect_id, amplifier, duration)
    player:sendMessage(string.format("§aApplied effect %d to %s", effect_id, target.name))
end, "Apply potion effect", "/effect <player> <id> [dur] [amp]", "op")

CommandDispatcher.register("playsound", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if not args[1] then player:sendMessage("§cUsage: /playsound <sound> [player]") return end
    local sound  = args[1]
    local target = args[2] and player.server.players:getByName(args[2]) or player
    if not target then player:sendMessage("§cPlayer not found.") return end
    target:playSound(sound, target.x, target.y, target.z)
    player:sendMessage("§aPlayed sound " .. sound)
end, "Play a sound", "/playsound <sound> [player]", "op")

CommandDispatcher.register("transfer", function(player, args)
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    if not args[1] then player:sendMessage("§cUsage: /transfer <address> [port]") return end
    local target = args[3] and player.server.players:getByName(args[3]) or player
    target:transfer(args[1], tonumber(args[2]) or 19132)
    player:sendMessage("§aTransferring " .. target.name)
end, "Transfer player to another server", "/transfer <address> [port] [player]", "op")

CommandDispatcher.register("plugins", function(player, args)
    local list = {}
    for name, _ in pairs(player.server.plugins.plugins) do
        list[#list+1] = name
    end
    player:sendMessage("§aPlugins (" .. #list .. "): §f" .. table.concat(list, ", "))
end, "List loaded plugins")

CommandDispatcher.register("version", function(player, args)
    player:sendMessage("§aMineLua Server v" .. player.server:getVersion())
    player:sendMessage("§7Your client: " .. player.game_version ..
        " (protocol " .. player.protocol_version .. ")")
end, "Show server version")

CommandDispatcher.register("tps", function(player, args)
    player:sendMessage(string.format("§aTPS: §f%d §aUptime: §f%ds",
        player.server.tick_rate,
        os.time() - player.server.start_time))
end, "Show server TPS")

CommandDispatcher.register("gamerule", function(player, args)
    if not args[1] then
        player:sendMessage("§cUsage: /gamerule <rule> [value]") return
    end
    local world = player.world
    if args[2] == nil then
        local val = world:getGameRule(args[1])
        player:sendMessage(string.format("§a%s = §f%s", args[1], tostring(val)))
    else
        if not player:isOp() then player:sendMessage("§cNo permission.") return end
        local v = args[2]
        if v == "true" then v = true elseif v == "false" then v = false
        elseif tonumber(v) then v = tonumber(v) end
        world:setGameRule(args[1], v)
        player:sendMessage(string.format("§aSet §f%s §ato §f%s", args[1], tostring(v)))
    end
end, "Get or set game rules", "/gamerule <rule> [value]")

CommandDispatcher.register("world", function(player, args)
    if not args[1] then
        player:sendMessage("§aCurrently in world: §f" .. player.world.name) return
    end
    if not player:isOp() then player:sendMessage("§cNo permission.") return end
    local world = player.server.worlds:getByName(args[1])
    if not world then
        player:sendMessage("§cWorld not found. Loading...")
        local ok, w = pcall(player.server.worlds.load, player.server.worlds, args[1])
        if ok then world = w else player:sendMessage("§cFailed: " .. tostring(w)) return end
    end
    player.world = world
    local sx, sy, sz = world:getSpawnPoint()
    player:teleport(sx, sy, sz)
    player:sendMessage("§aMoved to world: §f" .. world.name)
end, "Switch worlds", "/world [name]")

return CommandDispatcher
