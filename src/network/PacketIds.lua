-- minelua/src/network/PacketIds.lua
local PacketIds = {
    -- Mapping Protokol
    [710] = "1.21.20",
    [748] = "1.21.50",
    [775] = "1.21.132", -- Versi yang kamu maksud
}

-- ID Paket biasanya tetap sama di sub-versi yang berdekatan
local CommonIds = {
    LOGIN_PACKET = 0x01,
    PLAY_STATUS_PACKET = 0x02,
    TEXT_PACKET = 0x09,
    START_GAME_PACKET = 0x0b,
    RESOURCE_PACKS_INFO = 0x06,
}

function PacketIds.getLatest()
    return 775, "1.21.132"
end

function PacketIds.getPacket(name)
    return CommonIds[name]
end

return PacketIds
