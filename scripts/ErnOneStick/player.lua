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
local boxes = require("scripts.ErnOneStick.boxes")
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
local uiInterface = require("openmw.interfaces").UI

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

local reach = 0
local handleReach = function()
    -- magnitude of telekinesis is in feet
    -- need "Constants::UnitsPerFoot" =  21.33333333f
    -- normal reach is gmst: iMaxActivateDist, which is in game units
    local dist = core.getGMST("iMaxActivateDist")
    local telekinesisEffect = types.Actor.activeEffects(pself):getEffect(core.magic.EFFECT_TYPE.Telekinesis)
    if telekinesisEffect ~= nil then
        dist = dist + telekinesisEffect.magnitude * 21.33333333
    end
    reach = dist
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
local uiState = state.NewState()

uiState:set({
    name = "uiState",
    onEnter = function(base)
        controls.overrideMovementControls(false)
    end,
    onExit = function(base)
        controls.overrideMovementControls(true)
    end,
    onFrame = function(base, dt)
        if uiInterface.getMode() == nil then
            stateMachine:pop()
        end
    end
})

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
        track(base.target:getBoundingBox().center, 0.6)
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

local function hasLOS(playerHead, entity)
    local box = entity:getBoundingBox()

    -- should add anything that the item intersects with to the
    -- ignore list. items clip into tables and weapon racks.
    -- instead of casting from the center of the entity, cast from near the surface of the box
    -- facing the playerHead. this is needed so items on racks don't collide with the wall meshes.
    local fudgeFactor = math.min(30, (playerHead - box.center):length() / 2)

    local startPosition = box.center + (((playerHead - box.center)):normalize() * fudgeFactor)

    local ignoreList = {}
    table.insert(ignoreList, entity)
    for i = 1, 10 do
        local castResult = nearby.castRay(startPosition, playerHead, {
            collisionType = nearby.COLLISION_TYPE.Default,
            ignore = ignoreList
        })
        if castResult.hit == false then
            settings.debugPrint("collison: " .. entity.recordId .. " shot out into space")
            return false
        end
        if (castResult.hitObject ~= nil) and (castResult.hitObject.id == pself.id) then
            return true
        end
        -- if the thing we hit is intersecting with us, then skip it and try again.
        if (castResult.hitPos ~= nil) and boxes.inBox(castResult.hitPos, box) then
            settings.debugPrint("inBox(" .. tostring(castResult.hitPos) .. "," .. tostring(entity.recordId) .. ")")
            -- ignore the thing we hit (if it's an object)
            if castResult.hitObject ~= nil then
                table.insert(ignoreList, castResult.hitObject)
            end
            -- also advance the start position (in the case of world or heightmap)
            startPosition = castResult.hitPos
        else
            if castResult.hitObject ~= nil then
                settings.debugPrint("collison: " .. entity.recordId .. " stopped by " .. castResult.hitObject.recordId)
            else
                settings.debugPrint("collison: " .. entity.recordId .. " stopped by something")
            end

            return false
        end
    end
    settings.debugPrint("collison: " .. entity.recordId .. " gave up")
    return false
end

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
                -- use an extra-long reach if we have weapons or spells ready.
                local actorReach = reach
                if types.Actor.getStance(pself) ~= types.Actor.STANCE.Nothing then
                    actorReach = 1000
                end
                if (playerHead - e:getBoundingBox().center):length() > actorReach then
                    return false
                end
                return hasLOS(playerHead, e)
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
        for _, e in ipairs(nearby.containers) do
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
                if (playerHead - e:getBoundingBox().center):length() > reach then
                    return false
                end
                return hasLOS(playerHead, e)
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
                -- TODO: why is this being called multiple times for one button press??
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
        elseif keyLeft.rise then
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
        if keyLock.rise and types.Actor.canMove(pself) then
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
        if types.Actor.canMove(pself) == false then
            stateMachine:replace(travelState)
        end
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
        if keyLock.fall or (types.Actor.canMove(pself) == false) then
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
    handleReach()


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

local function UiModeChanged(data)
    if (data.newMode ~= nil) and (data.oldMode == nil) then
        stateMachine:push(uiState)
    end
end

return {
    eventHandlers = {
        UiModeChanged = UiModeChanged
    },
    engineHandlers = {
        onFrame = onFrame,
        onUpdate = onUpdate
    }
}
