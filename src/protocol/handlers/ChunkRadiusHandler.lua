local ChunkRadiusHandler = {}
function ChunkRadiusHandler:handle(player, buf)
    local requested = buf:readVarInt()
    local server = player.server
    player.chunk_radius = math.min(requested, server.view_distance)
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local b = require("utils.BitBuffer").new()
    b:writeVarInt(player.chunk_radius)
    server.protocol:sendPacket(player, PID.CHUNK_RADIUS_UPDATE, b)
end
return ChunkRadiusHandler
