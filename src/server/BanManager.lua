-- MineLua Ban Manager (standalone helper required by Server.lua)
local BanManager = {}

function BanManager.isBanned(name)
    local f = io.open("config/bans.txt", "r")
    if not f then return false end
    local lower = name:lower()
    for line in f:lines() do
        if line:match("^%s*(.-)%s*$"):lower() == lower then
            f:close()
            return true
        end
    end
    f:close()
    return false
end

return BanManager
