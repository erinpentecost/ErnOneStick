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

local onGround = types.Actor.isOnGround(pself)

-- reference: https://openmw.readthedocs.io/en/stable/reference/lua-scripting/openmw_self.html##(ActorControls)

local function resetCamera()
    camera.setYaw(pself.rotation:getYaw())
    camera.setPitch(pself.rotation:getPitch())
end

local function targetAngles(worldVector, t)
    -- This swings the viewport toward worldVector
    if t == nil then
        t = 1
    end

    local direction = (worldVector - camera.getPosition()):normalize()
    -- Two-variable atan2 is not available here!
    local targetYaw = util.normalizeAngle(math.atan2(direction.x, direction.y))
    local targetPitch = util.normalizeAngle(-math.asin(direction.z))

    targetYaw = radians.lerpAngle(pself.rotation:getYaw(), targetYaw, t)
    targetPitch = radians.lerpAngle(pself.rotation:getPitch(), targetPitch, t)

    return {
        yaw = targetYaw,
        pitch = targetPitch
    }
end

local function trackPitch(targetPitch, t)
    if t == nil then
        t = 1
    end
    targetPitch = radians.lerpAngle(pself.rotation:getPitch(), targetPitch, t)

    if radians.anglesAlmostEqual(pself.rotation:getPitch(), targetPitch) then
        return
    end

    camera.setPitch(targetPitch)
    pself.controls.pitchChange = radians.subtract(pself.rotation:getPitch(), targetPitch)
end

local function track(worldVector, t)
    local angles = targetAngles(worldVector, t)

    if radians.anglesAlmostEqual(pself.rotation:getYaw(), angles.yaw) and radians.anglesAlmostEqual(pself.rotation:getPitch(), angles.pitch) then
        return
    end

    camera.setPitch(angles.pitch)
    pself.controls.pitchChange = radians.subtract(pself.rotation:getPitch(), angles.pitch)

    camera.setYaw(angles.yaw)
    pself.controls.yawChange = radians.subtract(pself.rotation:getYaw(), angles.yaw)
end

local function look(worldVector, t)
    -- This is instant and works during pause.
    local angles = targetAngles(worldVector, t)

    if radians.anglesAlmostEqual(pself.rotation:getYaw(), angles.yaw) and radians.anglesAlmostEqual(pself.rotation:getPitch(), angles.pitch) then
        return
    end

    -- Actually rotate the player so they are facing that direction.
    -- This will also change the camera to match.
    local trans = util.transform
    core.sendGlobalEvent(settings.MOD_NAME .. "onRotate", {
        object = pself,
        rotation = trans.rotateZ(angles.yaw) * trans.rotateX(angles.pitch)
    })

    -- this all matches
    --[[settings.debugPrint("Yaw/Pitch: target(" ..
        string.format("%.3f", targetYaw) ..
        "/" .. string.format("%.3f", targetPitch) ..
        ") actual(" ..
        string.format("%.3f", camera.getYaw()) .. "/" .. string.format("%.3f", camera.getPitch()) ..
        ") self(" ..
        string.format("%.3f", pself.rotation:getYaw()) .. "/" .. string.format("%.3f", pself.rotation:getPitch()) ..
        ")")]]
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
local lockedOnState = state.NewState()
local travelState = state.NewState()
local preliminaryFreeLookState = state.NewState()
local freeLookState = state.NewState()

lockedOnState:set({
    name = "lockedOnState",
    target = nil,
    onEnter = function(base)
        pself.controls.movement = 0
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0
        pself.controls.run = false
        if base.target == nil then
            error("no target for locked-on state")
        end
    end,
    onExit = function(base)
        resetCamera()
    end,
    onFrame = function(base, dt)
        if keyLock.rise then
            stateMachine:replace(travelState)
            return
        end
        track(base.target:getBoundingBox().center, 0.3)
        if keyForward.pressed then
            pself.controls.movement = keyForward.analog
        elseif keyBackward.pressed then
            pself.controls.movement = -1 * keyBackward.analog
        else
            pself.controls.movement = 0
        end
        if keyLeft.pressed then
            pself.controls.sideMovement = -1 * keyLeft.analog
        elseif keyRight.pressed then
            pself.controls.sideMovement = keyRight.analog
        else
            pself.controls.sideMovement = 0
        end
    end,
})

lockSelectionState:set({
    name = "lockSelectionState",
    selectingActors = true,
    currentTarget = nil,
    actors = {},
    others = {},
    onEnter = function(base)
        settings.debugPrint("enter state: lockselection")
        pself.controls.movement = 0
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0
        resetCamera()
        core.sendGlobalEvent(settings.MOD_NAME .. "onPause")
        camera.setMode(camera.MODE.FirstPerson, true)

        local playerHead = pself:getBoundingBox().center + util.vector3(0, 0, pself:getBoundingBox().halfSize.z)
        --local playerHead = camera.getPosition()

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
                if (playerHead - center):length() > 500 then
                    -- TODO: increase when we have Telekinesis
                    return false
                end
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
        base.selectingActors = true
        if base.currentTarget == nil then
            base.currentTarget = base.others:next()
            base.selectingActors = false
        end
        if base.currentTarget == nil then
            settings.debugPrint("no valid targets!")
        end
    end,
    onExit = function(base)
        core.sendGlobalEvent(settings.MOD_NAME .. "onUnpause")
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0
        resetCamera()
    end,
    onFrame = function(base, dt)
        if keyLock.rise then
            if base.currentTarget then
                -- we selected a target
                print("Locking onto " .. base.currentTarget.recordId .. " (" .. base.currentTarget.id .. ")!")
                lockedOnState.base.target = base.currentTarget
                stateMachine:replace(lockedOnState)
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
            base.selectingActors = true
            newTarget(base.actors:next())
        elseif keyBackward.rise then
            base.selectingActors = true
            newTarget(base.actors:previous())
        end
        if keyLeft.rise then
            base.selectingActors = false
            newTarget(base.others:previous())
        elseif keyRight.rise then
            base.selectingActors = false
            newTarget(base.others:next())
        end

        if (base.currentTarget == nil) then
            stateMachine:replace(travelState)
            return
        end

        -- If we stay paused, then targets should remain valid as we cycle through them.
        if base.currentTarget:isValid() and base.currentTarget.enabled then
            look(base.currentTarget:getBoundingBox().center, 0.3)
        else
            settings.debugPrint("target no longer valid")
            stateMachine:replace(travelState)
            return
        end

        -- TODO: why are we looking away after picking up a tracked item?
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
        if onGround then
            trackPitch(0, 0.1)
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

        resetCamera()

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

local function onUpdate(dt)
    if dt == 0 then return end
    onGround = types.Actor.isOnGround(pself)
end

return {
    engineHandlers = {
        onFrame = onFrame,
        onUpdate = onUpdate
    }
}
