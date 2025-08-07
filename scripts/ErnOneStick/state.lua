--[[
ErnOneStick for OpenMW.
Copyright (C) 2025 Erin Pentecost

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]

-- Ref: https://www.lua.org/pil/16.html

local StateContainerFunctions = {}
StateContainerFunctions.__index = function(table, key)
    local raw = rawget(StateContainerFunctions, key)
    if raw ~= nil then
        return raw
    elseif #(table.stack) > 0 then
        -- fallback to current state.
        return table.stack[1].base[key]
    else
        error("empty state stack during '" .. key .. "' access")
    end
end

-- NewStateContainer returns a new state machine.
function NewStateContainer()
    local new = {
        -- first element is current state.
        stack = {}
    }
    setmetatable(new, StateContainerFunctions)
    return new
end

local StateFunctions = {}
StateFunctions.__index = StateFunctions

function StateFunctions.set(self, base)
    self.base = base
    if base.onEnter ~= nil then
        if type(base.onEnter) == "function" then
            self.onEnter = base.onEnter
        else
            error("base.onEnter is not a function")
            return
        end
    end
end

-- newState creates a new lock state.
-- If this state is active, calls to the container will forward to base.
function NewState(base)
    -- container pointer is a weakref since the container should own
    -- the state.
    local weakRefs = {
        container = nil
    }
    setmetatable(weakRefs, { __mode = 'v' })
    local newState = {
        onEnter = function() end,
        weakRefs = weakRefs,
    }
    setmetatable(newState, StateFunctions)
    if base ~= nil then
        newState:set(base)
    end
    return newState
end

-- push this State onto the StateContainer stack.
-- the first state pushed is permanent, and can't be popped.
function StateContainerFunctions.push(self, state)
    --print("push new state")
    if getmetatable(state) ~= StateFunctions then
        error("can't push non-state object")
        return
    end

    -- prevent a state from being in the stack more than once.
    for _, elem in ipairs(self.stack) do
        if elem == self then
            error("state is already in the stack")
            return
        end
    end

    -- set container ref
    state.weakRefs.container = self

    table.insert(self.stack, 1, state)

    state.onEnter()
end

function StateContainerFunctions.pop(self)
    --print("pop old state")
    if #(self.stack) > 0 then
        return table.remove(self.stack, 1)
    end
    if #(self.stack) > 0 then
        self.stack[1].onEnter()
    end
end

function StateContainerFunctions.replace(self, state)
    --print("replace state")
    StateContainerFunctions.push(self, state)
    if #(self.stack) > 1 then
        return table.remove(self.stack, 2)
    end
end

-- container returns the StateContainer for this State.
function StateFunctions.container(self)
    return self.weakRefs.container
end

-- remove the state from the state container.
-- Returns true if it was removed; false if it wasn't found.
function StateFunctions.remove(self)
    if StateFunctions.container(self) == nil then
        return false
    end
    for i, elem in ipairs(StateFunctions.container(self).stack) do
        if elem == self then
            table.remove(StateFunctions.container(self).stack, i)
            return true
        end
    end
    return false
end

--- TESTS

local function test()
    local cont = NewStateContainer()
    local s1 = NewState({ name = "s1" })
    cont:push(s1)
    if s1:container() ~= cont then
        error("container() does not match")
        return
    end
    if cont.name ~= "s1" then
        error("key not forwarded to s1, only element")
        return
    end
    local s2 = NewState({ name = "s2" })
    cont:push(s2)
    if cont.name ~= "s2" then
        error("key not forwarded to s2")
        return
    end
    local popped = cont:pop()
    if s2 ~= popped then
        error("popped did not return element")
        return
    end
    if cont.name ~= "s1" then
        error("key not forwarded to s1, post pop")
        return
    end
    if s2:remove() ~= false then
        error("remove() missing state did not return false")
    end
    if s1:remove() ~= true then
        error("remove() present state did not return true")
    end
    print("state container is ok")
end

test()

--- EXPORT
return {
    NewStateContainer = NewStateContainer,
    NewState = NewState,
}
