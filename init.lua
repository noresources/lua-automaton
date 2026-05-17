--------------------------------------------------
-- State

local StateClass = {
	EVENT = {
		ENTER = "enter",
		EXIT = "exit"
	}
}

local StateInstance = {}

function StateInstance:on(event, handler)
	self._listeners[event] = handler
end

function StateInstance:connect(validator, state)
	local t = type (validator)
	if (t == "boolean") or (t == "nil")
	then
		local V = validator
		validator = function () return V end
	elseif t == "string"
	then
		local V = validator
		validator = function (e)
			return tostring(e.context) == V
		end
	elseif t == "number"
	then
		local V = validator
		validator = function (e)
			return tonumber(e.context) == V
		end
	elseif t == "table"
	then
		local V = validator
		validator = function (e)
			for k, v in pairs (V)
			do
				if e.context[k] ~= v then return false end
			end
			return true
		end
	end
	table.insert(self._transitions, {validator = validator, state = state})
end

function StateInstance:accept( context )
	for _, t in ipairs (self._transitions)
	do
		if t.validator({
			incoming = self,
			context = context,
			outgoing = t.state
		})
		then
			return t
		end
	end
	return nil
end

function StateClass.new(data)
	local this = {}
	for k, v in pairs (data or {})
	do
		this[k] = v
	end
	this._transitions = {}
	this._listeners = {}
	
	for k, f in pairs (StateInstance)
	do
		this[k] = f
	end
	
	setmetatable (this, {
		__call = function (this, context)
			return this:accept(context)
		end,
		__index = function (o, k)
			return rawget (o, "_" .. k)
		end
	})
	
	return this
end


setmetatable (StateClass, {
	__call = function (StateClass, data)
		return StateClass.new(data)
	end
})

--------------------------------------------------
-- Automaton
local AutomatonClass = {
	EVENT = {
		START = "start",
		EXIT = "exit",
		TRANSITION = "transition",
		ENTER = "enter",
		TERMINATE = "terminate"
	}
}

local function includes(haystack, needle)
	for _, e in ipairs (haystack)
	do
		if e == needle then return true end
	end
	return false
end

local function invoke (type, emitter, data)
	local handler = emitter.listeners [type]
	if not handler then return end
	local event = {}
	for k, v in pairs (data or {})
	do
		event[k] = v
	end
	event.type = type
	handler (event)
end

local function AutomatonInstanceIterator(automaton)
	automaton._current = nil
	local i = 0
	return function ()
		i = i + 1
		local r = automaton:update()
		if r then return i, automaton.current end
		return nil
	end
end

local AutomatonInstance = {}
function AutomatonInstance:on(event, handler)
	self._listeners[event] = handler
end

function AutomatonInstance:reset (context)
	self._context = context
	self._current = nil
end

function AutomatonInstance:pairs (context)
	self._context = context or self._context
	return AutomatonInstanceIterator(self)
end

function AutomatonInstance:update (context)
	local ctx = context or self._context
	
	if self._current == nil
	then
		invoke (AutomatonClass.EVENT.START, self, {
			initial = self._initial,
			context = ctx
		})
	end
	
	self._current = self._current or self._initial
	if not self._current then return false, "No current state" end
	
	local visited = { self._current }
	local loop = false
	if #self._current.transitions > 0
	then
		loop = true
	end
	local iteration = 1
	while loop
	do
		local t = self._current:accept (ctx)
		if not t then return true, "No more transition validates (" .. #self._current.transitions .. ")" end
		
		local event = {
			incoming = self._current,
			context = ctx,
			outgoing = t.state,
			transition = t,
			iteration = iteration
		}
			
		invoke(AutomatonClass.EVENT.EXIT, self._current, event)
		self._current = t.state
		invoke (AutomatonClass.EVENT.TRANSITION, self, event)
		invoke (AutomatonClass.EVENT.ENTER, self._current, event)

		if includes (visited, self._current)
		then
			loop = false
		else
			table.insert (visited, self._current)
		end
	end
		
	if #self._current._transitions == 0
	then
		invoke(AutomatonClass.EVENT.TERMINATE, self, {
			final = self._current,
			context = ctx
		})
		return false, "Terminated"
	end
	
	return true
end

function AutomatonClass.new(initial)
	local this = {
		_listeners = {},
		_initial = initial,
		_current = nil,
		_listeners = {},
	}
	for k, f in pairs (AutomatonInstance)
	do
		this[k] = f
	end
	
	setmetatable (this, {
		__pairs = AutomatonInstanceIterator,
		__ipairs = AutomatonInstanceIterator,
		__call = function (this, context)
			return this:update (context)
		end,
		__index = function (o, k)
			return rawget (o, "_" .. k)
		end
	})
	
	this:reset()
	
	return this
end

setmetatable (AutomatonClass, {
	__call = function (AutomatonClass, initial) 
		return AutomatonClass.new(initial)
	end
})

return {
	State = StateClass,
	Automaton = AutomatonClass
}