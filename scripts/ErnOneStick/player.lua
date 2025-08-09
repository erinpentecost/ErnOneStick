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
local pself = require("openmw.self")
local camera = require('openmw.camera')
local localization = core.l10n(settings.MOD_NAME)
local ui = require('openmw.ui')
local aux_util = require('openmw_aux.util')
local input = require('openmw.input')
local controls = require('openmw.interfaces').Controls

settings.registerPage()

if settings.disable() then
    print(settings.MOD_NAME .. " is disabled.")
    return
end

local runThreshold = 0.9
local invertLook = 1
if settings.invertLookVertical then
    invertLook = -1
end

local function lerpAngle(startAngle, endAngle, t)
    local diff = (endAngle - startAngle + math.pi) % (2 * math.pi) - math.pi
    local result = startAngle + diff * t;
    -- Wrap to -PI to PI
    return (result + math.pi + 2 * math.pi) % (2 * math.pi) - math.pi
end

local function setFirstPersonCameraPitch(dt, desired)
    -- these are in radians!
    camera.setPitch(lerpAngle(camera.getPitch(), desired, 0.1))
end

input.registerAction {
    key = settings.MOD_NAME .. "LockButton",
    type = input.ACTION_TYPE.Boolean,
    l10n = settings.MOD_NAME,
    name = 'lockButton_name',
    description = 'lockButton_desc',
    defaultValue = false,
}

local keyLock = keytrack.NewKey("lock",
    function(dt) return input.getBooleanActionValue(settings.MOD_NAME .. "LockButton") end)
local keyForward = keytrack.NewKey("forward", function(dt)
    return input.getRangeActionValue("MoveForward")
end)
local keyBackward = keytrack.NewKey("backward", function(dt)
    return input.getRangeActionValue("MoveBackward")
end)

local keyLeft = keytrack.NewKey("left", function(dt)
    return input.getRangeActionValue("MoveLeft")
end)
local keyRight = keytrack.NewKey("right", function(dt)
    return input.getRangeActionValue("MoveRight")
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
local freeLookState = state.NewState()

lockState:set({
    onEnter = function()
        settings.debugPrint("enter state: lock")
        controls.overrideMovementControls(true)
        pself.controls.movement = 0
        core.sendGlobalEvent(settings.MOD_NAME .. "onPause")
    end,
    onFrame = function(s, dt)
        if keyLock.rise then
            print("lock state: lock")
            stateMachine:replace(travelState)
            core.sendGlobalEvent(settings.MOD_NAME .. "onUnpause")
            return
        end
    end
})

travelState:set({
    onEnter = function(base)
        settings.debugPrint("enter state: travel")
        controls.overrideMovementControls(true)
    end,
    onFrame = function(s, dt)
        if keyLock.rise then
            print("travel state: lock started")
            pself.controls.movement = 0
            pself.controls.run = false
            pself.controls.yawChange = 0
            stateMachine:replace(freeLookState)
            return
        end
        setFirstPersonCameraPitch(dt, 0)
        if keyForward.pressed then
            pself.controls.movement = keyForward.analog
            pself.controls.run = keyForward.analog > runThreshold
        elseif keyBackward.pressed then
            pself.controls.movement = -1 * keyBackward.analog
            pself.controls.run = keyBackward.analog > runThreshold
        else
            pself.controls.movement = 0
            pself.controls.run = false
        end
        if keyLeft.pressed then
            pself.controls.yawChange = keyLeft.analog * settings.lookSensitivityHorizontal * (-1 * dt)
        elseif keyRight.pressed then
            pself.controls.yawChange = keyRight.analog * settings.lookSensitivityHorizontal * dt
        else
            pself.controls.yawChange = 0
        end
    end
})

freeLookState:set({
    looking = false,
    onEnter = function(base)
        settings.debugPrint("enter state: freeLook. " .. aux_util.deepToString(base, 3))
        controls.overrideMovementControls(true)
        -- this is not resetting base.looking
        base.looking = false
    end,
    onFrame = function(base, dt)
        -- TODO: this onFrame is the stack, not the base.

        -- this state is entered when the lock button is pressed.
        -- if the d-pad is used during this period, then we stay in this
        -- state.
        -- otherwise, we enter lock-on state.
        if keyLock.fall then
            settings.debugPrint("exiting freeLook. " .. aux_util.deepToString(base, 3))
            if base.looking then
                stateMachine:replace(travelState)
            else
                stateMachine:replace(lockState)
            end
            return
        end
        -- TODO: slow time and increase DOF if looking at this point.

        if keyForward.pressed then
            pself.controls.pitchChange = keyForward.analog * settings.lookSensitivityVertical * (-1 * dt) * invertLook
        elseif keyBackward.pressed then
            pself.controls.pitchChange = keyBackward.analog * settings.lookSensitivityVertical * dt * invertLook
        else
            pself.controls.pitchChange = 0
        end
        -- TODO: left/right in this mode causes the camera pitch to jump
        if keyLeft.pressed then
            pself.controls.yawChange = keyLeft.analog * settings.lookSensitivityHorizontal * (-1 * dt)
        elseif keyRight.pressed then
            pself.controls.yawChange = keyRight.analog * settings.lookSensitivityHorizontal * dt
        else
            pself.controls.yawChange = 0
        end

        -- only count as looking if we newly pressed the key after locking on.
        if keyForward.rise or keyBackward.rise or keyLeft.rise or keyRight.rise then
            settings.debugPrint("looking")
            base.looking = true
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

    local currentState = stateMachine:current()
    --settings.debugPrint("current state " .. aux_util.deepToString(currentState, 3))
    currentState.onFrame(currentState, dt)
end

return {
    engineHandlers = {
        onFrame = onFrame
    }
}
