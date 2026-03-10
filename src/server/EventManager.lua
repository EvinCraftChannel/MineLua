-- MineLua Event Manager
local EventManager = {}
EventManager.__index = EventManager

function EventManager.new(server)
    local self = setmetatable({}, EventManager)
    self.server = server
    self.listeners = {} -- event_name -> list of {id, callback, priority}
    self.listener_id = 0
    return self
end

function EventManager:register(event_name, callback, priority)
    if not self.listeners[event_name] then
        self.listeners[event_name] = {}
    end
    self.listener_id = self.listener_id + 1
    local id = self.listener_id
    table.insert(self.listeners[event_name], {
        id = id,
        callback = callback,
        priority = priority or 0
    })
    -- Sort by priority (higher = earlier)
    table.sort(self.listeners[event_name], function(a, b)
        return a.priority > b.priority
    end)
    return id
end

function EventManager:unregister(listener_id)
    for event_name, listeners in pairs(self.listeners) do
        for i, listener in ipairs(listeners) do
            if listener.id == listener_id then
                table.remove(listeners, i)
                return true
            end
        end
    end
    return false
end

function EventManager:fire(event_name, data)
    local listeners = self.listeners[event_name]
    if not listeners then return data end
    
    for _, listener in ipairs(listeners) do
        local ok, result = pcall(listener.callback, data)
        if not ok then
            require("utils.Logger").error(string.format(
                "Error in event listener for '%s': %s", event_name, tostring(result)))
        elseif result == true then
            -- Listener consumed the event
            return data
        end
    end
    return data
end

return EventManager
