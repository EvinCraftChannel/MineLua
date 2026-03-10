local AuthInputHandler = {}
function AuthInputHandler:handle(player, buf)
    local pitch = buf:readFloat()
    local yaw   = buf:readFloat()
    local x = buf:readFloat(); local y = buf:readFloat(); local z = buf:readFloat()
    player.x=x; player.y=y; player.z=z
    player.yaw=yaw; player.pitch=pitch
end
return AuthInputHandler
