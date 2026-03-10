local HandshakeHandler = {}
function HandshakeHandler:handle(player, buf)
    -- Client-to-server handshake (encryption ack) - we skip encryption
    local server = player.server
    local PID = require("protocol.ProtocolManager").PACKET_ID
    -- Send resource pack info immediately
    local b = require("utils.BitBuffer").new()
    b:writeBool(false) b:writeBool(false) b:writeBool(false)
    b:writeLShort(0) b:writeLShort(0)
    server.protocol:sendPacket(player, PID.RESOURCE_PACKS_INFO, b)
end
return HandshakeHandler
