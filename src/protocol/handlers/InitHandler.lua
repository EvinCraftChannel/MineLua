local InitHandler = {}
function InitHandler:handle(player, buf)
    player.initialized = true
    player.server.events:fire("PlayerFullyJoined", {player = player})
end
return InitHandler
