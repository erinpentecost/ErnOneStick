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

local KeyFunctions = {}
KeyFunctions.__index = KeyFunctions

function NewKey(name, eval)
    local new = {
        name = name,
        eval = eval,
        pressed = false,
        rise = false,
        fall = false,
    }
    setmetatable(new, KeyFunctions)
    return new
end

function KeyFunctions.update(self, dt)
    local newState = self.eval(dt)
    if newState ~= self.pressed then
        settings.debugPrint("key " .. self.name .. ": " .. tostring(self.pressed) .. "->" .. tostring(newState))
        self.pressed = newState
        if newState then
            self.rise = true
            self.fall = false
        else
            self.rise = false
            self.fall = true
        end
    else
        self.rise = false
        self.fall = false
    end
end

return {
    NewKey = NewKey
}
