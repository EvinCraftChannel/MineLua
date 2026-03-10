-- MineLua RakNet Implementation
-- Handles low-level UDP/RakNet protocol for MCBE connections

local socket = require("socket")
local Logger = require("utils.Logger")
local BitBuffer = require("utils.BitBuffer")
local Player = require("server.Player")

local RakNet = {}
RakNet.__index = RakNet

-- RakNet packet IDs
RakNet.PACKET = {
    -- Offline packets
    UNCONNECTED_PING = 0x01,
    UNCONNECTED_PING_OPEN = 0x02,
    UNCONNECTED_PONG = 0x1C,
    OPEN_CONNECTION_REQUEST_1 = 0x05,
    OPEN_CONNECTION_REPLY_1 = 0x06,
    OPEN_CONNECTION_REQUEST_2 = 0x07,
    OPEN_CONNECTION_REPLY_2 = 0x08,
    -- Online packets  
    CONNECTION_REQUEST = 0x09,
    CONNECTION_REQUEST_ACCEPTED = 0x10,
    NEW_INCOMING_CONNECTION = 0x13,
    DISCONNECTION_NOTIFICATION = 0x15,
    DETECT_LOST_CONNECTIONS = 0x19,
    -- RakNet reliability
    FRAME_SET_4 = 0x84,
    FRAME_SET_C = 0x8C,
    ACK = 0xC0,
    NAK = 0xA0,
    -- Data packet range
    DATA_START = 0x80,
    DATA_END = 0x8F,
}

-- Magic bytes for RakNet identification
RakNet.MAGIC = "\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x12\x34\x56\x78"

function RakNet.new(server)
    local self = setmetatable({}, RakNet)
    self.server = server
    self.udp = nil
    self.connections = {} -- address:port -> connection state
    self.server_guid = math.random(0, 2^53) -- Unique server ID
    return self
end

function RakNet:bind(host, port)
    self.udp = socket.udp()
    self.udp:settimeout(0) -- Non-blocking
    self.udp:setsockname(host, port)
    Logger.info(string.format("RakNet UDP socket bound to %s:%d", host, port))
    Logger.info(string.format("Server GUID: %d", self.server_guid))
end

function RakNet:update()
    if not self.udp then return end
    
    -- Process incoming packets (up to 100 per tick)
    for _ = 1, 100 do
        local data, ip, port = self.udp:receivefrom()
        if not data then break end
        
        self:handlePacket(data, ip, port)
    end
    
    -- Process connection states (ACKs, reliability, etc.)
    for addr, conn in pairs(self.connections) do
        self:processConnection(conn, addr)
    end
end

function RakNet:handlePacket(data, ip, port)
    if #data < 1 then return end
    
    local packet_id = data:byte(1)
    local addr_key = ip .. ":" .. port
    
    -- Offline message handler
    if packet_id == RakNet.PACKET.UNCONNECTED_PING or 
       packet_id == RakNet.PACKET.UNCONNECTED_PING_OPEN then
        self:handlePing(data, ip, port)
        
    elseif packet_id == RakNet.PACKET.OPEN_CONNECTION_REQUEST_1 then
        self:handleOpenConnectionRequest1(data, ip, port)
        
    elseif packet_id == RakNet.PACKET.OPEN_CONNECTION_REQUEST_2 then
        self:handleOpenConnectionRequest2(data, ip, port)
        
    elseif packet_id >= RakNet.PACKET.DATA_START and 
           packet_id <= RakNet.PACKET.DATA_END then
        -- Framed reliable packet
        self:handleFrameSet(data, ip, port, addr_key)
        
    elseif packet_id == RakNet.PACKET.ACK then
        self:handleACK(data, addr_key)
        
    elseif packet_id == RakNet.PACKET.NAK then
        self:handleNAK(data, addr_key)
        
    elseif packet_id == RakNet.PACKET.DISCONNECTION_NOTIFICATION then
        self:handleDisconnect(ip, port, addr_key)
    end
end

function RakNet:handlePing(data, ip, port)
    -- Parse ping
    local buf = BitBuffer.new(data)
    buf:skip(1) -- packet id
    local ping_time = buf:readInt64()
    
    -- Build MOTD/server info
    local server = self.server
    local player_count = server.players:count()
    -- Advertise the latest protocol we support (26.2 = 924)
    -- Clients on older versions still connect; we negotiate down in LoginHandler
    local protocol_version = require("protocol.ProtocolManager").CURRENT_PROTOCOL or 924
    local game_version    = require("protocol.ProtocolManager").CURRENT_VERSION  or "26.2"

    local motd = table.concat({
        "MCPE",
        server.motd,
        tostring(protocol_version),
        game_version,
        tostring(player_count),
        tostring(server.max_players),
        tostring(self.server_guid),
        server.sub_motd or "MineLua",
        server.game_mode:sub(1,1):upper() .. server.game_mode:sub(2),
        "1",
        tostring(server.port),
        tostring(server.port)
    }, ";")
    
    -- Build pong response
    local pong = BitBuffer.new()
    pong:writeByte(RakNet.PACKET.UNCONNECTED_PONG)
    pong:writeInt64(ping_time)
    pong:writeInt64(self.server_guid)
    pong:writeBytes(RakNet.MAGIC)
    pong:writeShort(#motd)
    pong:writeString(motd)
    
    self.udp:sendto(pong:tostring(), ip, port)
end

function RakNet:handleOpenConnectionRequest1(data, ip, port)
    local buf = BitBuffer.new(data)
    buf:skip(1) -- packet id
    buf:skip(16) -- magic
    local protocol = buf:readByte()
    local mtu_size = #data + 28 -- UDP header
    
    Logger.debug(string.format("OCR1 from %s:%d proto=%d mtu=%d", ip, port, protocol, mtu_size))
    
    -- Send reply
    local reply = BitBuffer.new()
    reply:writeByte(RakNet.PACKET.OPEN_CONNECTION_REPLY_1)
    reply:writeBytes(RakNet.MAGIC)
    reply:writeInt64(self.server_guid)
    reply:writeByte(0) -- no security
    reply:writeShort(mtu_size)
    
    self.udp:sendto(reply:tostring(), ip, port)
end

function RakNet:handleOpenConnectionRequest2(data, ip, port)
    local addr_key = ip .. ":" .. port
    local buf = BitBuffer.new(data)
    buf:skip(1) -- packet id
    buf:skip(16) -- magic
    buf:skip(7) -- server address (4 bytes IP + 2 bytes port + 1 byte type)
    local mtu_size = buf:readShort()
    local client_guid = buf:readInt64()
    
    Logger.debug(string.format("OCR2 from %s:%d mtu=%d guid=%d", ip, port, mtu_size, client_guid))
    
    -- Check max players
    if self.server.players:count() >= self.server.max_players then
        -- Send disconnect
        self:sendDisconnect(ip, port)
        return
    end
    
    -- Initialize connection
    self.connections[addr_key] = {
        ip = ip,
        port = port,
        guid = client_guid,
        mtu = mtu_size,
        state = "connecting",
        player = nil,
        send_seq = 0,
        recv_seq = 0,
        reliable_index = 0,
        order_index = 0,
        ack_list = {},
        send_queue = {},
        recv_fragments = {},
        last_activity = socket.gettime(),
        timeout = 30 -- seconds
    }
    
    -- Send reply
    local reply = BitBuffer.new()
    reply:writeByte(RakNet.PACKET.OPEN_CONNECTION_REPLY_2)
    reply:writeBytes(RakNet.MAGIC)
    reply:writeInt64(self.server_guid)
    -- Client address
    reply:writeByte(4) -- IPv4
    for octet in ip:gmatch("%d+") do
        reply:writeByte(tonumber(octet))
    end
    reply:writeShort(port)
    reply:writeShort(mtu_size)
    reply:writeByte(0) -- no encryption
    
    self.udp:sendto(reply:tostring(), ip, port)
end

function RakNet:handleFrameSet(data, ip, port, addr_key)
    local conn = self.connections[addr_key]
    if not conn then return end
    
    conn.last_activity = socket.gettime()
    
    local buf = BitBuffer.new(data)
    local flags = buf:readByte()
    local seq_num = buf:readLInt24()
    
    -- Queue ACK
    table.insert(conn.ack_list, seq_num)
    
    -- Process frames in the packet
    while buf:remaining() > 0 do
        local frame_flags = buf:readByte()
        local reliability = (frame_flags & 0xE0) >> 5
        local has_split = (frame_flags & 0x10) ~= 0
        local bit_length = buf:readShort()
        local byte_length = math.ceil(bit_length / 8)
        
        local reliable_index = nil
        local order_index = nil
        local order_channel = nil
        
        -- Read reliability info
        if reliability == 2 or reliability == 3 or reliability == 4 or 
           reliability == 6 or reliability == 7 then
            reliable_index = buf:readLInt24()
        end
        if reliability == 1 or reliability == 3 or reliability == 4 or 
           reliability == 7 then
            order_index = buf:readLInt24()
            order_channel = buf:readByte()
        end
        
        -- Split packet info
        local split_count, split_id, split_index
        if has_split then
            split_count = buf:readInt()
            split_id = buf:readShort()
            split_index = buf:readInt()
        end
        
        -- Read frame body
        local body = buf:readBytes(byte_length)
        
        if has_split then
            -- Handle split packets
            self:handleSplitPacket(conn, split_id, split_index, split_count, body)
        else
            -- Process complete frame
            self:processFrame(conn, body)
        end
    end
    
    -- Send ACKs
    self:sendACKs(conn)
end

function RakNet:handleSplitPacket(conn, split_id, split_index, split_count, data)
    if not conn.recv_fragments[split_id] then
        conn.recv_fragments[split_id] = {
            count = split_count,
            received = 0,
            parts = {}
        }
    end
    
    local frag = conn.recv_fragments[split_id]
    frag.parts[split_index] = data
    frag.received = frag.received + 1
    
    if frag.received >= frag.count then
        -- Reassemble
        local assembled = ""
        for i = 0, frag.count - 1 do
            assembled = assembled .. (frag.parts[i] or "")
        end
        conn.recv_fragments[split_id] = nil
        self:processFrame(conn, assembled)
    end
end

function RakNet:processFrame(conn, data)
    if #data < 1 then return end
    local packet_id = data:byte(1)
    
    if packet_id == RakNet.PACKET.CONNECTION_REQUEST then
        self:handleConnectionRequest(conn, data)
        
    elseif packet_id == RakNet.PACKET.NEW_INCOMING_CONNECTION then
        self:handleNewIncomingConnection(conn, data)
        
    elseif packet_id == RakNet.PACKET.DISCONNECTION_NOTIFICATION then
        self:handleDisconnect(conn.ip, conn.port, conn.ip .. ":" .. conn.port)
        
    elseif packet_id == RakNet.PACKET.DETECT_LOST_CONNECTIONS then
        -- Ping/keep-alive, respond accordingly
        
    elseif packet_id == 0xFE then
        -- MCBE game packet (Batch)
        self:handleMCBEPacket(conn, data)
    end
end

function RakNet:handleConnectionRequest(conn, data)
    local buf = BitBuffer.new(data)
    buf:skip(1)
    local client_guid = buf:readInt64()
    local time = buf:readInt64()
    
    -- Send connection request accepted
    local reply = BitBuffer.new()
    reply:writeByte(RakNet.PACKET.CONNECTION_REQUEST_ACCEPTED)
    -- Client address
    reply:writeByte(4)
    for octet in conn.ip:gmatch("%d+") do
        reply:writeByte(tonumber(octet))
    end
    reply:writeShort(conn.port)
    reply:writeShort(0) -- system index
    -- Internal addresses (10 dummy IPs)
    for i = 1, 10 do
        reply:writeByte(4)
        reply:writeByte(127) reply:writeByte(0)
        reply:writeByte(0) reply:writeByte(i)
        reply:writeShort(0)
    end
    reply:writeInt64(time)
    reply:writeInt64(math.floor(socket.gettime() * 1000))
    
    self:sendReliable(conn, reply:tostring())
end

function RakNet:handleNewIncomingConnection(conn, data)
    conn.state = "connected"
    Logger.info(string.format("New connection from %s:%d", conn.ip, conn.port))
    
    -- Create player object
    local player = Player.new(self.server, conn)
    conn.player = player
    self.server.players:add(player)
end

function RakNet:handleMCBEPacket(conn, data)
    if not conn.player then return end
    
    -- Route to protocol handler
    self.server.protocol:handlePacket(conn.player, data:sub(2))
end

function RakNet:sendACKs(conn)
    if #conn.ack_list == 0 then return end
    
    local ack = BitBuffer.new()
    ack:writeByte(RakNet.PACKET.ACK)
    ack:writeShort(#conn.ack_list)
    for _, seq in ipairs(conn.ack_list) do
        ack:writeByte(1) -- single
        ack:writeLInt24(seq)
    end
    
    self.udp:sendto(ack:tostring(), conn.ip, conn.port)
    conn.ack_list = {}
end

function RakNet:handleACK(data, addr_key)
    -- Remove from retransmit queue (reliability)
    local conn = self.connections[addr_key]
    if conn then
        -- Process ACK records
        conn.last_activity = socket.gettime()
    end
end

function RakNet:handleNAK(data, addr_key)
    -- Retransmit requested packets
    local conn = self.connections[addr_key]
    if conn then
        -- TODO: retransmit
    end
end

function RakNet:handleDisconnect(ip, port, addr_key)
    local conn = self.connections[addr_key]
    if conn then
        if conn.player then
            self.server.players:remove(conn.player)
            self.server.events:fire("PlayerQuit", {player = conn.player})
            Logger.info(string.format("Player disconnected from %s:%d", ip, port))
        end
        self.connections[addr_key] = nil
    end
end

function RakNet:sendReliable(conn, data, channel)
    channel = channel or 0
    
    local frame = BitBuffer.new()
    -- Frame flags: RELIABLE_ORDERED = 0x60
    frame:writeByte(0x60)
    frame:writeShort(#data * 8) -- bit length
    -- Reliable index
    frame:writeLInt24(conn.reliable_index)
    conn.reliable_index = conn.reliable_index + 1
    -- Order index + channel
    frame:writeLInt24(conn.order_index)
    conn.order_index = conn.order_index + 1
    frame:writeByte(channel)
    frame:writeBytes(data)
    
    -- Wrap in frameset
    local packet = BitBuffer.new()
    packet:writeByte(0x84) -- FRAME_SET_4
    packet:writeLInt24(conn.send_seq)
    conn.send_seq = conn.send_seq + 1
    packet:writeBytes(frame:tostring())
    
    self.udp:sendto(packet:tostring(), conn.ip, conn.port)
end

function RakNet:sendToPlayer(player, data)
    local conn = player.connection
    if not conn then return end
    
    -- Wrap in MCBE batch packet (0xFE)
    local batch = "\xFE" .. data
    
    -- Handle MTU splitting if needed
    local mtu = conn.mtu - 60 -- overhead
    if #batch <= mtu then
        self:sendReliable(conn, batch)
    else
        -- Split into fragments
        self:sendSplit(conn, batch, mtu)
    end
end

function RakNet:sendSplit(conn, data, max_size)
    local split_id = (conn.split_id or 0)
    conn.split_id = split_id + 1
    local parts = {}
    local count = math.ceil(#data / max_size)
    
    for i = 0, count - 1 do
        local part = data:sub(i * max_size + 1, (i + 1) * max_size)
        
        local frame = BitBuffer.new()
        frame:writeByte(0x70) -- RELIABLE_ORDERED | HAS_SPLIT
        frame:writeShort(#part * 8)
        frame:writeLInt24(conn.reliable_index)
        conn.reliable_index = conn.reliable_index + 1
        frame:writeLInt24(conn.order_index)
        frame:writeByte(0)
        frame:writeInt(count)
        frame:writeShort(split_id)
        frame:writeInt(i)
        frame:writeBytes(part)
        
        local packet = BitBuffer.new()
        packet:writeByte(0x84)
        packet:writeLInt24(conn.send_seq)
        conn.send_seq = conn.send_seq + 1
        packet:writeBytes(frame:tostring())
        
        self.udp:sendto(packet:tostring(), conn.ip, conn.port)
    end
    
    conn.order_index = conn.order_index + 1
end

function RakNet:processConnection(conn, addr_key)
    -- Check timeout
    local now = socket.gettime()
    if now - conn.last_activity > conn.timeout then
        Logger.info(string.format("Connection timed out: %s", addr_key))
        self:handleDisconnect(conn.ip, conn.port, addr_key)
    end
end

function RakNet:sendDisconnect(ip, port)
    self.udp:sendto(string.char(RakNet.PACKET.DISCONNECTION_NOTIFICATION), ip, port)
end

function RakNet:close()
    if self.udp then
        self.udp:close()
        Logger.info("RakNet socket closed")
    end
end

return RakNet
