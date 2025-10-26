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
local MOD_NAME = require("scripts.ErnOneStick.ns")
local interfaces = require("openmw.interfaces")

local adminSettings = interfaces.ErnOneStick_S3ProtectedTable.new {
    inputGroupName = "SettingsAdmin" .. MOD_NAME,
    logPrefix = MOD_NAME,
    modName = MOD_NAME,
    subscribeHandler = false,
}
adminSettings.state = { debugMode = false, disable = false }
local function debugPrint(str, ...)
    if adminSettings.state.debugMode then
        local arg = { ... }
        if arg ~= nil then
            print(string.format("DEBUG: " .. str, unpack(arg)))
        else
            print("DEBUG: " .. str)
        end
    end
end

return {
    debugPrint = debugPrint,
    disable = adminSettings.state.disable
}
