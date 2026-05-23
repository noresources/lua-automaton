local public = {
	State = {
		EVENT = {
			ENTER = "enter",
			EXIT = "exit"
		}
	},
	Automaton = {
		EVENT = {
			START = "start",
			EXIT = "exit",
			TRANSITION = "transition",
			ENTER = "enter",
			TERMINATE = "terminate"
		}
	}
}

local internal = {
	State = {},
	Automaton = {}
}

-- Asserts that value has the given Lua type name.
function internal.typecheck(value, expected, name)
	local t = type(value)
	assert ( t == expected, name
		and expected .. " type expected for " .. name .. ". Got " .. t
		or expected .. " expected. Got " .. t)
end

-- Returns true for functions and callable tables (tables with a __call metamethod).
function internal.iscallable(value)
	local t = type(value)
	if t == "function" then return true end
	if t ~= "table" then return false end

	local mt = getmetatable (value)
	if not mt then return false end

	return type(mt.__call) == "function"
end

-- Registers handler for event; shared by State and Automaton instances.
function internal:on (event, handler)
	internal.typecheck(event, "string", "event")
	self._listeners[event] = handler
end

-- Exposes private _k fields as public k for read-only access.
function internal.__index(o, k)
	return rawget(o, "_" .. k)
end

-- Linear search; returns true if needle is present in the ipairs sequence of haystack.
function internal.includes(haystack, needle)
	for _, e in ipairs (haystack)
	do
		if e == needle then return true end
	end
	return false
end

-- Fires emitter's registered listener for event type, merging data fields into the event table.
function internal.invoke (type, emitter, data)
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

-------------------------------------
-- State

-- Appends a transition to state, normalising validator to a callable before storing it.
function internal.State:connect(validator, state)
	internal.typecheck(state, "table", "state")

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
		and not internal.iscallable(validator)
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

	assert(internal.iscallable(validator), "Validator must be callable")

	table.insert(self._transitions, {validator = validator, state = state})
end

-- Returns the first transition whose validator passes for context, or nil.
function internal.State:accept( context )
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

function public.State.new(data)
	local this = {}
	for k, v in pairs (data or {})
	do
		this[k] = v
	end

	this.on = internal.on
	this._listeners = {}

	this._transitions = {}

	for k, f in pairs (internal.State)
	do
		this[k] = f
	end

	setmetatable (this, {
		__call = function (this, context)
			return this:accept(context)
		end,
		__index = internal.__index
	})

	return this
end

setmetatable (public.State, {
	__call = function(_, data)
		return public.State.new(data)
	end
})

--------------------------------------------------
-- Automaton

-- Returns a stateful iterator that drives the automaton forward one update per call.
function internal.Automaton._iterator(automaton)
	automaton._current = nil
	local i = 0
	return function ()
		i = i + 1
		local r = automaton:update()
		if r then return i, automaton.current end
		return nil
	end
end


function internal.Automaton:reset (context)
	self._context = context
	self._current = nil
end

function internal.Automaton:pairs (context)
	self._context = context or self._context
	return self._iterator(self)
end

-- Advances the automaton: follows transitions from the current state until blocked, cycled, or terminal.
-- Returns true while the automaton is still running; false when it has terminated or encountered an error.
function internal.Automaton:update (context)
	local ctx = context or self._context

	if self._current == nil
	then
		internal.invoke (public.Automaton.EVENT.START, self, {
			current = self._initial,
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

		internal.invoke(public.Automaton.EVENT.EXIT, self._current, event)
		self._current = t.state
		internal.invoke (public.Automaton.EVENT.TRANSITION, self, event)
		internal.invoke (public.Automaton.EVENT.ENTER, self._current, event)

		iteration = iteration + 1

		if internal.includes (visited, self._current)
		then
			loop = false
		else
			table.insert (visited, self._current)
		end
	end

	if #self._current._transitions == 0
	then
		internal.invoke(public.Automaton.EVENT.TERMINATE, self, {
			current = self._current,
			context = ctx
		})
		return false, "Terminated"
	end

	return true
end

function public.Automaton.new(initial)
	local this = {
		_listeners = {},
		_initial = initial,
		_current = nil,
		on = internal.on
	}
	for k, f in pairs (internal.Automaton)
	do
		this[k] = f
	end

	setmetatable (this, {
		__pairs = this._iterator,
		__ipairs = this._iterator,
		__call = function (this, context)
			return this:update (context)
		end,
		__index = internal.__index
	})

	this:reset()

	return this
end

setmetatable (public.Automaton, {
	__call = function(_, initial)
		return public.Automaton.new(initial)
	end
})

---------------------------------
return public
