local MobEquipmentHandler = {}
function MobEquipmentHandler:handle(player, buf)
    local window_id = buf:readByte()
    -- read item stack then slot info
    player.selected_slot = buf:remaining() > 0 and buf:readByte() or player.selected_slot
end
return MobEquipmentHandler
