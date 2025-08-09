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
local radians = require("scripts.ErnOneStick.radians")
local keytrack = require("scripts.ErnOneStick.keytrack")
local core = require("openmw.core")
local pself = require("openmw.self")
local camera = require('openmw.camera')
local localization = core.l10n(settings.MOD_NAME)
local ui = require('openmw.ui')
local aux_util = require('openmw_aux.util')
local input = require('openmw.input')
local controls = require('openmw.interfaces').Controls
local cameraInterface = require("openmw.interfaces").Camera

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

-- reference: https://openmw.readthedocs.io/en/stable/reference/lua-scripting/openmw_self.html##(ActorControls)

local function setFirstPersonCameraPitch(dt, desired)
    -- I was having issues with camera.setPitch() causing the camera to jump around
    -- after following it up with pitchChange controls, so I dropped it.
    --camera.setPitch(radians.lerpAngle(camera.getPitch(), desired, 0.1))
    if radians.anglesAlmostEqual(camera.getPitch(), desired) then
        return
    else
        local swing = radians.subtract(camera.getPitch(), desired) * dt * 3
        pself.controls.pitchChange = swing
    end
end

local function setFirstPersonCameraYaw(dt, desired)
    if radians.anglesAlmostEqual(camera.getYaw(), desired) then
        return
    else
        local swing = radians.subtract(camera.getYaw(), desired) * dt * 3
        pself.controls.yawChange = swing
    end
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
    initialMode = nil,
    initialFOV = nil,
    onEnter = function(base)
        settings.debugPrint("enter state: freeLook. " .. aux_util.deepToString(base, 3))
        controls.overrideMovementControls(true)
        -- this is not resetting base.looking
        base.looking = false
        base.initialMode = camera.getMode()
        base.initialFOV = camera.getFieldOfView()
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0
    end,
    onFrame = function(base, dt)
        -- this state is entered when the lock button is first pressed,
        -- and ends when the lock button is released.
        -- if movement buttons are newly pressed while in this state, we
        -- set "looking" to true and force first-person perspective.
        -- when we exit this state, if "looking" is true, we go back to travel mode.
        -- otherwise, we enter lock-on mode.
        if keyLock.fall then
            settings.debugPrint("exiting freeLook. " .. aux_util.deepToString(base, 3))
            cameraInterface.enableModeControl(settings.MOD_NAME)
            camera.setMode(base.initialMode, true)
            camera.setFieldOfView(base.initialFOV)
            pself.controls.yawChange = 0
            pself.controls.pitchChange = 0
            if base.looking then
                stateMachine:replace(travelState)
            else
                stateMachine:replace(lockState)
            end
            return
        end
        -- TODO: slow time?

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
            settings.debugPrint("looking. pitch=" ..
                tostring(camera.getPitch()) .. ", extrapitch=" .. tostring(camera.getExtraPitch()))
            base.looking = true
            camera.setFieldOfView(base.initialFOV / settings.freeLookZoom)
            camera.setMode(camera.MODE.FirstPerson, true)
            cameraInterface.disableModeControl(settings.MOD_NAME)
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
