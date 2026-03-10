local BlockEntityHandler = {}
function BlockEntityHandler:handle(player, buf)
    local x = buf:readZigZag()
    local y = buf:readVarInt()
    local z = buf:readZigZag()
end
return BlockEntityHandler
