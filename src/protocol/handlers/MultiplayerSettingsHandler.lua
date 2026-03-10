local MultiplayerSettingsHandler = {}
function MultiplayerSettingsHandler:handle(player, buf)
    local intent = buf:readVarInt()
    player.multiplayer_intent = intent
end
return MultiplayerSettingsHandler
