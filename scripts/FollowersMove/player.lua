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
local common = require('scripts/FollowersMove/common')
local ui = require('openmw.ui')

local SCRIPTNAME = "Player"

local TELEPORT_KEY_COOLDOWN = 0.5
local TELEPORT_KEYBIND = 'FollowersMove_TeleportFollower'
input.registerAction{
    key = TELEPORT_KEYBIND,
    type = input.ACTION_TYPE.Boolean,
    l10n = 'FollowersMove',
    name = 'bind.TeleportFollower',
    description = 'bind.TeleportFollowerDesc',
    defaultValue = false,
}

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

local function onUpdate(dt)
    if not input.getBooleanActionValue(TELEPORT_KEYBIND) then return end
    local currentTime = core.getSimulationTime()
    if currentTime - lastKeyPressTime < TELEPORT_KEY_COOLDOWN then return end
    lastKeyPressTime = currentTime

    -- Build lookup table of active nearby actors
    local nearbyActorsById = common.getActiveActorsById(nearby.actors)
    local followers = globalData:asTable()
    -- How far we look for followers (first-/third-person)
    local DETECT_DIST_FP = 128
    local DETECT_DIST_TP = DETECT_DIST_FP * 1.5
    local detectDistance = (camera.getMode() == camera.MODE.FirstPerson) and DETECT_DIST_FP or DETECT_DIST_TP
    -- Height offsets for aim-cone
    local EYE_HEIGHT = 70
    local OFFSET_EYE = util.vector3(0, 0, EYE_HEIGHT)
    local OFFSET_TORSO = util.vector3(0, 0, EYE_HEIGHT * 0.5)
    local playerEyePos = self.position + OFFSET_EYE
    local camDirection = camera.viewportToWorldVector(util.vector2(0.5, 0.5)):normalize()
    -- Find best candidate
    local bestCandidate, bestDot = nil, 0
    local MIN_TARGETING_DOT = 0.866
    for _, h in ipairs({ {off=OFFSET_EYE},{off=OFFSET_TORSO},{off=util.vector3(0,0,0)} }) do
        for actorId, data in pairs(followers) do
            if data.isFollower then
                local actor = nearbyActorsById[actorId]
                if actor then
                    local actorPos = actor.position + h.off
                    local toActor = actorPos - playerEyePos
                    local dist = toActor:length()
                    if dist <= detectDistance then
                        local align = camDirection:dot(toActor)/dist
                        if align > MIN_TARGETING_DOT and align > bestDot then
                            bestDot = align
                            bestCandidate = actor
                        end
                    end
                end
            end
        end
        if bestCandidate then break end
    end
    if bestCandidate then
        local follower = {
            id = bestCandidate.id,
            recordId = bestCandidate.recordId,
            position = bestCandidate.position,
            cell = { name = bestCandidate.cell.name, region = bestCandidate.cell.region },
        }
        common.requestTeleport(follower, self.position)
    end
end

return {
    engineHandlers = {
        onUpdate = onUpdate
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
