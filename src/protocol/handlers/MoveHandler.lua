local MoveHandler = {}
function MoveHandler:handle(player, buf)
    buf:readLInt64() -- entity runtime id
    local mode = buf:readByte()
    local on_ground = buf:readBool()
    local x = buf:readFloat()
    local y = buf:readFloat()
    local z = buf:readFloat()
    local yaw   = buf:readFloat()
    local pitch = buf:readFloat()
    local head_yaw = buf:readFloat()
    if not player.spawned then return end
    player.x = x; player.y = y; player.z = z
    player.yaw = yaw; player.pitch = pitch; player.head_yaw = head_yaw
    player.on_ground = on_ground
    player.server.events:fire("PlayerMove", {player=player, x=x,y=y,z=z})
end
return MoveHandler
