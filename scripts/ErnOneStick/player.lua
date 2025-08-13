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
local targetui = require("scripts.ErnOneStick.targetui")
local keytrack = require("scripts.ErnOneStick.keytrack")
local targets = require("scripts.ErnOneStick.targets")
local shaderUtils = require("scripts.ErnOneStick.shader_utils")
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

settings.debugPrint("lockButton control is " .. tostring(settings.lockButton))

controls.overrideMovementControls(true)
cameraInterface.disableModeControl(settings.MOD_NAME)

local runThreshold = 0.9
local invertLook = 1
if settings.invertLookVertical then
    invertLook = -1
end

local function getSoundFilePath(file)
    return "Sound\\" .. settings.MOD_NAME .. "\\" .. file
end

local function resetCamera()
    camera.setYaw(pself.rotation:getYaw())
    camera.setPitch(pself.rotation:getPitch())
end

local function inBox(position, box)
    local normalized = box.transform:inverse():apply(position)
    return math.abs(normalized.x) <= 1
        and math.abs(normalized.y) <= 1
        and math.abs(normalized.z) <= 1
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

local function trackPitchFromVector(worldVector, t)
    local targetPitch = 0

    -- TODO: lerp is very wrong for this.
    -- TODO: solve motion sickness somehow
    --
    -- TODO: resting pitch might not be 0 anymore! that makes
    -- the minClamp not behave correctly.

    local minClamp = 0.01
    local maxTarget = targetAngles(worldVector, 1)
    if maxTarget.pitch > 0 and maxTarget.pitch < minClamp then
        targetPitch = radians.lerpAngle(maxTarget.pitch, 0, 0.8)
    elseif maxTarget.pitch < 0 and maxTarget.pitch > -1 * minClamp then
        targetPitch = radians.lerpAngle(maxTarget.pitch, 0, 0.8)
    else
        -- since we lerp first, then clamp, we'll hit the clamped values quick if the
        -- difference is very high. that's good.
        local angles = targetAngles(worldVector, t)
        -- clamp maximum changes
        targetPitch = angles.pitch
    end

    local maxPitchCorrection = 0.3
    if targetPitch > 0 then
        targetPitch = math.min(maxPitchCorrection, targetPitch)
    else
        targetPitch = math.max(-1 * maxPitchCorrection, targetPitch)
    end

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

local function isActor(entity)
    return entity.type == types.Actor or entity.type == types.NPC or entity.type == types.Creature
end

local function lockOnPosition(entity)
    -- this is bad for NPCs because you aren't looking at their faces.
    -- this is bad for items because the center of the box isn't necessarily a clickable
    -- part of the model.
    local pos = entity:getBoundingBox().center
    if isActor(entity) then
        local sizes = entity:getBoundingBox().halfSize
        -- if the actor is tall, offset so we are hopefully looking at their face.
        -- we shouldn't just point up. we should rotate this accurately for when actors
        -- are on the ground.
        if sizes.z * 0.8 > math.max(sizes.x, sizes.y) then
            pos = pos + entity.rotation:apply(util.vector3(0, 0, (sizes.z) * 0.7))
        end
    end
    return pos
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

--[[
local keyActivate = keytrack.NewKey("activate",
    function(dt) return input.getBooleanActionValue("Activate") end)
    ]]

-- Jump is a trigger, not an action.
input.registerTriggerHandler("Jump", async:callback(function() pself.controls.jump = true end))

local activating = false
input.registerTriggerHandler("Activate", async:callback(function() activating = true end))
local function handleActivate(dt)
    activating = false
end

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


local hexDofShader = shaderUtils.NewShaderWrapper("hexDoFProgrammable", {
    uDepth = 0,
    uAperture = 0.8,
    enabled = false,
})

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
    onFrame = function(s, dt)
        if uiInterface.getMode() == nil then
            stateMachine:pop()
        end
    end,
    onUpdate = function(s, dt)
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
        pself.controls.movement = 0
        pself.controls.sideMovement = 0
    end,
    onFrame = function(s, dt)
        if keyLock.rise then
            stateMachine:replace(travelState)
            return
        end
        local shouldRun = false
        track(lockOnPosition(s.base.target), 0.6)
        if keyForward.pressed then
            pself.controls.movement = keyForward.analog
            shouldRun = shouldRun or (keyForward.analog > runThreshold)
        elseif keyBackward.pressed then
            pself.controls.movement = -1 * keyBackward.analog
            shouldRun = shouldRun or (keyBackward.analog > runThreshold)
        else
            pself.controls.movement = 0
        end
        if keyLeft.pressed then
            pself.controls.sideMovement = -1 * keyLeft.analog
            shouldRun = shouldRun or (keyLeft.analog > runThreshold)
        elseif keyRight.pressed then
            pself.controls.sideMovement = keyRight.analog
            shouldRun = shouldRun or (keyRight.analog > runThreshold)
        else
            pself.controls.sideMovement = 0
        end

        pself.controls.run = shouldRun and settings.runWhileLockedOn
    end,
    onUpdate = function(s, dt)
    end
})

local function hasLOS(playerHead, entity)
    local box = entity:getBoundingBox()


    if inBox(playerHead, box) then
        settings.debugPrint("collison: " .. entity.recordId .. " contains playerhead")
        return true
    end

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
        if (castResult.hitPos ~= nil) and inBox(castResult.hitPos, box) then
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

local function getDistance(playerHead, entity)
    -- dist is a little closer because activation distance should be based
    -- on the closest face of the box, not on the center of the box.
    -- just fudge it by taking max of x,y,z box halfsize.
    local boxSize = entity:getBoundingBox().halfSize
    return (playerHead - entity:getBoundingBox().center):length() -
        math.max(boxSize.x, boxSize.y, boxSize.z)
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
        uiInterface.setHudVisibility(false)
        controls.overrideUiControls(true)
        camera.setMode(camera.MODE.FirstPerson, true)

        local playerHead = pself:getBoundingBox().center + util.vector3(0, 0, pself:getBoundingBox().halfSize.z)


        base.actors = targets.TargetCollection:new(nearby.actors,
            function(e)
                --settings.debugPrint("Filtering actor " .. e.recordId .. " (" .. e.id .. ")....")
                if e:isValid() == false then
                    return false
                end
                if types.Actor.isDead(e) then
                    return false
                end
                if e.id == pself.id then
                    return false
                end
                if e.type.records[e.recordId].name == "" then
                    -- only instances with names can be targetted
                    return false
                end

                -- dist is a little closer because activation distance should be based
                -- on the closest face of the box, not on the center of the box.
                -- just fudge it by taking max of x,y,z box halfsize.
                local dist = getDistance(playerHead, e)
                -- if the actor is very close, ignore LOS check.
                -- we were getting problems with mudcrabs (horrible creatures).
                if dist <= core.getGMST("iMaxActivateDist") / 2 then
                    return true
                end

                -- max distance
                if (dist >= 1000) then
                    return false
                end

                -- reduce max distance to activation distance if we don't have hands out
                if (dist >= core.getGMST("iMaxActivateDist")) and (types.Actor.getStance(pself) == types.Actor.STANCE.Nothing) then
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
                --settings.debugPrint("Filtering non-actor " .. e.recordId .. " (" .. e.id .. ")....")
                if e:isValid() == false then
                    return false
                end
                if e.id == pself.id then
                    return false
                end
                if e.type.records[e.recordId].name == "" then
                    -- only instances with names can be targetted
                    return false
                end
                -- only dead actors allowed
                if isActor(e) and (types.Actor.isDead(e) == false) then
                    return false
                end

                if getDistance(playerHead, e) > reach then
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
            -- we will exit this state on next frame.
        else
            settings.debugPrint("Looking at " .. base.currentTarget.recordId .. " (" .. base.currentTarget.id .. ").")
            hexDofShader.enabled = true
            core.sound.playSoundFile3d(getSoundFilePath("wind.mp3"), pself, {
                volume = settings.volume * 0.2,
                loop = true,
            })
            targetui.showTargetUI(base.currentTarget)
        end

        core.sound.playSoundFile3d(getSoundFilePath("breath_in.mp3"), pself, {
            volume = settings.volume,
        })
    end,
    onExit = function(base)
        core.sendGlobalEvent(settings.MOD_NAME .. "onUnpause")
        uiInterface.setHudVisibility(true)
        controls.overrideUiControls(false)
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0
        resetCamera()

        core.sound.stopSoundFile3d(getSoundFilePath("wind.mp3"), pself)

        hexDofShader.enabled = false
        targetui.destroy()
    end,
    onFrame = function(s, dt)
        if keyLock.rise then
            if s.base.currentTarget then
                -- we selected a target
                print("Locking onto " .. s.base.currentTarget.recordId .. " (" .. s.base.currentTarget.id .. ")!")
                lockedOnState.base.target = s.base.currentTarget
                stateMachine:replace(lockedOnState)
            else
                -- no target, so move to travel state.
                stateMachine:replace(travelState)
            end
            return
        end

        local newTarget = function(new)
            if (new ~= nil) and (new ~= s.base.currentTarget) then
                s.base.currentTarget = new
                settings.debugPrint("Looking at " ..
                    s.base.currentTarget.recordId .. " (" .. s.base.currentTarget.id .. ").")
                settings.debugPrint("ping at volume " .. tostring(settings.volume))

                targetui.showTargetUI(s.base.currentTarget)
                core.sound.playSoundFile3d(getSoundFilePath("ping.mp3"), pself, {
                    volume = settings.volume,
                })
            end
        end

        -- up/down cycles actors
        -- left/right cycles everything else
        if keyForward.rise then
            s.base.selectingActors = true
            newTarget(s.base.actors:next())
        elseif keyBackward.rise then
            s.base.selectingActors = true
            newTarget(s.base.actors:previous())
        elseif keyLeft.rise then
            s.base.selectingActors = false
            newTarget(s.base.others:previous())
        elseif keyRight.rise then
            s.base.selectingActors = false
            newTarget(s.base.others:next())
        elseif (s.base.currentTarget == nil) or (s.base.currentTarget:isValid() == false) or (s.base.currentTarget.enabled == false) then
            settings.debugPrint("Current target is no longer valid. Finding a new one...")
            -- we didn't change our target, but our current target is no longer valid.
            -- try jumping to the next one.
            if s.base.selectingActors then
                newTarget(s.base.actors:next())
                -- no more actors, so swap to non-actors.
                if s.base.currentTarget == nil then
                    newTarget(s.base.others:next())
                    s.base.selectingActors = false
                end
            else
                newTarget(s.base.others:next())
                if s.base.currentTarget == nil then
                    -- no more non-actors, so swap to actors.
                    newTarget(s.base.actors:next())
                    s.base.selectingActors = true
                end
            end
        end

        if (s.base.currentTarget == nil) then
            -- we have no valid targets at all.
            stateMachine:replace(travelState)
            return
        end

        -- point camera to the active target.
        local lockPosition = lockOnPosition(s.base.currentTarget)
        look(lockPosition, 0.3)
        hexDofShader.u.uDepth = (lockPosition - camera.getPosition()):length()

        -- check if we are activating the target.
        if activating then
            if isActor(s.base.currentTarget) and (getDistance(camera.getPosition(), s.base.currentTarget) > core.getGMST("iMaxActivateDist")) then
                settings.debugPrint("Actor target is too far away to activate.")
                -- TODO: play a negative sound
            else
                -- activation doesn't work while paused!
                -- so we need to drop out of this state and into a non-paused state.
                stateMachine:replace(travelState)
                core.sendGlobalEvent(settings.MOD_NAME .. "onActivate", {
                    entity = s.base.currentTarget,
                    player = pself,
                })
                -- TODO: play an item activation sound if this is not an actor.
            end
        end
    end,
    onUpdate = function(s, dt)
    end
})

travelState:set({
    name = "travelState",
    spotWeShouldLookAt = nil,
    onGround = false,
    onEnter = function(base)
        settings.debugPrint("enter state: travel")
        camera.setMode(camera.MODE.FirstPerson, true)
        pself.controls.sideMovement = 0
        base.spotWeShouldLookAt = nil
        base.onGround = types.Actor.isOnGround(pself)
    end,
    onExit = function(base)
        pself.controls.movement = 0
        pself.controls.run = false
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0
    end,
    onFrame = function(s, dt)
        if keyLock.rise and types.Actor.canMove(pself) then
            print("travel state: lock started")
            stateMachine:replace(preliminaryFreeLookState)
            return
        end
        pself.controls.sideMovement = 0
        -- Reset camera to foward if we are on the ground.
        -- Don't do this when swimming or levitating so the player
        -- can point up or down.
        if s.base.onGround and (s.base.spotWeShouldLookAt ~= nil) then
            -- TODO: raycast down from a foot in front of the camera
            -- so I can aim up or down when on stairs.
            --trackPitch(0, 0.1)
            trackPitchFromVector(s.base.spotWeShouldLookAt, 0.1)
        else
            pself.controls.pitchChange = 0
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
    end,
    onUpdate = function(s, dt)
        s.base.onGround = types.Actor.isOnGround(pself)
        if s.base.onGround == false then
            s.base.spotWeShouldLookAt = nil
            return
        end

        local zHalfHeight = pself:getBoundingBox().halfSize.z
        -- positive Z is up.

        local facing = pself.rotation:apply(util.vector3(0, 1, 0)):normalize()
        local leadingPosition = camera.getPosition() + (facing * 2 * pself:getBoundingBox().halfSize.y)

        local downward = util.vector3(leadingPosition.x, leadingPosition.y,
            leadingPosition.z - (10 * zHalfHeight))
        -- cast down from leading position to ground.
        local castResult = nearby.castRay(leadingPosition,
            downward,
            {
                collisionType = nearby.COLLISION_TYPE.HeightMap + nearby.COLLISION_TYPE.World,
                radius = 1
            }
        )
        if castResult.hit then
            -- we hit the ground.
            -- maybe add  camera.getFirstPersonOffset()
            s.base.spotWeShouldLookAt = castResult.hitPos +
                util.vector3(0.0, 0.0, camera.getFirstPersonOffset().z + (2 * zHalfHeight))

            --[[settings.debugPrint("hit something at z=" ..
                string.format("%.3f", castResult.hitPos.z) ..
                ". cameraZ=" ..
                string.format("%.3f", camera.getPosition().z) ..
                ". lookSpotZ=" .. string.format("%.3f", s.base.spotWeShouldLookAt.z))]]
        end
    end
})

preliminaryFreeLookState:set({
    name = "preliminaryFreeLookState",
    initialMode = nil,
    initialFOV = nil,
    timeInState = 0,
    onEnter = function(base)
        base.initialMode = camera.getMode()
        base.initialFOV = camera.getFieldOfView()
        camera.setFieldOfView(base.initialFOV / settings.freeLookZoom)
        camera.setMode(camera.MODE.FirstPerson, true)
        base.timeInState = 0
        pself.controls.yawChange = 0
        pself.controls.pitchChange = 0
        --settings.debugPrint(base.name .. ".OnEnter() = " .. aux_util.deepToString(base, 3))
    end,
    onFrame = function(s, dt)
        --settings.debugPrint(s.name .. ".OnFrame() = " .. aux_util.deepToString(s.base, 3))
        if types.Actor.canMove(pself) == false then
            stateMachine:replace(travelState)
        end

        if keyLock.fall then
            stateMachine:replace(lockSelectionState)
        elseif keyLock.pressed == false then
            -- it's possible that we miss the "fall" frame because we opened an inventory.
            stateMachine:replace(travelState)
        end

        -- we started looking around
        if (keyForward.rise or keyBackward.rise or keyLeft.rise or keyRight.rise) then
            stateMachine:replace(freeLookState)
        end
        -- if we're spending too long in this state, just go to freelook.
        s.base.timeInState = s.base.timeInState + dt
        if s.base.timeInState > 0.2 then
            settings.debugPrint("held lock for too long (" .. tostring(s.base.timeInState) .. "s), entering freelook")
            stateMachine:replace(freeLookState)
        end
    end,
    onExit = function(base)
        camera.setMode(base.initialMode, true)
        camera.setFieldOfView(base.initialFOV)
    end,
    onUpdate = function(s, dt)
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
    onFrame = function(s, dt)
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
    end,
    onUpdate = function(s, dt)
    end
})

stateMachine:push(travelState)

local function onFrame(dt)
    keyLock:update(dt)
    keyForward:update(dt)
    keyBackward:update(dt)
    keyLeft:update(dt)
    keyRight:update(dt)
    handleSneak(dt)
    handleReach()

    local currentState = stateMachine:current()
    currentState.onFrame(currentState, dt)

    -- triggers should be disabled after state handling, since they are once per frame.
    handleActivate(dt)
end

local function onUpdate(dt)
    if dt == 0 then return end
    shaderUtils.HandleShaders(dt)

    local currentState = stateMachine:current()
    currentState.onUpdate(currentState, dt)
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
