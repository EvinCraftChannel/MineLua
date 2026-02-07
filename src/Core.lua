local socket = require("socket")
local BinaryStream = require("BinaryStream")
local PluginManager = require("PluginManager")
local cjson = require("cjson") -- Library JSON untuk Lua
local PacketIds = require("PacketIds")
local zlib = require("zlib") -- Pastikan library ini terinstall
local lfs = require("lfs") -- LuaFileSystem (untuk membuat folder)
local Core = {
    isRunning = true,
    players = {}, 
    commands = {},
    RAKNET_MAGIC = "\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x12\x34\x56\x78",
    supportedProtocols = {
        [649] = "1.20.80",
        [662] = "1.21.0",
        [671] = "1.21.2",
        [775] = "1.21.132"
    }
}
local RAKNET_PROTOCOLS = {
    [10] = "Minecraft 1.14 - 1.17",
    [11] = "Minecraft 1.18 - 1.21+",
}
function Core:handleGamePacket(data, session)
    local stream = BinaryStream.new(data)
    local packetId = stream:getUnsignedVarInt()

    if packetId == 0x01 then -- Login
        self:handleLoginPacket(data, session)
    elseif packetId == 0x90 then -- PlayerAuthInput (Movement)
        self:handlePlayerAuthInput(data, session)
    elseif packetId == 0x1e then -- InventoryTransaction
        self:handleInventoryTransaction(data, session)
    elseif packetId == 0x05 then -- Disconnect
        print("[Network] " .. (session.username or "Player") .. " keluar dari permainan.")
        self.players[session.address .. ":" .. session.port] = nil
    end
end
function Core:sendRakNetFrame(session, payload)
    local stream = BinaryStream.new()
    stream:putByte(0x84) -- FrameSet ID (Reliable Ordered)
    stream:putLTriad(session.sendSeq or 0) -- Sequence Number
    session.sendSeq = (session.sendSeq or 0) + 1

    -- Encapsulated Packet Header
    local flags = 0x40 -- Reliability: Reliable Ordered (2 << 5)
    stream:putByte(flags)
    stream:putShort(#payload * 8) -- Length in bits
    
    stream:putLTriad(session.messageIndex or 0) -- Message Index
    session.messageIndex = (session.messageIndex or 0) + 1
    stream:putLTriad(0) -- Order Index
    stream:putByte(0)    -- Order Channel

    stream.buffer = stream.buffer .. payload
    
    self.socket:sendto(stream:getBuffer(), session.address, session.port)
end

function Core:handleBatch(payload, session)
    -- 1. Lewati byte 0xfe
    local data = string.sub(payload, 2)
    
    -- 2. Dekompresi (Minecraft 1.21 menggunakan Zlib)
    local success, uncompressed = pcall(function() 
        return zlib.inflate()(data) 
    end)
    
    if not success then
        print("[Error] Gagal dekompresi Batch Packet")
        return
    end

    -- 3. Proses paket-paket di dalam batch
    local stream = BinaryStream.new(uncompressed)
    while not stream:feof() do
        local length = stream:getUnsignedVarInt()
        local gameData = stream:get(length)
        
        -- Kirim ke fungsi identifikasi paket (Login, Move, dll)
        self:handleGamePacket(gameData, session)
    end
end

function Core:saveChunk(chunkX, chunkZ, data)
    -- Pastikan folder world ada
    if not lfs.attributes("world") then
        lfs.mkdir("world")
    end

    local fileName = string.format("world/chunk_%d_%d.dat", chunkX, chunkZ)
    local file = io.open(fileName, "wb")
    if file then
        file:write(data)
        file:close()
        -- print("[World] Chunk saved: " .. fileName)
    end
end

function Core:loadChunk(chunkX, chunkZ)
    local fileName = string.format("world/chunk_%d_%d.dat", chunkX, chunkZ)
    local file = io.open(fileName, "rb")
    if file then
        local data = file:read("*all")
        file:close()
        return data
    end
    return nil -- Chunk belum ada di file
end
function Core:provideChunk(session, chunkX, chunkZ)
    -- 1. Coba ambil dari file
    local data = self:loadChunk(chunkX, chunkZ)
    
    if not data then
        -- 2. Jika tidak ada, generate baru (Flat)
        local subChunkData = self:generateFlatSubChunk()
        local footer = string.rep("\x00", 25)
        data = subChunkData .. footer
        
        -- 3. Simpan hasil generate ke file untuk lain kali
        self:saveChunk(chunkX, chunkZ, data)
    end

    -- 4. Kirim ke pemain
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x3a) -- LevelChunkPacket
    stream:putVarInt(chunkX)
    stream:putVarInt(chunkZ)
    stream:putUnsignedVarInt(1) -- Sub-chunk count
    stream:putBoolean(false)
    stream:putUnsignedVarInt(#data)
    stream.buffer = stream.buffer .. data

    self:sendGamePacket(session, stream:getBuffer())
end
function Core:generateFlatSubChunk()
    local stream = BinaryStream.new()
    stream:putByte(8) -- Sub-chunk version
    stream:putByte(1) -- Number of layers (1 layer blok)
    
    -- Block Storage (Paletted)
    -- Kita buat simpel: 1 bit per blok (karena cuma ada 1 jenis blok: Grass)
    stream:putByte((0 << 1) | 1) -- 1 bit per blok, serialized
    
    -- Untuk 1 bit per blok, kita butuh (16x16x16) / 32 = 128 integer (4096 blok)
    -- Kita isi semuanya dengan indeks 0 (Blok pertama di palet)
    for i = 1, 128 do
        stream:putLInt(0) 
    end

    -- Palet: Berisi daftar jenis blok yang digunakan di sub-chunk ini
    stream:putLInt(1) -- Hanya ada 1 jenis blok dalam palet
    stream:putLInt(12345) -- Runtime ID untuk 'minecraft:grass_block' (Hanya contoh)
    
    return stream:getBuffer()
end
function Core:sendFlatChunk(session, chunkX, chunkZ)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x3a) -- Packet ID: LevelChunk
    stream:putVarInt(chunkX)
    stream:putVarInt(chunkZ)
    stream:putUnsignedVarInt(1) -- Sub-chunk count (kita kirim 1 saja agar ringan)
    stream:putBoolean(false) -- Caching disabled

    -- Data Chunk
    local subChunkData = self:generateFlatSubChunk()
    
    -- Metadata (Biome, Heightmap, dll - kita isi nol/minimal)
    local footer = string.rep("\x00", 25) -- Simplified Biome & Border data
    
    local payload = subChunkData .. footer
    stream:putUnsignedVarInt(#payload)
    stream.buffer = stream.buffer .. payload

    self:sendGamePacket(session, stream:getBuffer())
    print(string.format("[World] Chunk [%d, %d] dikirim ke %s", chunkX, chunkZ, session.username))
end
function Core:handleInventoryTransaction(data, session)
    local stream = BinaryStream.new(data)
    -- Lewati Packet ID 0x1e
    
    local legacyId = stream:getUnsignedVarInt() -- Biasanya 0
    local transactionType = stream:getUnsignedVarInt()
    
    -- Tipe 2 adalah ItemUseTransaction (Menaruh/Menghancurkan Blok)
    if transactionType == 2 then
        local actionType = stream:getUnsignedVarInt()
        local blockX = stream:getVarInt()
        local blockY = stream:getUnsignedVarInt()
        local blockZ = stream:getVarInt()
        local face = stream:getVarInt()
        local hotbarSlot = stream:getVarInt()
        
        -- Ambil info item yang dipegang
        local itemNetworkId = stream:getVarInt()
        
        if actionType == 0 then -- Klik kanan / Place Block
            self:handleBlockPlace(session, blockX, blockY, blockZ, face, itemNetworkId)
        elseif actionType == 1 then -- Klik kiri / Break Block
            self:handleBlockBreak(session, blockX, blockY, blockZ)
        end
    end
end
-- Di dalam Core.lua
Core.tasks = {}
Core.currentTick = 0

function Core:scheduleTask(delayTicks, callback)
    table.insert(self.tasks, {
        runAt = self.currentTick + delayTicks,
        callback = callback
    })
end

function Core:tick()
    self.currentTick = self.currentTick + 1
    
    -- Jalankan task dari indeks terakhir ke pertama
    for i = #self.tasks, 1, -1 do
        local task = self.tasks[i]
        if self.currentTick >= task.runAt then
            task.callback()
            table.remove(self.tasks, i)
        end
    end

    if self.currentTick % 200 == 0 then self:broadcastTime() end
end

function Core:setInventorySlot(session, slot, itemNetworkId, count)
    session.inventory = session.inventory or {}
    session.inventory[slot] = {id = itemNetworkId, count = count}

    -- Kirim paket konfirmasi ke Client
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x32) -- InventorySlotPacket
    stream:putUnsignedVarInt(0)    -- Window ID (0 = Inventory)
    stream:putUnsignedVarInt(slot)
    stream:putItem(itemNetworkId, count) -- Kamu perlu fungsi putItem di BinaryStream
    
    self:sendGamePacket(session, stream:getBuffer())
end
function Core:updatePlayerList(session, type)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x3f) -- PlayerListPacket
    stream:putByte(type) -- 0: Add, 1: Remove
    stream:putUnsignedVarInt(1) -- Jumlah pemain

    -- Data per pemain
    stream:putUUID(session.uuid)
    if type == 0 then
        stream:putVarLong(session.entityId)
        stream:putString(session.username)
        stream:putString(session.skinId or "Standard_Custom")
        -- Di sini kamu harus mengirimkan bitstream Skin Data (sangat panjang)
    end
    
    self:broadcastPacket(stream:getBuffer())
end
-- Ini adalah skema dasar encoder NBT sederhana
function BinaryStream:putNBT(data)
    if not data then
        self:putByte(0) -- TAG_End (NBT Kosong)
        return
    end
    -- Kamu butuh library seperti 'lua-nbt' karena manual encoding sangat kompleks
    -- Contoh: self.buffer = self.buffer .. nbt.encode(data)
end

function Core:handleBlockPlace(session, x, y, z, face, blockId)
    -- 1. Hitung koordinat Chunk (16x16)
    local chunkX = x >> 4
    local chunkZ = z >> 4
    
    -- 2. Muat data chunk dari file
    local chunkData = self:loadChunk(chunkX, chunkZ)
    if not chunkData then return end
    
    -- 3. Update data blok di dalam memori (Ini bagian teknisnya)
    -- Secara sederhana: Kita cari posisi bit blok tersebut di dalam sub-chunk
    -- dan menggantinya dengan ID blok baru.
    local updatedData = self:injectBlockToChunk(chunkData, x & 15, y, z & 15, blockId)
    
    -- 4. Simpan kembali ke file
    self:saveChunk(chunkX, chunkZ, updatedData)
    
    -- 5. Broadcast perubahan ke pemain lain (Penting!)
    self:broadcastBlockChange(x, y, z, blockId)
    
    print(string.format("[World] %s menaruh blok %d di %d, %d, %d", session.username, blockId, x, y, z))
end
function Core:broadcastPacket(packetPayload, excludeSession)
    for id, session in pairs(self.players) do
        if session.status == "INGAME" and session ~= excludeSession then
            self:sendGamePacket(session, packetPayload)
        end
    end
end
function Core:broadcastBlockChange(x, y, z, blockId, excludeSession)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x15) -- Packet ID: UpdateBlock
    
    stream:putVarInt(x)
    stream:putUnsignedVarInt(y)
    stream:putVarInt(z)
    
    stream:putUnsignedVarInt(blockId) -- Block Runtime ID
    stream:putUnsignedVarInt(0x3)     -- Flags (0x3 = All neighbors updated)
    stream:putUnsignedVarInt(0)       -- Layer (0 = Normal blocks)

    self:broadcastPacket(stream:getBuffer(), excludeSession)
end
function Core:spawnPlayerToAll(newPlayerSession)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x0c) -- AddPlayerPacket
    
    stream:putUUID(newPlayerSession.uuid)
    stream:putString(newPlayerSession.username)
    stream:putVarLong(newPlayerSession.entityId) -- ID unik di server
    stream:putUnsignedVarLong(newPlayerSession.entityId)
    
    stream:putFloat(newPlayerSession.x)
    stream:putFloat(newPlayerSession.y)
    stream:putFloat(newPlayerSession.z)
    
    -- ... (ditambah data metadata seperti skin dan item yang dipegang)
    
    self:broadcastPacket(stream:getBuffer(), newPlayerSession)
end
-- Di Core.lua
function Core:setBlock(x, y, z, blockId)
    -- Logika manipulasi world yang kita buat sebelumnya
    local chunkX, chunkZ = x >> 4, z >> 4
    local chunkData = self:loadChunk(chunkX, chunkZ)
    
    if chunkData then
        local updatedData = self:injectBlockToChunk(chunkData, x & 15, y, z & 15, blockId)
        self:saveChunk(chunkX, chunkZ, updatedData)
        self:broadcastBlockChange(x, y, z, blockId)
        return true
    end
    return false
end

-- Tambahkan helper untuk mengecek sisa stream
function BinaryStream:feof()
    return self.offset > #self.buffer
end

-- Tambahkan helper untuk membaca N byte string
function BinaryStream:get(length)
    local str = string.sub(self.buffer, self.offset, self.offset + length - 1)
    self.offset = self.offset + length
    return str
end

function Core:handleFrameSet(data, session)
    local stream = BinaryStream.new(data)
    local headerId = stream:getByte() -- 0x80 - 0x8d
    local seqNumber = stream:getLTriad() -- Nomor urut paket (Little Endian 24-bit)

    -- 1. PENTING: Kirim ACK (Acknowledge)
    -- Memberitahu Client bahwa kita menerima paket urutan ini.
    -- Jika tidak ada ini, Client akan Disconnect (Timeout).
    self:sendACK(session, seqNumber)

    -- Loop selama stream belum habis
    while not stream:feof() do
        -- Cek apakah sisa data cukup untuk header minimal (3 byte: Flag + Length)
        if #stream.buffer - stream.offset + 1 < 3 then break end

        -- A. Baca Flags & Panjang
        local flags = stream:getByte()
        local lengthInBits = stream:getShort()
        local lengthInBytes = math.ceil(lengthInBits / 8)

        local reliability = (flags & 0xE0) >> 5
        local hasSplit = (flags & 0x10) ~= 0

        -- B. Baca Reliability Layer (Header Tambahan)
        -- Kita baca saja agar offset stream bergeser dengan benar
        if reliability >= 2 and reliability <= 4 then
            stream:getLTriad() -- Message Index (24-bit LE)
        elseif reliability >= 6 and reliability <= 7 then
            stream:getLTriad() -- Message Index (24-bit LE)
            stream:getLTriad() -- Order Index (24-bit LE)
            stream:getByte()   -- Order Channel (1 byte)
        end

        -- C. Baca Split Layer (JIKA ADA)
        -- INI HARUS DIBACA SEBELUM MENGAMBIL PAYLOAD
        local splitCount, splitId, splitIndex = 0, 0, 0
        
        if hasSplit then
            -- RakNet Split Info menggunakan BIG ENDIAN (BE)
            splitCount = stream:getInt()   -- 4 byte BE
            splitId = stream:getShort()    -- 2 byte BE
            splitIndex = stream:getInt()   -- 4 byte BE
        end

        -- D. Baca Payload (Body)
        -- Payload yang dibaca sekarang sudah bersih dari header Split/Reliability
        local payload = stream:get(lengthInBytes)

        -- E. Proses Data
        if hasSplit then
            -- Jika paket terbelah, masukkan ke defragmenter
            self:handleDefragmentation(session, payload, splitCount, splitId, splitIndex)
        else
            -- Jika paket utuh, cek apakah ini Game Packet (0xFE)
            if string.byte(payload, 1) == 0xfe then
                self:handleBatch(payload, session)
            end
        end
    end
end

-- Fungsi Wajib: Mengirim ACK
function Core:sendACK(session, seqNumber)
    local stream = BinaryStream.new()
    stream:putByte(0xc0) -- ID ACK
    
    -- Struktur ACK sederhana (Single Record)
    stream:putShort(0) -- Record Count: 0 (artinya hanya 1 record)
    stream:putBoolean(true) -- Single Sequence Number? True
    stream:putLTriad(seqNumber) -- Nomor urut yang kita terima tadi
    
    -- Kirim langsung tanpa encapsulation
    self.socket:sendto(stream:getBuffer(), session.ip, session.port)
end


function Core:sendChunk(session, chunkX, chunkZ)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x3a) -- LevelChunkPacket ID
    stream:putVarInt(chunkX)
    stream:putVarInt(chunkZ)
    stream:putUnsignedVarInt(1)    -- Jumlah Sub-Chunk (kita kirim 1 saja untuk ground)
    stream:putBoolean(false)       -- Caching disabled

    -- Membuat Data Sub-Chunk (Y: 0-15)
    local subChunk = self:generateSubChunk()
    
    -- Metadata Tambahan (Biome & Border)
    -- Bedrock butuh 25 byte padding untuk biome sederhana di akhir data chunk
    local footer = string.rep("\x00", 25) 
    
    local fullData = subChunk .. footer
    stream:putUnsignedVarInt(#fullData)
    stream.buffer = stream.buffer .. fullData

    self:sendGamePacket(session, stream:getBuffer())
end
function Core:generateSubChunk()
    local stream = BinaryStream.new()
    stream:putByte(8) -- Version 8
    stream:putByte(1) -- 1 Layer
    
    -- Block Storage (Paletted)
    stream:putByte((0 << 1) | 1) -- 1 bit per block
    
    for i = 1, 128 do
        stream:putLInt(0) -- Semua blok merujuk ke index 0 di palet
    end

    -- Palet
    stream:putLInt(1) -- 1 jenis blok
    stream:putLInt(1) -- Runtime ID 1 biasanya adalah Grass/Air tergantung tabel versi
    
    return stream:getBuffer()
end


function Core:handleDefragmentation(session, payload, splitCount, splitId, splitIndex)
    if not session.fragments[splitId] then
        session.fragments[splitId] = {}
    end

    -- Simpan potongan paket
    session.fragments[splitId][splitIndex] = payload

    -- Cek apakah semua potongan sudah terkumpul
    local count = 0
    for _ in pairs(session.fragments[splitId]) do count = count + 1 end

    if count == splitCount then
        -- Susun ulang paket
        local fullPayload = ""
        for i = 0, splitCount - 1 do
            fullPayload = fullPayload .. session.fragments[splitId][i]
        end
        
        -- Bersihkan memori
        session.fragments[splitId] = nil
        
        -- Kirim ke pemroses batch
        if string.byte(fullPayload, 1) == 0xfe then
            self:handleBatch(fullPayload, session)
        end
    end
end

function Core:processBatch(rawData, session)
    local stream = BinaryStream.new(rawData)
    
    while stream.offset <= #rawData do
        local packetLength = stream:getUnsignedVarInt()
        local packetData = string.sub(rawData, stream.offset, stream.offset + packetLength - 1)
        stream.offset = stream.offset + packetLength
        
        local gameStream = BinaryStream.new(packetData)
        local packetId = gameStream:getUnsignedVarInt()
        
        if packetId == 0x01 then -- Login Packet
            print("[Login] Paket Login diterima dari " .. session.address)
            self:handleLogin(packetData, session.address, session.port)
        end
    end
end
-- Fungsi pembantu untuk mendapatkan ID Paket berdasarkan versi pemain
function Core:getPacketId(playerName, internalName)
    local player = self:getPlayerByName(playerName)
    local protocol = player and player.protocol or 775
    
    if PacketIds[protocol] and PacketIds[protocol][internalName] then
        return PacketIds[protocol][internalName]
    end
    return nil
end

local RakNet = {
    -- Packet IDs
    ID_OPEN_CONNECTION_REQUEST_1 = 0x05,
    ID_OPEN_CONNECTION_REPLY_1   = 0x06,
    ID_OPEN_CONNECTION_REQUEST_2 = 0x07,
    ID_OPEN_CONNECTION_REPLY_2   = 0x08,
    
    MAGIC = "\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x12\x34\x56\x78"
}
Core.supportedProtocols = {
    [649] = "1.20.80",
    [662] = "1.21.0",
    [671] = "1.21.2",
    [775] = "1.21.131"
}
-- Tambahkan variabel ini di bagian atas Core
Core.consoleBuffer = ""

function Core:handleConsoleInput()
    -- Gunakan io.read dengan cerdas atau library ffi untuk non-blocking
    -- Ini adalah versi sederhana untuk mendeteksi perintah terminal
    local input = io.read(0) -- Catatan: ini mungkin butuh penyesuaian tergantung OS
    
    if input and input ~= "" then
        local consoleSender = {
            username = "CONSOLE",
            status = "INGAME",
            protocol = 775
        }
        -- Tambahkan '/' otomatis jika user lupa mengetiknya di terminal
        if input:sub(1,1) ~= "/" then input = "/" .. input end
        self:handleChat(consoleSender, input)
    end
end

-- Mengirim pesan ke SATU pemain saja
function Core:sendMessage(player, message)
    if player.username == "CONSOLE" then
        print("\27[36m[Console]\27[0m " .. message)
        return
    end

    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x09) -- Text Packet ID
    stream:putByte(1)              -- Type: RAW (Pesan langsung)
    stream:putBoolean(false)       -- Is Localization
    stream:putString("")           -- Source (Kosongkan jika RAW)
    stream:putString(message)      -- Isi Pesan
    stream:putString("")           -- XUID
    stream:putString("")           -- Platform ID

    self:sendGamePacket(player, stream:getBuffer())
end

-- Mengirim pesan ke SEMUA pemain yang online
function Core:broadcastChat(message)
    for _, session in pairs(self.players) do
        if session.status == "INGAME" then
            self:sendMessage(session, message)
        end
    end
end

function Core:decodeBase64(data)
    -- Kamu butuh library base64 asli di sini, ini hanya placeholder
    return data 
end
function Core:handleLoginPacket(packetData, session)
    local stream = BinaryStream.new(packetData)
    -- Lewati Packet ID yang sudah dibaca (0x01)
    
    local protocol = stream:getInt() -- Versi protokol (misal: 671)
    print("[Login] Protokol Pemain: " .. protocol)

    -- Ambil data Connection Request (berisi rantai JWT)
    local requestData = stream:getString() 
    
    -- Bedah JSON yang membungkus JWT
    local success, json = pcall(cjson.decode, requestData)
    if not success or not json.chain then 
        print("[Error] Format Login tidak valid")
        return 
    end

    -- Ambil 'chain' (rantai sertifikat)
    for _, jwt in ipairs(json.chain) do
        local payload = self:decodeJWTPayload(jwt)
        if payload and payload.extraData then
            session.username = payload.extraData.displayName
            session.xuid = payload.extraData.XUID
            session.uuid = payload.extraData.identity
            
            print(string.format("\27[32m[Auth]\27[0m %s berhasil login! (XUID: %s)", session.username, session.xuid))
        end
    end
end

-- Fungsi sederhana untuk mengambil data dari JWT tanpa verifikasi kunci (unsafely)
function Core:decodeJWTPayload(jwt)
    -- Format JWT: header.payload.signature
    local parts = {}
    for part in jwt:gmatch("[^.]+") do
        table.insert(parts, part)
    end

    if #parts < 2 then return nil end

    -- Base64 Decode bagian tengah (payload)
    -- Kamu butuh fungsi helper base64_decode di sini
    local rawJson = self:base64_decode(parts[2])
    return pcall(cjson.decode, rawJson) and cjson.decode(rawJson) or nil
end
function Core:acceptPlayer(session)
    -- 1. Kirim Play Status (SUCCESS)
    local playStatus = BinaryStream.new()
    playStatus:putUnsignedVarInt(0x02) -- Packet ID
    playStatus:putInt(0) -- Status: Login Success
    self:sendGamePacket(session, playStatus:getBuffer())

    -- 2. Kirim ResourcePacksInfo (Kosongkan saja dulu)
    local resInfo = BinaryStream.new()
    resInfo:putUnsignedVarInt(0x06)
    resInfo:putBoolean(false) -- Must accept
    resInfo:putBoolean(false) -- Has scripts
    resInfo:putShort(0) -- Behavior pack count
    resInfo:putShort(0) -- Resource pack count
    self:sendGamePacket(session, resInfo:getBuffer())
end

-- Fungsi pembantu untuk membungkus & mengompres paket
function Core:sendGamePacket(session, payload)
    local batch = BinaryStream.new()
    batch:putByte(0xfe) -- Batch Header
    
    -- Kompresi Zlib
    local deflated = zlib.deflate()(payload, "finish")
    batch.buffer = batch.buffer .. deflated
    
    -- Bungkus ke RakNet Frame (Harus pakai fungsi pengiriman RakNet kamu)
    self:sendRakNetFrame(session, batch:getBuffer())
end
function Core:sendStartGame(session)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x0b) -- Packet ID: StartGame

    -- 1. Identity & Position
    stream:putVarLong(session.entityId or 1) -- Entity Runtime ID
    stream:putUnsignedVarLong(session.entityId or 1) -- Entity Unique ID
    stream:putInt(1) -- Player Gamemode (1 = Creative)
    
    -- Posisi Player (Vector3 Float)
    stream:putFloat(0.0)  -- X
    stream:putFloat(100.0) -- Y (Tinggi agar tidak spawn di dalam tanah)
    stream:putFloat(0.0)  -- Z
    
    -- Rotasi (Pitch & Yaw)
    stream:putFloat(0.0) 
    stream:putFloat(0.0)

    -- 2. Level Settings
    stream:putLong(12345) -- Seed
    stream:putShort(0)    -- Spawn Biome Type (0 = Default)
    stream:putString("overworld") -- Biome Name
    stream:putInt(0)      -- Dimension (0 = Overworld)
    stream:putInt(1)      -- Generator (1 = Infinite)
    stream:putInt(0)      -- World Gamemode
    stream:putInt(0)      -- Difficulty
    stream:putInt(0)      -- Spawn X
    stream:putInt(100)    -- Spawn Y
    stream:putInt(0)      -- Spawn Z
    
    -- 3. World Rules & Flags
    stream:putBoolean(false) -- Achievements Disabled
    stream:putInt(-1)        -- Day Cycle Time
    stream:putInt(0)         -- Education Edition Offer
    stream:putBoolean(false) -- Education Features
    stream:putString("")     -- Biome Override
    stream:putBoolean(true)  -- Confirmed Platform Locked
    
    -- 4. Game Rules (Kosongkan untuk simpel)
    stream:putUnsignedVarInt(0) 

    -- 5. Versioning & ID
    stream:putString("")      -- Level ID
    stream:putString("MineLua Server") -- World Name
    stream:putString("1.21.0") -- Version String (Sesuaikan protokol)

    -- 6. Item Definitions (Wajib ada di versi baru!)
    -- Kita kirim 0 dulu agar tidak perlu list panjang, 
    -- tapi client butuh ItemComponentPacket nantinya.
    stream:putUnsignedVarInt(0) 
    stream:putBoolean(false) -- Is Experimental
    
    self:sendGamePacket(session, stream:getBuffer())
    print("[Network] StartGamePacket dikirim untuk " .. (session.username or "Player"))
end

function Core:sendCreativeContent(session)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x91) -- Packet ID: CreativeContent

    -- Contoh sederhana: Kita kirim 1 item saja (Grass Block)
    -- Catatan: ID ini bisa berbeda tergantung versi protokol. 
    -- Untuk 1.21, Grass Block biasanya memiliki Network ID sekitar 2.
    local items = {
        {networkId = 2, blockRuntimeId = 12345} 
    }

    stream:putUnsignedVarInt(#items) -- Jumlah item

    for i, item in ipairs(items) do
        stream:putUnsignedVarInt(i) -- Entry ID
        
        -- Item Descriptor
        stream:putVarInt(item.networkId)
        stream:putShort(0) -- Metadata/Aux
        stream:putUnsignedVarInt(0) -- NBT Count
        
        -- Tambahan metadata untuk versi 1.21
        stream:putUnsignedVarInt(0) -- Group ID
    end

    self:sendGamePacket(session, stream:getBuffer())
end

function Core:onSuccessfulLogin(session)
    -- 1. Login Success
    self:sendPlayStatus(session, 0)
    
    -- 2. Resource Packs (Wajib kirim Info lalu Stack)
    self:sendResourcePacksInfo(session)
    -- Tunggu client merespon dengan ResourcePackClientResponse, 
    -- baru kemudian kirim StartGame. (Ini disingkat untuk contoh)
    
    -- 3. World Initialization
    self:sendStartGame(session)
    self:sendItemComponents(session) -- Wajib di 1.21
    self:sendCreativeContent(session)
    
    -- 4. Kirim Chunk Awal
    self:sendChunk(session, 0, 0)
    
    -- 5. Network Chunk Publisher (Memberitahu client radius render)
    self:updateNetworkChunkPublisher(session)
    
    -- 6. FINAL: Spawn Status
    self:sendPlayStatus(session, 3) 
    
    session.status = "INGAME"
end

function Core:handlePlayerAuthInput(packetData, session)
    local stream = BinaryStream.new(packetData)
    stream:getUnsignedVarInt() -- Skip ID 0x90

    local pitch = stream:getFloat()
    local yaw = stream:getFloat()
    local x = stream:getFloat()
    local y = stream:getFloat()
    local z = stream:getFloat()
    
    -- Lewati data gerakan analog (moveVector)
    stream.offset = stream.offset + 8 
    
    -- Ambil Input Data (Bitmask)
    local inputData = stream:getUnsignedVarLong()
    
    -- Deteksi status menggunakan Bitwise AND
    -- Nilai bit konstan untuk Bedrock 1.21:
    local isSneaking = (inputData & (1 << 3)) ~= 0
    local isSprinting = (inputData & (1 << 9)) ~= 0
    local isJumping = (inputData & (1 << 2)) ~= 0

    -- Simpan ke sesi agar bisa digunakan plugin atau broadcast
    session.isSneaking = isSneaking
    session.isSprinting = isSprinting

    -- Update posisi
    session.x, session.y, session.z = x, y, z
    session.pitch, session.yaw = pitch, yaw

    -- Beritahu pemain lain tentang perubahan status ini
    self:broadcastEntityEvent(session)
    self:broadcastMovement(session)
end
function Core:broadcastEntityEvent(player)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x27) -- SetEntityDataPacket

    stream:putUnsignedVarLong(player.entityId)
    
    -- Membuat Flag Metadata
    local flags = 0
    if player.isSneaking then flags = flags | (1 << 1) end -- DATA_FLAG_SNEAKING
    if player.isSprinting then flags = flags | (1 << 3) end -- DATA_FLAG_SPRINTING
    
    -- Tulis metadata (menggunakan fungsi writeEntityMetadata yang kita buat sebelumnya)
    self:writeEntityMetadata(stream, {
        [0] = {type = "long", value = flags} 
    })
    stream:putUnsignedVarInt(0) -- Tick

    self:broadcastPacket(stream:getBuffer(), player)
end

function Core:broadcastMovement(movingPlayer)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x13) -- Packet ID: MovePlayer

    stream:putUnsignedVarLong(movingPlayer.entityId) -- ID pemain yang bergerak
    stream:putFloat(movingPlayer.x)
    stream:putFloat(movingPlayer.y)
    stream:putFloat(movingPlayer.z)
    stream:putFloat(movingPlayer.pitch)
    stream:putFloat(movingPlayer.yaw)
    stream:putFloat(movingPlayer.yaw) -- Head Yaw
    
    stream:putByte(0) -- Mode (0 = Normal)
    stream:putBoolean(movingPlayer.onGround or true)
    stream:putUnsignedVarLong(0) -- Riding Entity ID

    -- Kirim ke semua pemain kecuali dirinya sendiri
    self:broadcastPacket(stream:getBuffer(), movingPlayer)
end
function Core:updateNetworkChunkPublisher(session)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x79) -- NetworkChunkPublisherUpdate
    
    stream:putVarInt(math.floor(session.x))
    stream:putVarInt(math.floor(session.y))
    stream:putVarInt(math.floor(session.z))
    stream:putUnsignedVarInt(64) -- Radius muat (dalam blok)

    self:sendGamePacket(session, stream:getBuffer())
end

function Core:sendItemComponents(session)
    local stream = BinaryStream.new()
    stream:putUnsignedVarInt(0x106) -- Packet ID: ItemComponentPacket

    -- Jumlah Item (Kita set 0 untuk memulai tanpa custom items)
    stream:putUnsignedVarInt(0) 

    self:sendGamePacket(session, stream:getBuffer())
    print("[Network] ItemComponentPacket dikirim (Empty).")
end

function Core:handleLogin(data, ip, port)
    local stream = BinaryStream.new(data)
    local protocolVersion = stream:getLInt()
    
    local versionLabel = self.supportedProtocols[protocolVersion] or "Unknown Version"
    print(string.format("\27[33m[Login]\27[0m Mencoba masuk dengan Protokol: %d (%s)", protocolVersion, versionLabel))

    -- 1. LOGIKA MULTIPROTOCOL: Cek apakah kita dukung atau perlu translasi
    if protocolVersion < 775 then
        print("[Multiprotocol] Versi lama terdeteksi. Mengaktifkan Translator v" .. protocolVersion)
        -- Di sini kamu bisa memanggil fungsi khusus: self:translateFromOldVersion(stream, protocolVersion)
    end

    -- 2. Ambil panjang payload (JWT Chain)
    -- Catatan: Setelah protocol, biasanya ada string panjang payload
    local length = stream:getLInt() 
    local payload = string.sub(data, stream.offset, stream.offset + length - 1)
    
    -- 3. Decode JWT/JSON
    local success, decoded = pcall(cjson.decode, payload)
    
    if success and decoded.chain then
        for _, chain in ipairs(decoded.chain) do
            -- Parsing JWT (Header.Payload.Signature)
            local _, payloadBase64 = chain:match("([^.]+).([^.]+).([^.]+)")
            
            if payloadBase64 then
                local userData = self:decodeBase64(payloadBase64)
                local userJson = pcall(cjson.decode, userData) and cjson.decode(userData) or {}
                
                if userJson.extraData then
                    local username = userJson.extraData.displayName
                    local xuid = userJson.extraData.XUID
                    local uuid = userJson.extraData.identity -- UUID unik pemain
                    
                    print(string.format("\27[32m[Auth]\27[0m %s terverifikasi (XUID: %s)", username, xuid))

                    -- Simpan informasi protokol ke dalam sesi pemain
    local identifier = ip .. ":" .. port
    if self.players[identifier] then
        self.players[identifier].protocol = protocolVersion
                        self.players[identifier].username = username
                        self.players[identifier].uuid = uuid
                    end

                    -- Trigger Event ke Plugin dengan membawa info versi
                    PluginManager.callEvent("onPlayerPreLogin", username, ip, protocolVersion)
                end
            end
        end
    else
        print("[Error] Gagal men-decode paket Login. Mungkin kompresi atau versi tidak cocok.")
    end
end

function Core:getPlayerByName(name)
    for _, player in pairs(self.players) do
        if player.username == name then return player end
    end
    return nil
end


function Core:handleOpenConnectionRequest1(data, ip, port)
    -- Ambil byte ke-18 (Protokol RakNet)
    local raknetProtocol = string.byte(data, 18)
    
    -- Jika versi terbaru (11) atau yang lama (10), kita izinkan saja
    if raknetProtocol < 10 then
        print("[RakNet] Versi protokol terlalu tua: " .. raknetProtocol)
        return
    end

    local reply = BinaryStream.new()
    reply:putByte(0x06) -- Reply 1
    reply.buffer = reply.buffer .. self.RAKNET_MAGIC
    reply:putLong(12345678) 
    reply:putByte(0) -- Security
    reply:putShort(#data + 28) -- MTU
    
    self.socket:sendto(reply:getBuffer(), ip, port)
end



-- Membalas Open Connection Request 2 (Paket 0x07)
function Core:handleOpenConnectionRequest2(data, ip, port)
    local stream = BinaryStream.new(data)
    stream.offset = 17 -- Lewati ID dan Magic
    -- (Di sini biasanya ada pengecekan MTU dan Port Server)
    
    print("[RakNet] Request 2 (Handshake Selesai) dari " .. ip)

    local reply = BinaryStream.new()
    reply:putByte(RakNet.ID_OPEN_CONNECTION_REPLY_2)
    reply.buffer = reply.buffer .. RakNet.MAGIC
    reply:putLong(12345678) -- Server ID
    reply:putShort(port)    -- Client Port
    reply:putShort(1492)    -- MTU Size
    reply:putByte(0)        -- Security
    
    self.socket:sendto(reply:getBuffer(), ip, port)
end

function Core:init()
    self.socket = assert(socket.udp())
    self.socket:settimeout(0)
    self.socket:setsockname("0.0.0.0", 19132)
    
    print("\27[32m=== MINELUA ===\27[0m")
    PluginManager.loadPlugins()
    self:mainLoop()
end

function Core:mainLoop()
    print("\27[32m[Console]\27[0m Menunggu perintah... (Ketik /help untuk bantuan)")
    
    while self.isRunning do
        -- 1. Gunakan socket.select untuk menunggu paket (0.01 detik)
        -- Ini jauh lebih efisien daripada socket.sleep
        local readable, _, _ = socket.select({self.socket}, nil, 0.01)

        -- 2. Jika ada data UDP masuk
        if readable and readable[1] == self.socket then
            local data, ip, port = self.socket:receivefrom()
            if data then
                self:processIncomingPacket(data, ip, port)
            end
        end

        -- 3. LOGIKA TIK (Untuk task terjadwal/anti-cheat)
        self:tick()

        -- 4. LOGIKA CONSOLE (Tantangan Non-Blocking)
        -- Karena io.read() blocking, kita gunakan trik 'pcall' 
        -- atau integrasi dengan loop sistem jika kamu di Linux/Termux.
        -- Untuk sekarang, kita buat handler perintah Console-nya:
        self:handleConsoleInput()
    end
end

-- Fungsi pemisah untuk merapikan mainLoop
function Core:processIncomingPacket(data, ip, port)
    local identifier = ip .. ":" .. port
    local stream = BinaryStream.new(data)
    local packetId = stream:getByte()

    if not self.players[identifier] then
        -- Logika Unconnected (Handshake awal)
        if packetId == 0x01 then
            self:handlePing(ip, port)
        elseif packetId == 0x05 then
            self:handleOpenConnectionRequest1(data, ip, port)
            self:createSession(ip, port, identifier)
        end
    else
        -- Logika Connected
        local session = self.players[identifier]
        session.lastUpdate = os.time()

        if packetId == 0x07 then
            self:handleOpenConnectionRequest2(data, ip, port)
            session.status = "CONNECTED"
        elseif packetId >= 0x80 and packetId <= 0x8d then
            self:handleFrameSet(data, session)
        else
            session:handlePacket(packetId, stream)
        end
    end
    
    PluginManager.callEvent("onPacketReceive", packetId, ip, port)
end
function Core:handleConsoleInput()
    -- Catatan: Di Lua standar, membaca stdin tanpa blocking butuh library 'lanes' atau 'posix'.
    -- Sebagai alternatif 'workaround' untuk MineLua di Terminal:
    -- Kita buat objek "CONSOLE" yang berperan seolah-olah dia pemain sakti.
    
    local consolePlayer = {
        username = "CONSOLE",
        protocol = 775,
        status = "INGAME",
        -- Dummy function agar tidak error saat plugin memanggil sendMessage
        sendMessage = function(msg) print("\27[36m[Console Response]\27[0m " .. msg) end
    }

    -- Jika kamu ingin input console benar-benar aktif, kamu bisa menggunakan 
    -- sistem command queue. Untuk saat ini, kita hubungkan ke sistem chat:
    -- self:handleChat(consolePlayer, inputDariUser)
end

Core.commands = {}

function Core:handleChat(player, message)
    -- 1. Deteksi Perintah (Dimulai dengan /)
    if message:sub(1, 1) == "/" then
        local args = {}
        for word in message:gmatch("%S+") do 
            table.insert(args, word) 
        end
        
        local commandName = table.remove(args, 1):sub(2):lower()

        -- Logika Prioritas 1: Kirim ke Plugin (AdminTools, dll)
        -- Jika plugin mengembalikan 'true', berarti perintah sudah ditangani
        local handled = PluginManager.callEvent("onCommand", player, commandName, args)
        if handled then return end

        -- Logika Prioritas 2: Perintah Internal Core (Jika ada)
        if self.commands[commandName] then
            local success, err = pcall(self.commands[commandName], player, args)
            if not success then 
                print("\27[31m[Command Error]\27[0m /" .. commandName .. ": " .. tostring(err))
            end
            return
        end

        -- Jika tidak ada yang kenal perintahnya
        self:sendMessage(player, "§cPerintah /" .. commandName .. " tidak dikenal.")
        
    else
        -- 2. Logika Chat Biasa
        print(string.format("[Chat] %s: %s", player.username or "Unknown", message))
        
        -- Event untuk plugin (misal filter kata kasar)
        PluginManager.callEvent("onPlayerChat", player, message)
        
        -- Kirim ke semua orang dengan format chat
        local formattedMessage = string.format("§7%s §f> %s", player.username or "Player", message)
        self:broadcastChat(formattedMessage)
    end
end



function Core:registerCommand(name, callback)
    self.commands[name] = callback
    print("[Command] Terdaftar: /" .. name)
end


-- Di Core.lua (handlePing)
function Core:handlePing(ip, port)
    local protocol, version = PacketIds.getLatest()
    
    local stream = BinaryStream.new()
    stream:putByte(0x1c) 
    stream:putLong(os.time())
    stream:putLong(987654321) -- Server ID
    
    -- Format String RakNet Bedrock
    local motd = {
        "MCPE",
        "MineLua Server",     -- Nama Server
        protocol,             -- 775
        version,              -- 1.21.132
        "0",                  -- Online
        "100",                 -- Max
        "123456789",          -- GUID
        "MineLua",            -- Subname
        "Survival",           -- Gamemode
        "1",                  -- Port IPv4
        "19132",
        "19132"
    }
    
    local serverName = table.concat(motd, ";") .. ";"
    local payload = stream:getBuffer() .. self.RAKNET_MAGIC
    
    local finalStream = BinaryStream.new(payload)
    finalStream:putString(serverName)
    
    self.socket:sendto(finalStream:getBuffer(), ip, port)
end


function Core:sendTranslatedMessage(player, message)
    -- Ambil ID TEXT_PACKET sesuai protokol player tersebut
    local packetId = PacketIds.get(player.protocol, "TEXT")
    
    local stream = BinaryStream.new()
    stream:putByte(0xfe) -- Game Packet Header
    stream:putUnsignedVarInt(packetId)
    
    -- Struktur paket Text
    stream:putByte(1) -- Type Raw
    stream:putBoolean(false) -- Is Localization
    stream:putString("") -- Source
    stream:putString(message) -- Content
    -- ... sisa field lainnya
    
    self:sendPacket(player, stream:getBuffer())
end

-- Membuat Sesi Baru (Handshake dimulai)
function Core:createSession(ip, port, id)
    print("[Network] Membuat sesi baru untuk " .. id)
    self.players[id] = {
        address = ip,
        port = port,
        status = "CONNECTING",
        lastUpdate = os.time(),
        fragments = {}, -- Tempat menyimpan paket yang terbelah
        handlePacket = function(session, packetId, stream)
            -- Di sini logika RakNet State Machine bekerja
            print(string.format("[Session %s] Paket masuk: 0x%02x", id, packetId))
            session.lastUpdate = os.time()
        end
    }
end

Core:init()
