local input = require('openmw.input')
local storage = require('openmw.storage')
local core = require('openmw.core')
local nearby = require('openmw.nearby')
local self = require('openmw.self')
local camera = require('openmw.camera')
local util = require('openmw.util')
local debug = require('scripts/FollowersMove/debug')
local globalData = storage.globalSection('FollowersMoveData')
local types = require('openmw.types')
local ui = require('openmw.ui')

local SCRIPTNAME = "Player"

local TELEPORT_KEY_COOLDOWN = 0.5
local FOLLOWER_TELEPORT_KEY = input.KEY.B
-- TODO: switch to input.registerAction so the key can be changed in-game.

local lastKeyPressTime = 0

-- Usage: enter player context via `luap` in console, call: I.FollowersMoveDebugInterface.setDebug("DEBUG_VERBOSE", true)
local function setDebug(flag, value)
    -- Must use global event as player scripts can't modify global storage directly
    core.sendGlobalEvent('FollowersMove_SetDebug', {
        flag = flag,
        value = value
    })
    return true
end

  local function getDebugStatus()
      local status = debug.getDebug()
      local flags = {}

    -- Format the flag list in a human-readable way
      for i, flag in ipairs(status) do
          table.insert(flags, flag.name .. " = " .. tostring(flag.value))
      end
      
      return table.concat(flags, "\n")
  end

-- Direct message box handler
local function onShowMessageBox(eventData)
    debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onShowMessageBox", "Displaying message box: " .. eventData.message)
    ui.showMessage(eventData.message)
end

local function onKeyPress(key)
    debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onKeyPress", "input: " .. (key.symbol ~= "" and "symbol=" .. key.symbol or "code=" .. key.code))
    local currentTime = core.getSimulationTime()
    if currentTime - lastKeyPressTime < TELEPORT_KEY_COOLDOWN then
        return
    end

    if key.code == FOLLOWER_TELEPORT_KEY then
        lastKeyPressTime = currentTime
        
        -- Build lookup table for nearby actors by ID for O(1) lookups
        local nearbyActorsById = {}
        for _, obj in ipairs(nearby.actors) do
            if not types.Actor.isDead(obj) and types.Actor.isInActorsProcessingRange(obj) then
                nearbyActorsById[obj.id] = obj
            end
        end
        
        local followers = globalData:asTable()
        -- How far we look for followers. 3rd-person gets a slightly larger radius.
        local DETECT_DIST_FP = 128 -- first-person
        local DETECT_DIST_TP = DETECT_DIST_FP * 1.5 -- third-person
        local detectDistance = (camera.getMode() == camera.MODE.FirstPerson) and DETECT_DIST_FP or DETECT_DIST_TP

        -- Height offsets for aim-cone tests
        local EYE_HEIGHT = 70
        local OFFSET_EYE = util.vector3(0, 0, EYE_HEIGHT)
        local OFFSET_TORSO = util.vector3(0, 0, EYE_HEIGHT * 0.5)

        local playerEyePos = self.position + OFFSET_EYE

        -- Camera forward direction (already in world-space)
        local camDirection = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()

        -- Try three vertical slices, breaking as soon as one yields a valid target.
        local MIN_TARGETING_DOT = 0.866  -- ~30° half-angle cone
        local HEIGHT_TESTS = {
            {offset = OFFSET_EYE,   label = "eye"},
            {offset = OFFSET_TORSO, label = "torso"},
            {offset = util.vector3(0, 0, 0), label = "ground"}
        }

        local bestCandidate = nil
        local bestDot = 0
        local chosenHeightLabel = ""

        for _, h in ipairs(HEIGHT_TESTS) do
            local offset = h.offset
            bestCandidate = nil
            bestDot = 0

            for actorId, data in pairs(followers) do
                if data.isFollower then
                    local actor = nearbyActorsById[actorId]
                    if actor then
                        local actorAimPos = actor.position + offset
                        local toActor = actorAimPos - playerEyePos
                        local distance = toActor:length()

                        if distance <= detectDistance then
                            local alignment = camDirection:dot(toActor) / distance

                            if alignment > MIN_TARGETING_DOT and alignment > bestDot then
                                bestDot = alignment
                                bestCandidate = actor
                                chosenHeightLabel = h.label
                            end
                        end
                    end
                end
            end

            if bestCandidate then
                debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onKeyPress", "Targeting height level: " .. chosenHeightLabel)
                break -- found at this height, no need for lower levels
            end
        end

        if bestCandidate then
            local followerData = globalData:get(bestCandidate.id)
            if followerData and followerData.isFollower then
                local distance = (bestCandidate.position - playerEyePos):length()
                debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onKeyPress", "Teleporting " .. bestCandidate.recordId .. " dot: " .. bestDot)
                debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onKeyPress", "Selected follower " .. bestCandidate.recordId .. " at distance " .. distance .. " units")
                
                debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onKeyPress", "Player at " .. tostring(self.position))
                
                -- Send teleport event to global script with follower and position data
                -- Event flow: player.lua -> global.lua (teleportFollower) -> local.lua (findSafePosition) 
                -- -> global.lua (onSafePositionEvent) -> actual teleport
                core.sendGlobalEvent('FollowersMove_Teleport', {
                    follower = {
                        id = bestCandidate.id,
                        recordId = bestCandidate.recordId,
                        position = bestCandidate.position,
                        cell = {
                            name = bestCandidate.cell.name,
                            region = bestCandidate.cell.region
                        }
                    },
                    playerPosition = self.position
                })
            else
                debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "Teleport", bestCandidate.recordId .. " is not a follower - skipping teleport")
            end
        else
            debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "Teleport", "No follower hit by raycast.")
        end
        return false -- Block default B key behavior
    end
end

return {
    engineHandlers = {
        onKeyPress = onKeyPress
    },
    eventHandlers = {
        FollowersMove_ShowMessageBox = onShowMessageBox
    },
    -- interface to expose functions to Lua console
    interfaceName = 'FollowersMoveDebugInterface',
    interface = {
        setDebug = setDebug,
        getDebugStatus = getDebugStatus
    }
}
