local ContainerHandler = {}
function ContainerHandler:handle(player, buf)
    local window_id = buf:readByte()
    player.open_container = nil
    local b = require("utils.BitBuffer").new()
    b:writeByte(window_id) b:writeBool(false)
    player.server.protocol:sendPacket(player, require("protocol.ProtocolManager").PACKET_ID.CONTAINER_CLOSE, b)
end
return ContainerHandler
