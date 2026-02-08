local BinaryStream = {}
BinaryStream.__index = BinaryStream

-- Inisialisasi Stream baru
function BinaryStream.new(buffer)
    return setmetatable({
        buffer = buffer or "",
        offset = 1
    }, BinaryStream)
end
function BinaryStream:putRaw(data)
    self.buffer = self.buffer .. data
end

function BinaryStream:putBoolean(v)
    self:putByte(v and 1 or 0)
end


-- Mendapatkan seluruh isi buffer biner
function BinaryStream:getBuffer()
    return self.buffer
end

-- Cek apakah pembacaan sudah mencapai akhir file
function BinaryStream:feof()
    return self.offset > #self.buffer
end

-- --- READ METHODS (MEMBACA DATA) ---

-- Membaca 1 byte
function BinaryStream:getByte()
    if self.offset > #self.buffer then return 0 end
    local b = string.byte(self.buffer, self.offset) or 0
    self.offset = self.offset + 1
    return b
end

-- Membaca Little Endian Int (32-bit)
function BinaryStream:getLInt()
    local b1, b2, b3, b4 = string.byte(self.buffer, self.offset, self.offset + 3)
    self.offset = self.offset + 4
    return b1 + (b2 << 8) + (b3 << 16) + (b4 << 24)
end

-- Membaca Little Endian Triad (24-bit) - Sering digunakan RakNet
function BinaryStream:getLTriad()
    local b1, b2, b3 = string.byte(self.buffer, self.offset, self.offset + 2)
    self.offset = self.offset + 3
    return b1 + (b2 << 8) + (b3 << 16)
end

-- Membaca Unsigned VarInt (Minecraft Protocol)
function BinaryStream:getUnsignedVarInt()
    local value, shift = 0, 0
    repeat
        local byte = self:getByte()
        value = value | ((byte & 0x7F) << shift)
        shift = shift + 7
    until (byte & 0x80) == 0
    return value
end

-- Membaca Magic Number RakNet (16 byte)
function BinaryStream:getMagic()
    local magic = string.sub(self.buffer, self.offset, self.offset + 15)
    self.offset = self.offset + 16
    return magic
end

-- Membaca data mentah berdasarkan panjang (N byte)
function BinaryStream:get(length)
    local str = string.sub(self.buffer, self.offset, self.offset + length - 1)
    self.offset = self.offset + length
    return str
end

-- --- WRITE METHODS (MENULIS DATA) ---

-- Menulis 1 byte
function BinaryStream:putByte(v)
    self.buffer = self.buffer .. string.char(v & 0xFF)
end

-- Menulis Magic Number RakNet
function BinaryStream:putMagic()
    local magic = "\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x12\x34\x56\x78"
    self.buffer = self.buffer .. magic
end

-- Menulis UUID (16 byte raw)
function BinaryStream:putUUID(uuid)
    self.buffer = self.buffer .. uuid
end

-- Menulis Short (16-bit Big Endian)
function BinaryStream:putShort(v)
    self.buffer = self.buffer .. string.char((v >> 8) & 0xFF, v & 0xFF)
end

-- Menulis Little Endian Int (32-bit)
function BinaryStream:putLInt(v)
    self.buffer = self.buffer .. string.pack("<i4", v)
end

-- Menulis Long (64-bit Big Endian) - Digunakan untuk GUID/Time
function BinaryStream:putLong(v)
    -- Menggunakan string.pack ">j" (8-byte signed int Big Endian)
    -- Ini jauh lebih aman daripada perhitungan bitwise manual untuk angka 64-bit
    self.buffer = self.buffer .. string.pack(">j", v)
end

-- Menulis Unsigned VarInt (Minecraft Protocol)
function BinaryStream:putUnsignedVarInt(v)
    v = math.floor(v)
    while v >= 0x80 do
        self:putByte((v & 0x7F) | 0x80)
        v = v >> 7
    end
    self:putByte(v)
end

-- Menulis Signed VarInt (ZigZag Encoding)
function BinaryStream:putVarInt(v)
    v = math.floor(v)
    local u = (v << 1) ~ (v >> 31)
    self:putUnsignedVarInt(u)
end

-- Menulis String Minecraft (Panjang VarInt + Isi)
function BinaryStream:putString(v)
    self:putUnsignedVarInt(#v)
    self.buffer = self.buffer .. v
end

-- Menulis String RakNet (Panjang Short + Isi) - Wajib untuk Unconnected Pong
function BinaryStream:putString16(v)
    self:putShort(#v)
    self.buffer = self.buffer .. v
end

-- Menulis Item Bedrock 1.21
function BinaryStream:putItem(id, count)
    if id == 0 or id == nil then
        self:putVarInt(0) -- Item kosong
        return
    end
    self:putVarInt(id)
    self:putShort(count or 1)
    self:putUnsignedVarInt(0) -- Metadata/NBT count
    self:putVarInt(0) -- CanPlaceOn count
    self:putVarInt(0) -- CanDestroy count
end

return BinaryStream
