--[[
  HelloWorld Plugin for MineLua
  Demonstrates the full MineLua plugin API:
    - Events
    - Commands
    - Scheduler
    - Forms (UI)
    - World manipulation
    - Items & blocks
]]

local info = PluginInfo   -- metadata from plugin.yml
local log  = Logger
local srv  = Server

-- ── onLoad — called when the plugin is loaded ─────────────────────────────
function onLoad()
    log.info("HelloWorld v" .. info.version .. " loaded!")

    -- Register events
    srv.registerEvent("PlayerJoin",   onPlayerJoin)
    srv.registerEvent("PlayerQuit",   onPlayerQuit)
    srv.registerEvent("PlayerChat",   onPlayerChat)
    srv.registerEvent("BlockBreak",   onBlockBreak)
    srv.registerEvent("PlayerDeath",  onPlayerDeath)
    srv.registerEvent("PlayerRespawn",onPlayerRespawn)

    -- Register commands
    srv.registerCommand("hello",    cmdHello,    "Say hello",          "/hello")
    srv.registerCommand("warp",     cmdWarp,     "Teleport to a warp", "/warp <name>")
    srv.registerCommand("setwarp",  cmdSetWarp,  "Set a warp point",   "/setwarp <name>")
    srv.registerCommand("menu",     cmdMenu,     "Open plugin menu",   "/menu")
    srv.registerCommand("kit",      cmdKit,      "Get a starter kit",  "/kit")
    srv.registerCommand("heal",     cmdHeal,     "Heal yourself",      "/heal")
    srv.registerCommand("spawn",    cmdSpawn,    "Go to spawn",        "/spawn")
    srv.registerCommand("fly",      cmdFly,      "Toggle flight",      "/fly")
    srv.registerCommand("speed",    cmdSpeed,    "Set movement speed", "/speed <1-5>")
    srv.registerCommand("back",     cmdBack,     "Return to last position", "/back")

    -- Announce to online players that the plugin loaded
    srv.scheduleTask(20, function()
        srv.broadcastMessage("§a[HelloWorld] Plugin loaded and ready!")
    end)

    -- Repeating task: broadcast time every 5 minutes
    srv.scheduleTask(0, function()
        srv.scheduleRepeating(0, 6000, function()
            local world = srv.getDefaultWorld()
            if world then
                local t = world.time or 0
                local period = t < 6000 and "§eMorning" or
                               t < 12000 and "§6Noon" or
                               t < 13000 and "§cSunset" or "§9Night"
                srv.broadcastMessage("§7[Time] " .. period .. " §7(" .. t .. ")")
            end
        end)
    end)

    log.info("HelloWorld: all events and commands registered.")
end

-- ── onUnload ───────────────────────────────────────────────────────────────
function onUnload()
    log.info("HelloWorld unloaded!")
end

-- ── Warp storage ──────────────────────────────────────────────────────────
local warps = {}   -- name -> {x,y,z,world}

local function loadWarps()
    local f = io.open("warps.json", "r")
    if f then
        local content = f:read("*a")
        f:close()
        -- Simple key=x,y,z parsing
        for line in content:gmatch("[^\n]+") do
            local name, x, y, z, world = line:match("^([^=]+)=([%d%-%.]+),([%d%-%.]+),([%d%-%.]+),(.+)$")
            if name then
                warps[name] = {x=tonumber(x),y=tonumber(y),z=tonumber(z),world=world}
            end
        end
    end
end

local function saveWarps()
    local f = io.open("warps.json", "w")
    if f then
        for name, w in pairs(warps) do
            f:write(string.format("%s=%s,%s,%s,%s\n",
                name, w.x, w.y, w.z, w.world))
        end
        f:close()
    end
end

local last_positions = {}   -- player name -> {x,y,z}

loadWarps()

-- ── Event handlers ────────────────────────────────────────────────────────

function onPlayerJoin(event)
    local player = event.player
    log.info("HelloWorld: " .. player.name .. " joined!")

    -- Welcome message with title
    srv.scheduleTask(40, function()
        if player.spawned then
            player:sendTitle("§aWelcome!", "§7" .. player.name, 10, 60, 20)
            player:sendMessage("§e[HelloWorld] §fWelcome, §a" .. player.name .. "§f! Type §e/hello§f to get started.")
        end
    end)
end

function onPlayerQuit(event)
    local player = event.player
    log.info("HelloWorld: " .. player.name .. " left.")
    last_positions[player.name] = nil
end

function onPlayerChat(event)
    -- Filter swearing (example)
    local bad_words = {"badword1", "badword2"}
    for _, w in ipairs(bad_words) do
        if event.message:lower():find(w) then
            event.cancel  = true
            event.player:sendMessage("§cPlease keep chat family-friendly!")
            return
        end
    end
end

function onBlockBreak(event)
    local player = event.player
    -- Prevent breaking bedrock (id=7) even in creative for non-ops
    local block = player.world:getBlock(event.x, event.y, event.z)
    if block and block.id == 7 and not player:isOp() then
        event.cancel = true
        player:sendMessage("§cYou cannot break bedrock!")
    end
end

function onPlayerDeath(event)
    local player = event.player
    last_positions[player.name] = {x=player.x, y=player.y, z=player.z}
end

function onPlayerRespawn(event)
    local player = event.player
    player:sendMessage("§eYou respawned! Type §a/back §eto return to your death point.")
end

-- ── Commands ──────────────────────────────────────────────────────────────

function cmdHello(player, args)
    player:sendMessage("§aHello, §e" .. player.name .. "§a! Welcome to MineLua!")
    player:sendMessage("§7Server: §fMineLua §7| §7Players: §f" ..
        srv.getPlayerCount() .. "/" .. (srv.getConfig().max_players or 20))
    player:sendMessage("§7Your position: §f" ..
        string.format("%.1f, %.1f, %.1f", player.x, player.y, player.z))
    player:sendMessage("§7World: §f" .. (player.world and player.world.name or "unknown"))
    player:sendMessage("§7Version: §f" .. srv.getVersion())
    player:playSound("mob.villager.yes", player.x, player.y, player.z)
end

function cmdWarp(player, args)
    if not args[1] then
        -- List warps
        local list = {}
        for name in pairs(warps) do list[#list+1] = name end
        if #list == 0 then
            player:sendMessage("§cNo warps set. Use /setwarp <name> to create one.")
        else
            player:sendMessage("§aAvailable warps: §f" .. table.concat(list, "§7, §f"))
        end
        return
    end
    local w = warps[args[1]:lower()]
    if not w then
        player:sendMessage("§cWarp '" .. args[1] .. "' not found. Type /warp for a list.")
        return
    end
    last_positions[player.name] = {x=player.x, y=player.y, z=player.z}
    player:teleport(w.x, w.y, w.z)
    player:sendMessage("§aTeleported to warp §e" .. args[1])
    player:playSound("mob.endermen.portal")
end

function cmdSetWarp(player, args)
    if not player:isOp() then
        player:sendMessage("§cOnly operators can set warps.")
        return
    end
    if not args[1] then
        player:sendMessage("§cUsage: /setwarp <name>")
        return
    end
    local name = args[1]:lower()
    warps[name] = {
        x = player.x, y = player.y, z = player.z,
        world = player.world and player.world.name or "world"
    }
    saveWarps()
    player:sendMessage("§aWarp §e" .. name .. " §aset at your current position!")
end

function cmdMenu(player, args)
    -- Send a simple modal form menu
    player:sendForm(100, {
        type    = "form",
        title   = "§lMineLua Menu",
        content = "§7Welcome, " .. player.name .. "!\nWhat would you like to do?",
        buttons = {
            {text = "§aGet Starter Kit"},
            {text = "§bTeleport to Spawn"},
            {text = "§eHeal Me"},
            {text = "§cClose"},
        }
    })
end

-- Handle form responses
srv.registerEvent("PlayerFormResponse", function(event)
    if event.form_id ~= 100 then return end
    local choice = tonumber(event.data)
    if choice == 0 then
        cmdKit(event.player, {})
    elseif choice == 1 then
        cmdSpawn(event.player, {})
    elseif choice == 2 then
        cmdHeal(event.player, {})
    end
end)

function cmdKit(player, args)
    -- Give starter kit
    local kit = {
        {id=276, count=1, damage=0},  -- Diamond Sword
        {id=278, count=1, damage=0},  -- Diamond Pickaxe
        {id=277, count=1, damage=0},  -- Diamond Shovel
        {id=279, count=1, damage=0},  -- Diamond Axe
        {id=310, count=1, damage=0},  -- Diamond Helmet
        {id=311, count=1, damage=0},  -- Diamond Chestplate
        {id=312, count=1, damage=0},  -- Diamond Leggings
        {id=313, count=1, damage=0},  -- Diamond Boots
        {id=297, count=64, damage=0}, -- Bread
        {id=264, count=32, damage=0}, -- Diamonds
        {id=50,  count=64, damage=0}, -- Torches
    }
    for _, item in ipairs(kit) do
        player.inventory:addItem(item)
    end
    player:sendInventory()
    player:sendMessage("§a✓ Starter kit received! Happy mining!")
    player:playSound("random.levelup")
end

function cmdHeal(player, args)
    player.health = player.max_health
    player.food   = 20
    player:sendHealth()
    player:sendMessage("§a✓ You have been healed!")
    player:addEffect(10, 0, 100, false) -- Regen I for 5 seconds
end

function cmdSpawn(player, args)
    local world = player.world or srv.getDefaultWorld()
    if not world then player:sendMessage("§cNo world loaded!") return end
    last_positions[player.name] = {x=player.x, y=player.y, z=player.z}
    local sx, sy, sz = world:getSpawnPoint()
    player:teleport(sx, sy, sz)
    player:sendMessage("§aTeleported to spawn!")
end

function cmdFly(player, args)
    if not player:isOp() and player.game_mode ~= 1 then
        player:sendMessage("§cOnly operators can toggle flight outside Creative mode.")
        return
    end
    player.flying = not player.flying
    player:sendAdventureSettings()
    player:sendMessage(player.flying and "§aFlight enabled!" or "§cFlight disabled!")
end

function cmdSpeed(player, args)
    if not player:isOp() then
        player:sendMessage("§cOnly operators can change speed.")
        return
    end
    local level = tonumber(args[1]) or 1
    level = math.max(1, math.min(5, level))
    -- Send movement speed attribute
    player:sendMessage("§aSpeed set to §e" .. level)
end

function cmdBack(player, args)
    local pos = last_positions[player.name]
    if not pos then
        player:sendMessage("§cNo previous position saved.")
        return
    end
    last_positions[player.name] = {x=player.x, y=player.y, z=player.z}
    player:teleport(pos.x, pos.y, pos.z)
    player:sendMessage("§aTeleported back to your previous position!")
end
