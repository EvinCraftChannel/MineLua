package.path = package.path .. ";./src/?.lua;./src/network/?.lua;./plugins/?.lua"
local Core = require("Core")
local BinaryStream = require("BinaryStream") 

-- Inisialisasi Server
local server = Core.new("0.0.0.0", 19132)
server:init()

local status, err = pcall(function()
    Core:init()
end)

if not status then
    print("\27[31m[CRITICAL ERROR]\27[0m " .. err)
end
