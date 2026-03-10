local Logger = require("utils.Logger")
local TextHandler = {}
function TextHandler:handle(player, buf)
    local msg_type = buf:readByte()
    buf:readBool() -- needs translation
    if msg_type == 1 then buf:readString() end -- sender (skip)
    local message = buf:readString()
    if not player.spawned then return end
    if message:sub(1,1) == "/" then
        -- Command
        local cmd_line = message:sub(2)
        local parts = {}
        for w in cmd_line:gmatch("%S+") do parts[#parts+1] = w end
        local cmd = (parts[1] or ""):lower()
        table.remove(parts, 1)
        local handled = player.server.events:fire("PlayerCommand", {
            player=player, command=cmd, args=parts, cancel=false
        })
        if not handled then
            require("server.CommandDispatcher").dispatch(player, cmd, parts)
        end
    else
        Logger.info(string.format("<%s> %s", player.name, message))
        local event = player.server.events:fire("PlayerChat", {
            player=player, message=message, format="<%s> %s", cancel=false
        })
        if not (event and event.cancel) then
            local fmt = (event and event.format) or "<%s> %s"
            local msg = (event and event.message) or message
            player.server:broadcastMessage(string.format(fmt, player.name, msg))
        end
    end
end
return TextHandler
