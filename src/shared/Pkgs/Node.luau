type fields = {
	value: any,
	
	prev: boolean,
	next: boolean
}
type methods = {
	set_prev: (self: Node, node: Node) -> (),
	set_next: (self: Node, node: Node) -> ()
}

local module = {}
module.__index = module
module.__tostring = function() return "Node" end
module.__newindex = function() error("Invalid member.", 2) end

function module.new(value)
	return setmetatable({
		value = value,

		prev = false,
		next = false,
	}, module)
end

function module:set_prev(node)
	if (node) then
		assert(getmetatable(node) == module, "Expected a node.")
	end
	
	if (self.prev) then self.prev.next = false end
	self.prev = node
	
	if (not node) then return end
	
	if (node.next) then node.next.prev = false end
	node.next = self
end

function module:set_next(node)
	if (node) then
		assert(getmetatable(node) == module, "Expected a node.")
	end
	
	if (self.next) then self.next.prev = false end
	self.next = node

	if (not node) then return end

	if (node.prev) then node.prev.next = false end
	node.prev = self
end

export type Node = typeof(setmetatable({} :: fields, {} :: { __index: methods }))
export type Module = {
	new: (value: any) -> Node
}

return module :: Module