type fields = {
	
}
type methods<T...> = {
	Fire: fire<T...>,
	SyncFire: fire<T...>,

	Wait: wait<T...>,
	Connect: connect<T...>,
	Once: connect<T...>
}

local module = {}
module.__index = module
module.__tostring = function() return "Signal" end
module.__newindex = function() error("Invalid member.", 2) end

local Node = require(script.Parent.Node)
local Connection = require(script.Connection)

local function assert_subscriber(sub)
	assert((type(sub) == "function" or type(sub) == "thread"), `Expected a function or a thread.`)
end

function module.new()
	return setmetatable({
		_head = false,
	}, module)
end

function module:sync_fire(... : any)
	local r_thread = coroutine.running()
	local running_threads = 0
	
	local curr = self._head
	while (curr) do
		local sub = curr.value.sub
		curr = curr.prev
		
		running_threads += 1
		task.defer(function(...)
			local s, r = pcall(sub, ...)
			
			running_threads -= 1
			
			if (running_threads == 0) then task.spawn(r_thread) end
			if (not s) then error(r) end
		end, ...)
	end
	
	coroutine.yield()
end

function module:fire(... : any)
	local curr = self._head
	
	while (curr) do
		local sub = curr.value.sub
		curr = curr.prev
		
		task.spawn(sub, ...)
	end
end

function module:connect(sub : (...any) -> ())
	assert_subscriber(sub)
	
	local node = Node.new({ sub = sub, Signal = self, })
	
	if (self._head) then
		self._head:set_next(node)
	end
	self._head = node
	
	return Connection.new(node)
end

function module:once(sub : (...any) -> ())
	assert_subscriber(sub)
	
	local con;con = self:connect(function(...)
		task.spawn(sub, ...)
		
		con:disconnect()
	end)
	
	return con
end

function module:wait()
	self:once(coroutine.running())
	
	return coroutine.yield()
end

module.Connect = module.connect
module.Once = module.once
module.Wait = module.wait
module.Fire = module.fire
module.SyncFire = module.sync_fire

type connect<T...> = ( self: Signal<T...>, (T...) -> () ) -> Connection
type fire<T...> = ( self: Signal<T...>,T...) -> ()
type wait<T...> = ( self: Signal<T...> ) -> T...

export type Connection = Connection.Connection

export type Signal<T...> = typeof(setmetatable({} :: fields, {} :: { __index: methods<T...> }))
export type Module = {
	new: () -> Signal<>
}

return module :: Module