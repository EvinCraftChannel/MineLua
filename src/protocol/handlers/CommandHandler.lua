local CommandHandler = {}
function CommandHandler:handle(player, buf)
    local command = buf:readString()
    if command:sub(1,1) == "/" then command = command:sub(2) end
    local parts = {}
    for w in command:gmatch("%S+") do parts[#parts+1] = w end
    local cmd = (parts[1] or ""):lower()
    table.remove(parts,1)
    local handled = player.server.events:fire("PlayerCommand",{
        player=player,command=cmd,args=parts,cancel=false
    })
    if not handled then
        require("server.CommandDispatcher").dispatch(player, cmd, parts)
    end
end
return CommandHandler
