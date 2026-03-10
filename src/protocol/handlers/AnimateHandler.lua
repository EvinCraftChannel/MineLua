local AnimateHandler = {}
function AnimateHandler:handle(player, buf)
    local action = buf:readVarInt()
    player.server.events:fire("PlayerAnimate",{player=player,action=action})
end
return AnimateHandler
