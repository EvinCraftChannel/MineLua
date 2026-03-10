local FormResponseHandler = {}
function FormResponseHandler:handle(player, buf)
    local form_id = buf:readVarInt()
    local data    = buf:readString()
    player.server.events:fire("PlayerFormResponse",{
        player=player, form_id=form_id, data=data
    })
end
return FormResponseHandler
