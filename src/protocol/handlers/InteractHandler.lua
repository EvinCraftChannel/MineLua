local InteractHandler = {}
function InteractHandler:handle(player, buf)
    local action = buf:readByte()
    local target_id = buf:readLInt64()
    if action == 4 then -- open inventory
        player.server.events:fire("PlayerOpenInventory", {player=player})
    end
end
return InteractHandler
