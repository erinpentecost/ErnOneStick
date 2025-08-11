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

local input = require('openmw.input')
local settings = require("scripts.ErnOneStick.settings")

local triggerThreshold = 0.3

local KeyFunctions = {}
KeyFunctions.__index = KeyFunctions

function NewKey(name, eval)
    local new = {
        name = name,
        eval = eval,
        pressed = false,
        -- analog is a range from 0 to 1 indicating how pressed the key is.
        analog = 0,
        rise = false,
        fall = false,
    }
    setmetatable(new, KeyFunctions)
    return new
end

function KeyFunctions.update(self, dt)
    -- newState is a boolean or float range from 0 to 1.
    local newState = self.eval(dt)
    local newBooleanState = false
    self.analog = 0
    if type(newState) == "boolean" then
        newBooleanState = newState
        if newState then
            self.analog = 1
        end
    elseif type(newState) == "number" then
        self.analog = math.max(0, math.min(1, newState))
        if newState > (1 - triggerThreshold) then
            newBooleanState = true
        elseif newState < triggerThreshold then
            newBooleanState = false
        else
            return
        end
    else
        error("unsupported type for key tracker: " .. type(newState))
        return
    end

    if newBooleanState ~= self.pressed then
        settings.debugPrint("key " .. self.name .. ": " .. tostring(self.pressed) .. "->" .. tostring(newBooleanState))
        self.pressed = newBooleanState
        if newBooleanState then
            self.rise = true
            self.fall = false
        else
            self.rise = false
            self.fall = true
        end
    else
        --[[if self.rise or self.fall then
            settings.debugPrint("key " .. self.name .. ": reset rise and fall")
            end]]
        self.rise = false
        self.fall = false
    end
end

return {
    NewKey = NewKey
}
