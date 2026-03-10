-- MineLua BitBuffer - Binary read/write utility
-- Used for parsing and building RakNet/MCBE packets

local BitBuffer = {}
BitBuffer.__index = BitBuffer

function BitBuffer.new(data)
    local self = setmetatable({}, BitBuffer)
    if type(data) == "string" then
        self.data = data
        self.pos = 1
        self.write_buf = nil
    else
        self.data = ""
        self.pos = 1
        self.write_buf = {}
    end
    return self
end

-- ==================== WRITE METHODS ====================

function BitBuffer:_write(bytes)
    table.insert(self.write_buf, bytes)
end

function BitBuffer:writeByte(v)
    v = v & 0xFF
    self:_write(string.char(v))
end

function BitBuffer:writeShort(v)
    v = v & 0xFFFF
    self:_write(string.char((v >> 8) & 0xFF, v & 0xFF))
end

function BitBuffer:writeLShort(v)
    v = v & 0xFFFF
    self:_write(string.char(v & 0xFF, (v >> 8) & 0xFF))
end

function BitBuffer:writeInt(v)
    v = v & 0xFFFFFFFF
    self:_write(string.char(
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF
    ))
end

function BitBuffer:writeLInt(v)
    v = v & 0xFFFFFFFF
    self:_write(string.char(
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF
    ))
end

function BitBuffer:writeLInt24(v)
    v = v & 0xFFFFFF
    self:_write(string.char(
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF
    ))
end

function BitBuffer:writeInt64(v)
    -- Write as two 32-bit ints (big-endian)
    local hi = math.floor(v / (2^32)) & 0xFFFFFFFF
    local lo = v & 0xFFFFFFFF
    self:writeInt(hi)
    self:writeInt(lo)
end

function BitBuffer:writeLInt64(v)
    local hi = math.floor(v / (2^32)) & 0xFFFFFFFF
    local lo = v & 0xFFFFFFFF
    self:writeLInt(lo)
    self:writeLInt(hi)
end

function BitBuffer:writeFloat(v)
    -- Pack float to 4 bytes (IEEE 754)
    local bits = 0
    if v ~= 0 then
        local sign = v < 0 and 1 or 0
        local abs_v = math.abs(v)
        local exp = math.floor(math.log(abs_v) / math.log(2))
        local mantissa = abs_v / (2^exp) - 1
        exp = exp + 127
        bits = sign * (2^31) + exp * (2^23) + math.floor(mantissa * (2^23))
    end
    self:writeInt(bits)
end

function BitBuffer:writeDouble(v)
    -- Pack double to 8 bytes
    local s = v < 0 and 1 or 0
    local abs_v = math.abs(v)
    local e, m = 0, 0
    if abs_v ~= 0 then
        e = math.floor(math.log(abs_v) / math.log(2)) + 1023
        m = abs_v / (2^(e - 1023)) - 1
    end
    local hi = s * (2^31) + e * (2^20) + math.floor(m * (2^20))
    local lo = math.floor((m * (2^20) - math.floor(m * (2^20))) * (2^32))
    self:writeLInt(lo)
    self:writeLInt(hi)
end

function BitBuffer:writeVarInt(v)
    v = v & 0xFFFFFFFF
    repeat
        local byte = v & 0x7F
        v = v >> 7
        if v ~= 0 then byte = byte | 0x80 end
        self:writeByte(byte)
    until v == 0
end

function BitBuffer:writeZigZag(v)
    self:writeVarInt((v << 1) ~ (v >> 31))
end

function BitBuffer:writeVarLong(v)
    for i = 1, 10 do
        local byte = v & 0x7F
        v = math.floor(v / 128)
        if v ~= 0 then byte = byte | 0x80 end
        self:writeByte(byte)
        if v == 0 then break end
    end
end

function BitBuffer:writeString(s)
    self:writeVarInt(#s)
    self:_write(s)
end

function BitBuffer:writeLString(s)
    self:writeShort(#s)
    self:_write(s)
end

function BitBuffer:writeBytes(b)
    self:_write(b)
end

function BitBuffer:writeBool(v)
    self:writeByte(v and 1 or 0)
end

function BitBuffer:writeVec3(x, y, z)
    self:writeFloat(x)
    self:writeFloat(y)
    self:writeFloat(z)
end

function BitBuffer:writeBlockPos(x, y, z)
    self:writeZigZag(x)
    self:writeVarInt(y)
    self:writeZigZag(z)
end

function BitBuffer:writeUUID(uuid)
    -- Write as two int64s
    self:writeInt64(uuid[1] or 0)
    self:writeInt64(uuid[2] or 0)
end

-- ==================== READ METHODS ====================

function BitBuffer:readByte()
    local b = self.data:byte(self.pos)
    self.pos = self.pos + 1
    return b or 0
end

function BitBuffer:readShort()
    local hi = self:readByte()
    local lo = self:readByte()
    return hi * 256 + lo
end

function BitBuffer:readLShort()
    local lo = self:readByte()
    local hi = self:readByte()
    return hi * 256 + lo
end

function BitBuffer:readInt()
    local b1 = self:readByte()
    local b2 = self:readByte()
    local b3 = self:readByte()
    local b4 = self:readByte()
    return b1 * (2^24) + b2 * (2^16) + b3 * 256 + b4
end

function BitBuffer:readLInt()
    local b1 = self:readByte()
    local b2 = self:readByte()
    local b3 = self:readByte()
    local b4 = self:readByte()
    return b4 * (2^24) + b3 * (2^16) + b2 * 256 + b1
end

function BitBuffer:readLInt24()
    local b1 = self:readByte()
    local b2 = self:readByte()
    local b3 = self:readByte()
    return b3 * (2^16) + b2 * 256 + b1
end

function BitBuffer:readInt64()
    local hi = self:readInt()
    local lo = self:readInt()
    return hi * (2^32) + lo
end

function BitBuffer:readLInt64()
    local lo = self:readLInt()
    local hi = self:readLInt()
    return hi * (2^32) + lo
end

function BitBuffer:readFloat()
    local bits = self:readInt()
    if bits == 0 then return 0.0 end
    local sign = (bits >> 31) == 0 and 1 or -1
    local exp = ((bits >> 23) & 0xFF) - 127
    local mantissa = (bits & 0x7FFFFF) / (2^23) + 1
    return sign * mantissa * (2^exp)
end

function BitBuffer:readVarInt()
    local result = 0
    local shift = 0
    repeat
        local byte = self:readByte()
        result = result | ((byte & 0x7F) << shift)
        shift = shift + 7
        if shift > 35 then break end
    until (byte & 0x80) == 0
    return result
end

function BitBuffer:readZigZag()
    local v = self:readVarInt()
    return (v >> 1) ~ -(v & 1)
end

function BitBuffer:readVarLong()
    local result = 0
    local shift = 0
    repeat
        local byte = self:readByte()
        result = result + (byte & 0x7F) * (2^shift)
        shift = shift + 7
        if shift > 70 then break end
    until (byte & 0x80) == 0
    return result
end

function BitBuffer:readString()
    local len = self:readVarInt()
    return self:readBytes(len)
end

function BitBuffer:readLString()
    local len = self:readLShort()
    return self:readBytes(len)
end

function BitBuffer:readBytes(n)
    local s = self.data:sub(self.pos, self.pos + n - 1)
    self.pos = self.pos + n
    return s
end

function BitBuffer:readBool()
    return self:readByte() ~= 0
end

function BitBuffer:readVec3()
    return self:readFloat(), self:readFloat(), self:readFloat()
end

function BitBuffer:readBlockPos()
    return self:readZigZag(), self:readVarInt(), self:readZigZag()
end

function BitBuffer:skip(n)
    self.pos = self.pos + n
end

function BitBuffer:remaining()
    return #self.data - self.pos + 1
end

function BitBuffer:pos()
    return self.pos
end

function BitBuffer:tostring()
    if self.write_buf then
        return table.concat(self.write_buf)
    end
    return self.data
end

function BitBuffer:len()
    if self.write_buf then
        local total = 0
        for _, v in ipairs(self.write_buf) do
            total = total + #v
        end
        return total
    end
    return #self.data
end

return BitBuffer
