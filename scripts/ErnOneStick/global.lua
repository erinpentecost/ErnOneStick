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
local settings = require("scripts.ErnOneStick.settings")
local world = require('openmw.world')

if require("openmw.core").API_REVISION < 62 then
    error("OpenMW 0.49 or newer is required!")
end

-- Init settings first to init storage which is used everywhere.
settings.initSettings()

local function onPause()
    --world.setSimulationTimeScale(0.1)
    world.pause(settings.MOD_NAME)
end

local function onUnpause()
    --world.setSimulationTimeScale(1)
    world.unpause(settings.MOD_NAME)
end

local function onRotate(data)
    data.object:teleport(data.object.cell, data.object.position, data.rotation)
end

return {
    eventHandlers = {
        [settings.MOD_NAME .. "onPause"] = onPause,
        [settings.MOD_NAME .. "onUnpause"] = onUnpause,
        [settings.MOD_NAME .. "onRotate"] = onRotate,
    }
}
