-- MineLua Server - Main Entry Point
-- A Minecraft Bedrock Edition server implementation in Lua
-- Compatible with MCBE protocol versions (1.0 - 1.21+)

local Server = require("server.Server")
local Logger = require("utils.Logger")
local Config = require("utils.Config")

-- Banner
print([[
╔═══════════════════════════════════════════╗
║           MineLua Server v1.0.0           ║
║   Minecraft Bedrock Edition Server        ║
║   Powered by Lua + LuaSocket + OpenSSL    ║
╚═══════════════════════════════════════════╝
]])

-- Load configuration
local config = Config.load("config/server.yml")

-- Initialize logger
Logger.init(config.log_level or "INFO", "logs/server.log")

Logger.info("Starting MineLua Server...")
Logger.info("Minecraft Bedrock Edition Compatible Server")
Logger.info("Protocol support: 1.0.0 - 1.21.x")

-- Start server
local server = Server.new(config)
server:start()
