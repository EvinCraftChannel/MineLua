-- MineLua Inventory
local Inventory = {}
Inventory.__index = Inventory

function Inventory.new(holder, size)
    local self = setmetatable({}, Inventory)
    self.holder = holder
    self.size = size
    self.slots = {}
    for i = 1, size do self.slots[i] = {id=0, count=0, damage=0} end
    return self
end

function Inventory:getSlot(index)
    return self.slots[index]
end

function Inventory:setSlot(index, item)
    if index >= 1 and index <= self.size then
        self.slots[index] = item or {id=0, count=0, damage=0}
        return true
    end
    return false
end

function Inventory:addItem(item)
    if not item or item.id == 0 then return true end
    -- Try to stack
    for i, slot in ipairs(self.slots) do
        if slot.id == item.id and slot.damage == (item.damage or 0) then
            local max_stack = self:getMaxStack(item.id)
            local can_add = max_stack - slot.count
            if can_add > 0 then
                local add = math.min(can_add, item.count)
                slot.count = slot.count + add
                item.count = item.count - add
                if item.count <= 0 then return true end
            end
        end
    end
    -- Try empty slot
    for i, slot in ipairs(self.slots) do
        if slot.id == 0 then
            self.slots[i] = {id = item.id, count = item.count, damage = item.damage or 0}
            return true
        end
    end
    return false -- full
end

function Inventory:removeItem(item_id, count)
    count = count or 1
    for i, slot in ipairs(self.slots) do
        if slot.id == item_id and slot.count > 0 then
            local remove = math.min(slot.count, count)
            slot.count = slot.count - remove
            count = count - remove
            if slot.count == 0 then
                self.slots[i] = {id=0, count=0, damage=0}
            end
            if count <= 0 then return true end
        end
    end
    return count <= 0
end

function Inventory:hasItem(item_id, count)
    count = count or 1
    local found = 0
    for _, slot in ipairs(self.slots) do
        if slot.id == item_id then
            found = found + slot.count
        end
    end
    return found >= count
end

function Inventory:getMaxStack(item_id)
    -- Most items stack to 64
    local non_stackable = {356, 358, 261, 259, 368, 391, 398, 400, 346, 398}
    for _, id in ipairs(non_stackable) do
        if id == item_id then return 1 end
    end
    return 64
end

function Inventory:clear()
    for i = 1, self.size do
        self.slots[i] = {id=0, count=0, damage=0}
    end
end

return Inventory
