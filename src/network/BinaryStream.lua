local BinaryStream = {}
BinaryStream.__index = BinaryStream

function BinaryStream.new(buffer)
    return setmetatable({
        buffer = buffer or "",
        offset = 1
    }, BinaryStream)
end

function BinaryStream:getBuffer()
    return self.buffer
end

-- --- READ METHODS ---

function BinaryStream:getByte()
    if self.offset > #self.buffer then return 0 end
    local b = string.byte(self.buffer, self.offset)
    self.offset = self.offset + 1
    return b
end

-- --- WRITE METHODS ---
-- Tambahkan ke BinaryStream.lua
function BinaryStream:putMagic()
    local magic = "\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x12\x34\x56\x78"
    self.buffer = self.buffer .. magic
end

function BinaryStream:getMagic()
    local magic = string.sub(self.buffer, self.offset, self.offset + 15)
    self.offset = self.offset + 16
    return magic
end
function BinaryStream:putUUID(uuid)
    -- UUID biasanya dikirim dalam 16 byte raw
    -- Kamu bisa gunakan library 'uuid' untuk generate atau convert
    self.buffer = self.buffer .. uuid
end

function BinaryStream:putItem(id, count)
    if id == 0 then
        self:putVarInt(0) -- Item kosong
        return
    end
    self:putVarInt(id)
    self:putShort(count)
    self:putUnsignedVarInt(0) -- Metadata/NBT count
    -- Di 1.21, ada tambahan 'CanPlaceOn' dan 'CanDestroy' list
    self:putVarInt(0) -- CanPlaceOn count
    self:putVarInt(0) -- CanDestroy count
end

function BinaryStream:putByte(v)
    self.buffer = self.buffer .. string.char(v & 0xFF)
end

-- Menulis String dengan panjang Short (2 byte Big Endian)
-- WAJIB UNTUK UNCONNECTED PONG
function BinaryStream:putString16(v)
    self:putShort( #v ) -- Panjang string
    self.buffer = self.buffer .. v
end

-- Menulis Short (16-bit Big Endian)
function BinaryStream:putShort(v)
    self.buffer = self.buffer .. string.char((v >> 8) & 0xFF, v & 0xFF)
end

-- Menulis Long (64-bit Big Endian)
-- RakNet menggunakan Big Endian untuk Time & GUID
function BinaryStream:putLong(v)
    -- Ini implementasi sederhana untuk Lua 5.3+
    -- Membagi 64 bit menjadi 8 byte
    local b1 = (v >> 56) & 0xFF
    local b2 = (v >> 48) & 0xFF
    local b3 = (v >> 40) & 0xFF
    local b4 = (v >> 32) & 0xFF
    local b5 = (v >> 24) & 0xFF
    local b6 = (v >> 16) & 0xFF
    local b7 = (v >> 8) & 0xFF
    local b8 = v & 0xFF
    self.buffer = self.buffer .. string.char(b1, b2, b3, b4, b5, b6, b7, b8)
end

return BinaryStream
