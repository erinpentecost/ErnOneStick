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
local interfaces = require("openmw.interfaces")
local storage = require("openmw.storage")
local types = require("openmw.types")
local async = require('openmw.async')

local MOD_NAME = "ErnOneStick"

local SettingsGameplay = storage.globalSection("SettingsGameplay" .. MOD_NAME)

local function debugMode()
    return SettingsGameplay:get("debugMode")
end

local function debugPrint(str, ...)
    if debugMode() then
        local arg = { ... }
        if arg ~= nil then
            print(string.format("DEBUG: " .. str, unpack(arg)))
        else
            print("DEBUG: " .. str)
        end
    end
end


local function registerPage()
    interfaces.Settings.registerPage {
        key = MOD_NAME,
        l10n = MOD_NAME,
        name = "name",
        description = "description"
    }
end

local function initSettings()
    interfaces.Settings.registerGroup {
        key = "SettingsGameplay" .. MOD_NAME,
        l10n = MOD_NAME,
        name = "modSettingsControlsTitle",
        description = "modSettingsControlsDesc",
        page = MOD_NAME,
        permanentStorage = false,
        settings = { {
            key = "debugMode",
            name = "debugMode_name",
            description = "debugMode_description",
            default = false,
            renderer = "checkbox"
        } }
    }

    print("init settings")
end

local function onReset(fn)
    SettingsGameplay:subscribe(async:callback(function(section, key)
        if key == "resetData" then
            fn()
        end
    end))
end

return {
    initSettings = initSettings,
    MOD_NAME = MOD_NAME,

    registerPage = registerPage,

    debugMode = debugMode,
    debugPrint = debugPrint
}
