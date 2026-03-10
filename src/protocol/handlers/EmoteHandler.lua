local EmoteHandler = {}
function EmoteHandler:handle(player, buf)
    local entity_id = buf:readLInt64()
    local emote_id  = buf:readString()
    player.server.events:fire("PlayerEmote",{player=player,emote=emote_id})
end
return EmoteHandler
