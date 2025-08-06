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

local lockStateContainerFunctions = {}
lockStateContainerFunctions.__index = function(table, key)
    if lockStateContainerFunctions[key] ~= nil then
        -- container functions get precedence
        return lockStateContainerFunctions[key]
    elseif #(table.stack) > 0 then
        -- otherwise, fallback to current state.
        return table.stack[0].base[key]
    else
        error("empty state stack during '" .. key .. "' access")
    end
end

function NewLockStateContainer()
    local new = {
        -- first element is current state.
        stack = {}
    }
    setmetatable(new, lockStateContainerFunctions)
    return new
end

local lockStateFunctions = {}
lockStateFunctions.__index = lockStateFunctions

-- newLockState creates a new lock state.
-- If this state is active, calls to the container will forward to base.
function lockStateContainerFunctions:newLockState(base)
    -- container pointer is a weakref since the container should own
    -- the state.
    local weakRefs = {
        container = self
    }
    setmetatable(weakRefs, { __mode = 'v' })
    local newState = {
        base = base,
        weakRefs = weakRefs,
    }
    setmetatable(newState, lockStateFunctions)
    return newState
end

function lockStateContainerFunctions:pop()
    -- can't pop the last element.
    if #(self.stack) > 1 then
        return table.remove(self.stack, 1)
    end
end

-- container returns the lockStateContainer for this lockState.
function lockStateFunctions:container()
    return self.weakRefs.container
end

-- push this lockState onto the lockStateContainer stack.
-- the first state pushed is permanent, and can't be popped.
function lockStateFunctions:push()
    -- prevent a state from being in the stack more than once.
    for _, elem in ipairs(self:container().stack) do
        if elem == self then
            error("state is already in the stack")
            return
        end
    end
    table.insert(self:container().stack, 1, self)
end

return {
    NewLockStateContainer = NewLockStateContainer,
}
