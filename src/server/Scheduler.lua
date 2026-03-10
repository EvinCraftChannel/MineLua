-- MineLua Scheduler
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(server)
    local self = setmetatable({}, Scheduler)
    self.server = server
    self.tasks = {}
    self.task_id = 0
    return self
end

function Scheduler:after(delay_ticks, callback)
    self.task_id = self.task_id + 1
    self.tasks[self.task_id] = {
        id = self.task_id,
        run_at = nil, -- will be set on first tick
        delay = delay_ticks,
        interval = nil,
        callback = callback,
        cancelled = false
    }
    return self.task_id
end

function Scheduler:repeating(delay_ticks, interval_ticks, callback)
    self.task_id = self.task_id + 1
    self.tasks[self.task_id] = {
        id = self.task_id,
        run_at = nil,
        delay = delay_ticks,
        interval = interval_ticks,
        callback = callback,
        cancelled = false
    }
    return self.task_id
end

function Scheduler:cancel(task_id)
    if self.tasks[task_id] then
        self.tasks[task_id].cancelled = true
    end
end

function Scheduler:tick(current_tick)
    local to_remove = {}
    for id, task in pairs(self.tasks) do
        if task.cancelled then
            table.insert(to_remove, id)
        else
            if not task.run_at then
                task.run_at = current_tick + task.delay
            end
            if current_tick >= task.run_at then
                local ok, err = pcall(task.callback)
                if not ok then
                    require("utils.Logger").error("Scheduler task error: " .. tostring(err))
                end
                if task.interval then
                    task.run_at = current_tick + task.interval
                else
                    table.insert(to_remove, id)
                end
            end
        end
    end
    for _, id in ipairs(to_remove) do
        self.tasks[id] = nil
    end
end

return Scheduler
