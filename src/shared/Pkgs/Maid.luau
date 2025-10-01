type fields = {
    Tasks: { [any]: MaidTask },
}
type methods = {
    GiveTask: (self: Maid, maid_task: MaidTask) -> number,

    DoCleaning: (self: Maid) -> (),
    Destroy: (self: Maid) -> (),
}

local function valid_maidtask(value)
    if (type(value) == "thread") then
        return true
    end
    if (type(value) == "function") then
        return true
    end
    if (type(value) == "table") then
        if (value.Destroy) then
            return true
        end
        if (value.Disconnect) then
            return true
        end
    end
    if (typeof(value) == "Instance") then
        return true
    end
    if (typeof(value) == "RBXScriptConnection") then
        return true
    end
    
    return false
end

local Maid = {}

function Maid:__index(index)
    return (Maid[index] or self.Tasks[index])
end
function Maid:__newindex(index, maid_task)
    if (maid_task and not valid_maidtask(maid_task)) then
        warn("[Maid] Invalid task.")
        return
    end

    self:_collect(index)
    self.Tasks[index] = maid_task
end

function Maid:_collect(index)
    local maid_task = self.Tasks[index]
    if (not maid_task) then
        return
    end

    self.Tasks[index] = nil

    if (type(maid_task) == "thread") then
        local success
        if (coroutine.running() ~= maid_task) then
            success = pcall(task.cancel, maid_task)
        end

        if (not success) then
            task.defer(task.cancel, maid_task)
        end
    elseif (type(maid_task) == "function") then
        maid_task()
    elseif (type(maid_task) == "table") then
        if (maid_task.Disconnect) then
            maid_task:Disconnect()
        end
        if (maid_task.Destroy) then
            maid_task:Destroy()
        end
    elseif (typeof(maid_task) == "RBXScriptConnection") then
        maid_task:Disconnect()
    elseif (typeof(maid_task) == "Instance") then
        maid_task:Destroy()
    end
end

function Maid.new()
    local self = setmetatable({
        Tasks = {}
    }, Maid)

    return self
end

function Maid:GiveTask(maid_task)
    if (not valid_maidtask(maid_task)) then
        warn("[Maid] Invalid task.")
        return
    end

    local task_id = (#self.Tasks + 1)
    self.Tasks[task_id] = maid_task

    return task_id
end

function Maid:DoCleaning()
    for index, _ in (self.Tasks) do
        self:_collect(index)
    end
end

Maid.Destroy = Maid.DoCleaning

export type MaidTask = (thread | () -> () | {} | Instance | RBXScriptConnection)

export type Module = {
    new: () -> Maid,
}

export type Maid = typeof(setmetatable({} :: fields, {} :: { __index: methods }))

return Maid :: Module