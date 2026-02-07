local PacketIds = {
    -- Versi yang didukung
    protocols = {
        [710] = "1.21.20",
        [748] = "1.21.50",
        [775] = "1.21.132",
    },
    
    -- Mapping ID Paket
    -- Jika di versi tertentu ID-nya berubah, kita bisa buat tabel khusus versi tersebut
    ids = {
        LOGIN = 0x01,
        PLAY_STATUS = 0x02,
        RESOURCE_PACKS_INFO = 0x06,
        RESOURCE_PACK_STACK = 0x07,
        START_GAME = 0x0b,
        TEXT = 0x09,
        UPDATE_BLOCK = 0x15,
        LEVEL_CHUNK = 0x3a,
        PLAYER_AUTH_INPUT = 0x90,
        INVENTORY_TRANSACTION = 0x1e,
    }
}

function PacketIds.getLatest()
    return 775, "1.21.132"
end

-- Tambahkan parameter protocol untuk antisipasi perubahan ID di masa depan
function PacketIds.get(name, protocol)
    -- Saat ini kita kembalikan dari tabel umum, 
    -- tapi di sini kamu bisa tambah logika: if protocol == 710 then ...
    return PacketIds.ids[name]
end

return PacketIds
