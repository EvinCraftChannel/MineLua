local Logger = require("utils.Logger")
local ViolationHandler = {}
function ViolationHandler:handle(player, buf)
    local violation_type = buf:readVarInt()
    local severity = buf:readVarInt()
    local packet_id = buf:readVarInt()
    local context = buf:readString()
    Logger.warn(string.format("PacketViolation from %s: type=%d severity=%d pkt=0x%02X ctx=%s",
        player.name or "?", violation_type, severity, packet_id, context))
end
return ViolationHandler
