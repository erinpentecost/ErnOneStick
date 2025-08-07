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
local state = require("scripts.ErnOneStick.state")
local keytrack = require("scripts.ErnOneStick.keytrack")
local core = require("openmw.core")
local self = require("openmw.self")
local localization = core.l10n(settings.MOD_NAME)
local ui = require('openmw.ui')
local input = require('openmw.input')
local controls = require('openmw.interfaces').Controls

settings.registerPage()

input.registerAction {
    key = settings.MOD_NAME .. "LockButton",
    type = input.ACTION_TYPE.Boolean,
    l10n = settings.MOD_NAME,
    name = 'lockButton_name',
    description = 'lockButton_desc',
    defaultValue = false,
}

local deadZone = 0.2

local keyLock = keytrack.NewKey("lock",
    function(dt) return input.getBooleanActionValue(settings.MOD_NAME .. "LockButton") end)
local keyForward = keytrack.NewKey("forward", function(dt)
    return input.getRangeActionValue("MoveForward") > deadZone
end)
local keyBackward = keytrack.NewKey("backward", function(dt)
    return input.getRangeActionValue("MoveBackward") > deadZone
end)

local keyLeft = keytrack.NewKey("left", function(dt)
    return input.getRangeActionValue("MoveLeft") > deadZone
end)
local keyRight = keytrack.NewKey("right", function(dt)
    return input.getRangeActionValue("MoveRight") > deadZone
end)

local stateMachine = state.NewStateContainer()

local normalState = state.NewState({
    onEnter = function()
        settings.debugPrint("enter state: normal")
        controls.overrideMovementControls(false)
    end,
    onFrame = function(dt) end
})

stateMachine:push(normalState)

local lockState = state.NewState()
local travelState = state.NewState()

lockState:set({
    onEnter = function()
        settings.debugPrint("enter state: lock")
        controls.overrideMovementControls(true)
        self.controls.movement = 0
    end,
    onFrame = function(s, dt)
        if keyLock.rise then
            print("lock state: lock")
            stateMachine:replace(travelState)
            return
        end
    end
})

travelState:set({
    onEnter = function()
        settings.debugPrint("enter state: travel")
        controls.overrideMovementControls(true)
    end,
    onFrame = function(s, dt)
        if keyLock.rise then
            print("travel state: lock")
            stateMachine:replace(lockState)
            return
        end
        if keyForward.pressed then
            self.controls.movement = 1
            self.controls.run = true
        elseif keyBackward.pressed then
            self.controls.movement = -1
            self.controls.run = true
        else
            self.controls.movement = 0
            self.controls.run = true
        end
        if keyLeft.pressed then
            self.controls.yawChange = settings.lookSensitivityHorizontal * (-1 * dt)
        elseif keyRight.pressed then
            self.controls.yawChange = settings.lookSensitivityHorizontal * dt
        else
            self.controls.yawChange = 0
        end
    end
})

stateMachine:push(travelState)

local function onFrame(dt)
    keyLock:update(dt)
    keyForward:update(dt)
    keyBackward:update(dt)
    keyLeft:update(dt)
    keyRight:update(dt)

    stateMachine:onFrame(dt)
end

return {
    engineHandlers = {
        onFrame = onFrame
    }
}
