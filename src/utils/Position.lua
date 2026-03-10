-- MineLua Position
local Position = {}
Position.__index = Position

function Position.new(x, y, z, world)
    return setmetatable({x=x or 0, y=y or 0, z=z or 0, world=world}, Position)
end

function Position:distance(other)
    local dx = self.x - other.x
    local dy = self.y - other.y
    local dz = self.z - other.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function Position:__tostring()
    return string.format("(%.2f, %.2f, %.2f)", self.x, self.y, self.z)
end

return Position
