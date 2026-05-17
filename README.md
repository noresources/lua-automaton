# lua-automaton
===========================================

Automaton implementation for Lua.

## Example

```lua
local Module = require "." -- Depends on your package;path

-- The initial state of the Automaton.
-- Given to Automaton constructor.
local initial = Module.State.new ({ name = "Initial state" })

local zero = Module.State.new ({ name = "Reset counter"})
local one = Module.State.new ({ name = "One", value = 1 })
local two = Module.State.new ({ name = "Two", value = 2})
local three = Module.State.new ({ name = "Three", value = 3})

-- A transition function that will compare the context counter value against the current state value
function greater (e)
	local actual = e.context.counter or 0
	local expected = e.incoming.value or 0
	return actual > expected
end

-- true is a shorthand for function() return true end
initial:connect(true, zero)

-- Reset context counter each time automaton enter the zero state
zero:on ("enter", function (e)
	e.context.counter = (e.context.counter or 0) + 1
end)

zero:connect(greater, one)
zero:connect(true, zero)

one:connect(greater, two)
one:connect(true, zero)

two:connect(greater, three)
two:connect(true, zero)

-----------------------------------------

local automaton = Module.Automaton.new (initial)

for _, event in pairs (Module.Automaton.EVENT)
do
	automaton:on(event, function (e)
		print("",  "Automaton", e.type)
		if (e.incoming) then print("", "", "from", e.incoming.name) end
		if (e.outgoing) then print("", "", "to", e.outgoing.name) end
	end)
end

-- Reset and assign default context
local context = {
	counter = 0
}

-- Loop manually
automaton:reset (context)
while automaton:update()
do
	context.pass = (context.pass or 0) + 1
	print ("Update pass", context.pass, 
		"at state", automaton.current.name,
		"counter", context.counter)
end

-------------------------------------
-- Loop using iterator
context.counter = 0
context.pass = 0
automaton:reset (context)
for i, state in pairs (automaton)
do
	print ("Iterator pass", i, "state", state.name)
end
```
