-- Resource Pack Client Response Handler
local Logger = require("utils.Logger")
local ResourcePackHandler = {}
function ResourcePackHandler:handle(player, buf)
    local status = buf:readByte() -- 1=refused 2=send 3=have all 4=completed
    Logger.debug(string.format("ResourcePackClientResponse: %d from %s", status, player.name or "?"))
    local PID = require("protocol.ProtocolManager").PACKET_ID
    local server = player.server

    if status == 2 then
        -- Client wants packs - we have none, send empty stack
        local b = require("utils.BitBuffer").new()
        b:writeBool(false) -- must accept
        b:writeBool(false) -- scripting
        b:writeByte(0)     -- forced to accept level
        b:writeShort(0)    -- behavior packs
        b:writeShort(0)    -- resource packs
        server.protocol:sendPacket(player, PID.RESOURCE_PACK_STACK, b)
    elseif status == 3 or status == 4 then
        -- Client has all packs → spawn player
        player:spawn()
    end
end
return ResourcePackHandler
