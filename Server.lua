local socket = require("socket")
local BinaryStream = require("BinaryStream")

local Server = {}
Server.__index = Server

-- Magic Number RakNet (Wajib untuk handshake)
local RAKNET_MAGIC = "\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x12\x34\x56\x78"

function Server.start(ip, port)
    local instance = setmetatable({}, Server)
    instance.socket = assert(socket.udp())
    instance.socket:settimeout(0)
    instance.socket:setsockname(ip, port)
    instance.isRunning = true
    
    print(string.format("[MineLua] Server berjalan di %s:%d", ip, port))
    instance:run()
end

function Server:run()
    while self.isRunning do
        local data, ip, port = self.socket:receivefrom()
        if data then
            self:handlePacket(data, ip, port)
        end
        socket.sleep(0.01) -- Hemat CPU
    end
end

function Server:handlePacket(data, ip, port)
    local stream = BinaryStream.new(data)
    local packetId = stream:getByte()
    local identifier = ip .. ":" .. port

    -- Jika belum ada sesi (Unconnected)
    if not self.players[identifier] then
        if packetId == 0x01 or packetId == 0x02 then -- Ping
            self:sendUnconnectedPong(ip, port)
        elseif packetId == 0x05 then -- Open Connection Request 1
            -- Panggil fungsi handleOpenConnectionRequest1 dari kode Core kamu sebelumnya
            self:handleOpenConnectionRequest1(data, ip, port)
        end
    else
        -- Jika sudah ada sesi, proses paket frameset (0x80 - 0x8d)
        -- ...
    end
end


function Server:sendUnconnectedPong(ip, port)
    local stream = BinaryStream.new()
    
    -- 1. Packet ID (Unconnected Pong)
    stream:putByte(0x1c) 
    
    -- 2. Ping ID (Time - 8 Bytes Big Endian)
    stream:putLong(os.time())
    
    -- 3. Server ID (GUID - 8 Bytes Big Endian)
    -- Gunakan angka acak yang konsisten untuk ID server Anda
-- Tambahkan ini di fungsi Server.start atau init
self.serverId = math.random(10000000, 99999999) .. math.random(10000000, 99999999)
self.serverId = tonumber(self.serverId) 
    stream:putLong(serverId) 
    
    -- 4. Magic (16 Bytes)
    stream.buffer = stream.buffer .. RAKNET_MAGIC
    
    -- 5. Server Info String (Format RakNet Bedrock)
    -- Protocol ID untuk 1.21.132 adalah 775
    local protocol = "775"
    local version = "1.21.132"
    local motd = "MineLua Server"
    local subMotd = "Berjalan di Lua"
    local currentPlayers = "0"
    local maxPlayers = "20"
    local gameMode = "Survival" -- "Creative", "Survival", dll.
    
    -- Struktur String RakNet:
    -- Edisi;MOTD;Protocol;Versi;Pemain;MaxPemain;ServerID;SubMOTD;GameMode;Dunia;PortIPv4;PortIPv6;
    local motdTable = {
        "MCPE",
        motd,
        protocol,
        version,
        currentPlayers,
        maxPlayers,
        serverIdString,
        tostring(serverId),
        subMotd,
        gameMode,
        "1",     -- Server status (1 = online)
        "19132", -- Port IPv4
        "19133"  -- Port IPv6
    }
    
    local finalMotd = table.concat(motdTable, ";") .. ";"
    
    -- Menggunakan putString16 (Short-length prefixed string)
    stream:putString16(finalMotd)
    
    -- Kirim balik ke client
    self.socket:sendto(stream:getBuffer(), ip, port)
end


Server.start("0.0.0.0", 19132)
