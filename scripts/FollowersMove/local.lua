local self = require('openmw.self')
local ai = require('openmw.interfaces').AI
local core = require('openmw.core')
local nearby = require('openmw.nearby')
local util = require('openmw.util')
local debug = require('scripts/FollowersMove/debug')
local types = require('openmw.types')
local common = require('scripts/FollowersMove/common')

local SCRIPTNAME = "Local"

local FOLLOW_CHECK_INTERVAL = 2.0
local NAVMESH_RETRY_DELAY = 0.05
local MAX_NAVMESH_RETRY_ATTEMPTS = 3
local INITIAL_NAVMESH_SEARCH_RADIUS = 100

local frameCounter = 0
local actor = self
local wasFollowing = false
local pendingSafePositions = {}

local function processPendingSafePositions()
    -- If no pending positions, just skip all processing
    if next(pendingSafePositions) == nil then
        return
    end
    
    local currentTime = core.getSimulationTime()
    local toRemove = {}
    
    -- Process at most 1 position per frame to avoid performance spikes
    local processed = false
    
    for requestId, data in pairs(pendingSafePositions) do
        if processed then break end
        
        -- data.position is guaranteed to exist since we created it in onFindSafePosition
        if (currentTime - (data.lastAttempt or 0) >= NAVMESH_RETRY_DELAY) or not data.lastAttempt then
            processed = true
            local radius = INITIAL_NAVMESH_SEARCH_RADIUS * (2 ^ (data.retryCount - 1))
            debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "processPendingSafePositions",
                "Attempting navmesh search for " .. actor.recordId ..
                "at " .. tostring(data.position) .. " " ..
                "with radius " .. radius .. " (retry " .. data.retryCount .. ")")

            local safePos = nearby.findNearestNavMeshPosition(data.position, radius)

            if safePos then
                if nearby.castNavigationRay(safePos, data.playerPosition) then
                    debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "processPendingSafePositions", "Navmesh path exists, teleporting " .. actor.recordId)
                    core.sendGlobalEvent('FollowersMove_SafePosition', {
                        actorId = actor.id,
                        recordId = actor.recordId,
                        displayName = self.type.records[self.recordId].name,
                        safePos = safePos
                    })
                    toRemove[requestId] = true
                else
                    debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "processPendingSafePositions", "No navmesh path, teleport not needed for " .. actor.recordId)
                    if data.retryCount >= MAX_NAVMESH_RETRY_ATTEMPTS then
                        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "processPendingSafePositions", "No path to player found after " .. MAX_NAVMESH_RETRY_ATTEMPTS .. " retries for [" .. actor.recordId .. "] - teleport cancelled", true)
                        toRemove[requestId] = true
                    else
                        data.retryCount = data.retryCount + 1
                        data.lastAttempt = currentTime
                    end
                end
            else
                if data.retryCount >= MAX_NAVMESH_RETRY_ATTEMPTS then
                    debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "processPendingSafePositions", "No navmesh position found after " .. MAX_NAVMESH_RETRY_ATTEMPTS .. " retries for [" .. actor.recordId .. "] - teleport cancelled", true)
                    toRemove[requestId] = true
                else
                    data.retryCount = data.retryCount + 1
                    data.lastAttempt = currentTime
                end
            end
        end
    end

    for requestId in pairs(toRemove) do
        pendingSafePositions[requestId] = nil
    end
end

local function onUpdate(dt)
    if types.Actor.isDead(actor) or not types.Actor.isInActorsProcessingRange(actor) then
        if wasFollowing then
            core.sendGlobalEvent('FollowersMove_Update', {
                action = "remove",
                actorId = actor.id,
                recordId = actor.recordId
            })
            wasFollowing = false
            debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onUpdate", "Actor died or became inactive, removed from followers list: " .. actor.recordId)
        end
        return
    end

    frameCounter = frameCounter + dt
    if frameCounter >= FOLLOW_CHECK_INTERVAL then
        if debug.DEBUG_SPAM() then
            debug.debugPrint(debug.DEBUG_SPAM(), SCRIPTNAME, "onUpdate", "Processing actor.id: " .. actor.id .. " recordId: " .. actor.recordId)
        end
            local package = ai.getActivePackage()
            local packageType = package and package.type or "None"
            if debug.DEBUG_VERBOSE() then
                debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onUpdate", actor.recordId .. " has package type: " .. packageType)
            end
            local isFollowing = false
            if packageType == "Follow" or packageType == "Escort" then
                local target = ai.getActiveTarget(packageType)
                if target and target.recordId == "player" then
                    if debug.DEBUG_VERBOSE() then
                        debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onUpdate", actor.recordId .. " follows player")
                    end
                    isFollowing = true
                end
            end
            if isFollowing ~= wasFollowing then
                local action = isFollowing and "add" or "remove"
                core.sendGlobalEvent('FollowersMove_Update', {
                    action = action,
                    actorId = actor.id,
                    recordId = actor.recordId
                })
                if debug.DEBUG_VERBOSE() then
                    debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onUpdate", (action == "add" and "Adding" or "Removing") .. " follower " .. actor.recordId)
                end
            end
            wasFollowing = isFollowing
        frameCounter = frameCounter - FOLLOW_CHECK_INTERVAL
    end
    
    processPendingSafePositions()
end

local function onFindSafePosition(eventData)
    debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onFindSafePosition", "Received safe position request for " .. actor.recordId .. " at position " .. tostring(eventData.position))

    local safePos = nearby.findNearestNavMeshPosition(eventData.position, INITIAL_NAVMESH_SEARCH_RADIUS)

    if safePos then
        if eventData.playerPosition then
            -- Check if a path exists from the safe position to the player
            -- This ensures we don't teleport to unreachable areas
            if nearby.castNavigationRay(safePos, eventData.playerPosition) then
                debug.debugPrint(
                    debug.DEBUG(), SCRIPTNAME, "onFindSafePosition",
                    "Navmesh path exists, teleporting " .. actor.recordId
                )
                local event = {
                    actorId = actor.id,
                    recordId = actor.recordId,
                    displayName = self.type.records[self.recordId].name,
                    safePos = safePos
                }
                debug.debugPrint(debug.DEBUG_SPAM(), SCRIPTNAME, "onFindSafePosition", "About to send event: actorId: " .. actor.id .. " recordId: " .. actor.recordId)
                if debug.DEBUG_SPAM() then
                    for k, v in pairs(event) do
                        debug.debugPrint(debug.DEBUG_SPAM(), SCRIPTNAME, "onFindSafePosition", "Event field: " .. k .. " " .. tostring(v))
                    end
                end
                core.sendGlobalEvent('FollowersMove_SafePosition', event)
            else
                debug.debugPrint(
                    debug.DEBUG(), SCRIPTNAME, "onFindSafePosition",
                    "No navmesh path, teleport not needed for " .. actor.recordId
                )
            end
        else
            debug.debugPrint(
                debug.DEBUG(), SCRIPTNAME, "onFindSafePosition",
                "Found safe position for [" .. actor.recordId .. "] at " .. tostring(safePos) .. 
                " with radius " .. INITIAL_NAVMESH_SEARCH_RADIUS .. " (no navmesh check)"
            )
            local event = {
                actorId = actor.id,
                recordId = actor.recordId,
                displayName = self.type.records[self.recordId].name,
                safePos = safePos
            }
            debug.debugPrint(debug.DEBUG_SPAM(), SCRIPTNAME, "onFindSafePosition", "About to send event: actorId: " .. actor.id .. " recordId: " .. actor.recordId)
            if debug.DEBUG_SPAM() then
                for k, v in pairs(event) do
                    debug.debugPrint(debug.DEBUG_SPAM(), SCRIPTNAME, "onFindSafePosition", "Event field: " .. k .. " " .. tostring(v))
                end
            end
            core.sendGlobalEvent('FollowersMove_SafePosition', event)
        end
    else
        debug.debugPrint(
            debug.DEBUG(), SCRIPTNAME, "onFindSafePosition",
            "No safe position found with radius " .. INITIAL_NAVMESH_SEARCH_RADIUS .. " - scheduling retry"
        )
        -- Store request for later retry with exponentially increasing radius
        -- Each retry doubles the search radius to find valid positions farther away
        local requestId = actor.id .. "_" .. core.getSimulationTime()
        pendingSafePositions[requestId] = {
            position = eventData.position,
            playerPosition = eventData.playerPosition,
            retryCount = 1,
            lastAttempt = core.getSimulationTime()
        }
    end
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
        onInit = function()
            debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onInit", "initialized for " .. self.recordId .. " <" .. self.id .. ">")
        end
    },
    eventHandlers = {
        FollowersMove_FindSafePosition = onFindSafePosition
    }
}
