local Core = require('./src/Core')
local BinaryStream = require("BinaryStream") 

-- Inisialisasi Server
local server = Core.new("0.0.0.0", 19132)
server:init()
