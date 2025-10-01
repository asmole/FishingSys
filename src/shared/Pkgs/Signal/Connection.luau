local Node = require(script.Parent.Parent.Node)

type fields = {
	connected: boolean
}

type methods = {
	disconnect: () -> (),
	Disconnect: () -> ()
}

local node_ref = setmetatable({}, { __mode = "kv" })

local module = {}
module.__index = module
module.__tostring = function() return "Connection" end
module.__newindex = function() error("Invalid member.", 2) end

function module.new(node)
	local self = setmetatable({
		connected = true,
	}, module)
	
	node_ref[self] = node
	return self
end

function module:disconnect()
	if (not self.connected) then return end
	self.connected = false

	local node = node_ref[self]
	if (not node) then return end
	
	node_ref[self] = nil
	
	local Signal = node.value.Signal

	local prev, next = node.prev, node.next
	node:set_prev()
	node:set_next()

	if (prev and next) then
		prev:set_next(next)
	end

	if (Signal._head == node) then
		Signal._head = (prev or false)
	end
end

module.Disconnect = module.disconnect

type module = {
	new: (node: Node.Node) -> Connection
}

export type Connection = typeof(setmetatable({} :: fields, {} :: { __index: methods } ))

return module :: module