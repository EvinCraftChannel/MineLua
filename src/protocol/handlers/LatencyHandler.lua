local LatencyHandler = {}
function LatencyHandler:handle(player, buf)
    local timestamp = buf:readLInt64()
    local is_from_server = buf:readBool()
    if is_from_server then return end
    player.latency = math.max(0, math.floor((require("socket").gettime()*1000) - timestamp))
    -- Echo back
    local b = require("utils.BitBuffer").new()
    b:writeLInt64(timestamp) b:writeBool(true)
    player.server.protocol:sendPacket(player, require("protocol.ProtocolManager").PACKET_ID.NETWORK_STACK_LATENCY, b)
end
return LatencyHandler
