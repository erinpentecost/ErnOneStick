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
local targets = require("scripts.ErnOneStick.targets")
local core = require("openmw.core")
local pself = require("openmw.self")
local camera = require('openmw.camera')
local localization = core.l10n(settings.MOD_NAME)
local ui = require('openmw.ui')
local util = require('openmw.util')
local aux_util = require('openmw_aux.util')
local async = require("openmw.async")
local types = require('openmw.types')
local input = require('openmw.input')
local controls = require('openmw.interfaces').Controls
local nearby = require('openmw.nearby')
local cameraInterface = require("openmw.interfaces").Camera

settings.registerPage()

if settings.disable() then
    print(settings.MOD_NAME .. " is disabled.")
    return
end

controls.overrideMovementControls(true)
cameraInterface.disableModeControl(settings.MOD_NAME)

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

local function lookAt(dt, desired)
    local direction = ((desired:getBoundingBox().center + util.vector3(0, 0, (desired:getBoundingBox().halfSize.z) / 2)) - camera.getPosition())
        :normalize()
    -- from DynamicCamera
    local targetYaw = math.atan(direction.x, direction.y)
    local targetPitch = math.max(-1.57, math.min(1.57, -math.asin(direction.z)))

    --settings.debugPrint("yaw: " .. targetYaw .. ", pitch: " .. targetPitch)
    --setFirstPersonCameraPitch(dt, targetPitch)
    --setFirstPersonCameraYaw(dt, targetYaw)
    camera.setYaw(targetYaw)
    --pself.controls.yawChange = 0
    camera.setPitch(targetPitch)
    --pself.controls.pitchChange = 0
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

local keySneak = keytrack.NewKey("sneak",
    function(dt) return input.getBooleanActionValue("Sneak") end)

-- Jump is a trigger, not an action.
input.registerTriggerHandler("Jump", async:callback(function() pself.controls.jump = true end))


-- Have to recreate sneak toggle.
local sneaking = false
local function handleSneak(dt)
    keySneak:update(dt)
    if keySneak.rise then
        sneaking = sneaking ~= true
        pself.controls.sneak = sneaking
    end
end

local stateMachine = state.NewStateContainer()

local normalState = state.NewState({
    name = "normalState",
    onFrame = function(dt) end
})

stateMachine:push(normalState)

local lockSelectionState = state.NewState()
local travelState = state.NewState()
local preliminaryFreeLookState = state.NewState()
local freeLookState = state.NewState()

lockSelectionState:set({
    name = "lockSelectionState",
    currentTarget = nil,
    actors = {},
    others = {},
    onEnter = function(base)
        settings.debugPrint("enter state: lockselection")
        pself.controls.movement = 0
        core.sendGlobalEvent(settings.MOD_NAME .. "onPause")
        camera.setMode(camera.MODE.FirstPerson, true)

        local playerHead = pself:getBoundingBox().center + util.vector3(0, 0, pself:getBoundingBox().halfSize.z)

        base.actors = targets.TargetCollection:new(nearby.actors,
            function(e)
                if e:isValid() == false then
                    return false
                end
                if types.Actor.isDead(e) then
                    return false
                end
                local center = e:getBoundingBox().center
                local castResult = nearby.castRay(center, playerHead, {
                    collisionType = nearby.COLLISION_TYPE.AnyPhysical,
                    ignore = e
                })
                --[[settings.debugPrint("raycast from " ..
                    aux_util.deepToString(playerHead, 3) ..
                    " to " ..
                    aux_util.deepToString(center, 3) .. ": hit " .. aux_util.deepToString(castResult.hitObject, 3))]]
                return (castResult.hitObject ~= nil) and (castResult.hitObject.id == pself.id)
            end)

        local others = {}
        for _, e in ipairs(nearby.activators) do
            table.insert(others, e)
        end
        for _, e in ipairs(nearby.actors) do
            table.insert(others, e)
        end
        for _, e in ipairs(nearby.items) do
            table.insert(others, e)
        end
        for _, e in ipairs(nearby.doors) do
            table.insert(others, e)
        end

        base.others = targets.TargetCollection:new(others,
            function(e)
                if e:isValid() == false then
                    return false
                end
                -- only dead actors allowed
                if e.type == types.Actor and (types.Actor.isDead(e) == false) then
                    return false
                end
                local center = e:getBoundingBox().center
                local castResult = nearby.castRay(center, playerHead, {
                    collisionType = nearby.COLLISION_TYPE.AnyPhysical,
                    ignore = e
                })
                --[[settings.debugPrint("raycast from " ..
                    aux_util.deepToString(playerHead, 3) ..
                    " to " ..
                    aux_util.deepToString(center, 3) .. ": hit " .. aux_util.deepToString(castResult.hitObject, 3))]]
                return (castResult.hitObject ~= nil) and (castResult.hitObject.id == pself.id)
            end)

        base.currentTarget = base.actors:next()
        if base.currentTarget == nil then
            base.currentTarget = base.others:next()
        end
        if base.currentTarget == nil then
            settings.debugPrint("no valid targets!")
        end
    end,
    onExit = function(base)
        core.sendGlobalEvent(settings.MOD_NAME .. "onUnpause")
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0
    end,
    onFrame = function(base, dt)
        if keyLock.rise then
            if base.currentTarget then
                -- we selected a target
                print("Locking onto " .. base.currentTarget.recordId .. " (" .. base.currentTarget.id .. ")!")
                -- TODO: enter locked state
                stateMachine:replace(travelState)
            else
                -- no target, so move to travel state.
                stateMachine:replace(travelState)
            end
            return
        end

        local newTarget = function(new)
            if (new ~= nil) and (new ~= base.currentTarget) then
                -- target changed
                base.currentTarget = new
                print("Looking at " .. base.currentTarget.recordId .. " (" .. base.currentTarget.id .. ").")
            end
        end

        -- up/down cycles actors
        -- left/right cycles everything else
        if keyForward.rise then
            newTarget(base.actors:next())
        elseif keyBackward.rise then
            newTarget(base.actors:previous())
        end
        if keyLeft.rise then
            newTarget(base.others:previous())
        elseif keyRight.rise then
            newTarget(base.others:next())
        end

        if base.currentTarget ~= nil then
            lookAt(dt, base.currentTarget)
        end
    end
})

travelState:set({
    name = "travelState",
    onEnter = function(base)
        settings.debugPrint("enter state: travel")
        camera.setMode(camera.MODE.FirstPerson, true)
    end,
    onExit = function(base)
        pself.controls.movement = 0
        pself.controls.run = false
        pself.controls.yawChange = 0
    end,
    onFrame = function(s, dt)
        if keyLock.rise then
            print("travel state: lock started")
            stateMachine:replace(preliminaryFreeLookState)
            return
        end
        -- Reset camera to foward if we are on the ground.
        -- Don't do this when swimming or levitating so the player
        -- can point up or down.
        if types.Actor.isOnGround(pself) then
            setFirstPersonCameraPitch(dt, 0)
        end
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

preliminaryFreeLookState:set({
    name = "preliminaryFreeLookState",
    onFrame = function(base, dt)
        -- we released the lock button
        if keyLock.fall then
            stateMachine:replace(lockSelectionState)
        end
        -- we started looking around
        if (keyForward.rise or keyBackward.rise or keyLeft.rise or keyRight.rise) then
            stateMachine:replace(freeLookState)
        end
    end
})

freeLookState:set({
    name = "freeLookState",
    initialMode = nil,
    initialFOV = nil,
    onEnter = function(base)
        settings.debugPrint("enter state: freeLook. " .. aux_util.deepToString(base, 3))
        -- this is not resetting base.looking
        base.initialMode = camera.getMode()
        base.initialFOV = camera.getFieldOfView()
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0

        camera.setFieldOfView(base.initialFOV / settings.freeLookZoom)
        camera.setMode(camera.MODE.FirstPerson, true)
    end,
    onExit = function(base)
        camera.setMode(base.initialMode, true)
        camera.setFieldOfView(base.initialFOV)
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
            stateMachine:replace(travelState)
            return
        end

        if keyForward.pressed then
            pself.controls.pitchChange = keyForward.analog * settings.lookSensitivityVertical * (-1 * dt) * invertLook
        elseif keyBackward.pressed then
            pself.controls.pitchChange = keyBackward.analog * settings.lookSensitivityVertical * dt * invertLook
        else
            pself.controls.pitchChange = 0
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

stateMachine:push(travelState)

local function onFrame(dt)
    keyLock:update(dt)
    keyForward:update(dt)
    keyBackward:update(dt)
    keyLeft:update(dt)
    keyRight:update(dt)
    --keyJump:update(dt)
    --keySneak:update(dt)
    handleSneak(dt)


    --[[
    if input.actions ~= nil then
        for k, v in pairs(input.actions) do
            settings.debugPrint(k .. ": " .. aux_util.deepToString(v, 3))
        end
    end
    ]]

    local currentState = stateMachine:current()
    --settings.debugPrint("current state " .. aux_util.deepToString(currentState, 3))
    currentState.onFrame(currentState, dt)
end

return {
    engineHandlers = {
        onFrame = onFrame
    }
}
