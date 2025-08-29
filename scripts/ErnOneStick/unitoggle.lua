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
local pself = require("openmw.self")
local async = require("openmw.async")
local types = require('openmw.types')
local ui = require("openmw.interfaces").UI
local core = require("openmw.core")
local input = require('openmw.input')
local controls = require('openmw.interfaces').Controls

if settings.disable() then
    print(settings.MOD_NAME .. " is disabled.")
    return
end

local function override()
    if settings.combineToggles ~= true then
        controls.overrideCombatControls(false)
        return
    end
    controls.overrideCombatControls(true)
end

local function canDoMagic()
    local hasSpell = (types.Actor.getSelectedEnchantedItem(pself) ~= nil) or (types.Actor.getSelectedSpell(pself) ~= nil)

    return types.Player.getControlSwitch(pself, types.Player.CONTROL_SWITCH.Magic) and
        (types.Player.isWerewolf(pself) ~= true) and hasSpell
end

local function canDoFighting()
    return types.Player.getControlSwitch(pself, types.Player.CONTROL_SWITCH.Fighting)
end

local function toggle()
    override()
    if settings.combineToggles ~= true then
        return
    end
    -- Nothing -> Spell -> Weapon -> Nothing
    if types.Actor.getStance(pself) == types.Actor.STANCE.Nothing then
        if canDoMagic() then
            types.Actor.setStance(pself, types.Actor.STANCE.Spell)
        elseif canDoFighting() then
            types.Actor.setStance(pself, types.Actor.STANCE.Weapon)
        end
        return
    end

    if types.Actor.getStance(pself) == types.Actor.STANCE.Spell then
        if canDoFighting() then
            types.Actor.setStance(pself, types.Actor.STANCE.Weapon)
        else
            types.Actor.setStance(pself, types.Actor.STANCE.Nothing)
        end
        return
    end

    if types.Actor.getStance(pself) == types.Actor.STANCE.Weapon then
        types.Actor.setStance(pself, types.Actor.STANCE.Nothing)
        return
    end
end

input.registerTriggerHandler('ToggleSpell', async:callback(function() toggle() end))
input.registerTriggerHandler('ToggleWeapon', async:callback(function() toggle() end))


-- The below section is modified from openmw's playercontrols.lua
-- It's reproduced here because if you override the Toggle buttons you also end up overriding this one.
-- https://github.com/OpenMW/openmw/blob/60d31e978aed4001b36277720ad3406d0a005c4d/files/data/scripts/omw/input/playercontrols.lua#L45
local function controlsAllowed()
    return not core.isWorldPaused()
        and types.Player.getControlSwitch(pself, types.Player.CONTROL_SWITCH.Controls)
        and not ui.getMode()
end
local startUse = false
input.registerActionHandler('Use', async:callback(function(value)
    if value and controlsAllowed() then startUse = true end
end))
local function processAttacking()
    -- for spell-casting, set controls.use to true for exactly one frame
    -- otherwise spell casting is attempted every frame while Use is true
    if types.Actor.getStance(pself) == types.Actor.STANCE.Spell then
        pself.controls.use = startUse and 1 or 0
    elseif types.Actor.getStance(pself) == types.Actor.STANCE.Weapon and input.getBooleanActionValue('Use') then
        pself.controls.use = 1
    else
        pself.controls.use = 0
    end
    startUse = false
end
local function onFrame(_)
    if controlsAllowed() then
        processAttacking()
    end
end

return {
    engineHandlers = {
        onFrame = onFrame
    }
}
