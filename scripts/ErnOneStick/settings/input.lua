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

local inputSettings = interfaces.ErnOneStick_S3ProtectedTable.new {
    inputGroupName = "SettingsInput" .. MOD_NAME,
    logPrefix = MOD_NAME,
    modName = MOD_NAME,
    subscribeHandler = false,
}
inputSettings.state = {
    twoStickMode = false,
    lookSensitivityHorizontal = 0,
    lookSensitivityVertical = 0,
    invertLookVertical = false,
    enableShaders = false,
    freeLookZoom = 0,
    volume = 0,
    dynamicPitch = false,
    autoLockon = true,
    travelcam = "",
    lockedoncam = "",

}

return inputSettings.state
