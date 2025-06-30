local storage = require('openmw.storage')
local world = require('openmw.world')
local util = require('openmw.util')
local core = require('openmw.core')
local debug = require('scripts/FollowersMove/debug')
local globalData = storage.globalSection('FollowersMoveData')
local globalDebugData = storage.globalSection('FollowersMoveDebug')
local types = require('openmw.types')

local SCRIPTNAME = "Global"

local FOLLOWER_PLACEMENT_DISTANCE = 100
local UPDATE_INTERVAL_SECONDS = 1.0
local DEAD_FOLLOWER_CLEANUP_INTERVAL = 5.0

local playerPosition = nil
local frameCounter = 0
local cleanupCounter = 0

local function onEvent(eventData)
    if eventData.action then
        debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onEvent", "Received event - action: " .. eventData.action .. " actorId: " .. eventData.actorId .. " recordId: " .. eventData.recordId)
    else
        debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onEvent", "Received event - actorId: " .. eventData.actorId .. " recordId: " .. eventData.recordId)
    end

    local actorId = eventData.actorId
    if eventData.action == "add" or eventData.action == "update" then
        local current = globalData:get(actorId)
        if not current or not current.isFollower or current.recordId ~= eventData.recordId then
            debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onEvent", (eventData.action == "add" and "Adding" or "Updating") .. " follower " .. actorId .. " " .. eventData.recordId)
            globalData:set(actorId, {
                isFollower = true,
                recordId = eventData.recordId
            })
        end
    elseif eventData.action == "remove" then
        if globalData:get(actorId) ~= nil then
            debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onEvent", "Removing follower " .. actorId .. " " .. eventData.recordId)
            globalData:set(actorId, nil)
        end
    end

    local followers = globalData:asTable()
    local validFollowers = {}
    for id, data in pairs(followers) do
        if type(data) == "table" and data.isFollower then
            table.insert(validFollowers, {
                id = id,
                recordId = data.recordId
            })
        end
    end
    debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onEvent", "Current followers: " .. #validFollowers)
    for _, follower in ipairs(validFollowers) do
        debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onEvent", "- " .. follower.recordId .. " <" .. follower.id .. ">")
    end
end

local function onSetDebug(eventData)
    local flag = eventData.flag
    local value = eventData.value
    
    globalDebugData:set(flag, value)

    return debug.setDebugFlag(flag, value)
end

local function teleportFollower(actorId)
    local followerData = globalData:get(actorId)
    if not followerData or not followerData.isFollower then
        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "teleportFollower", "Actor " .. actorId .. " is not a follower - skipping teleport")
        return
    end

    -- Build lookup table of active actors by ID
    local activeActorsById = {}
    for _, obj in ipairs(world.activeActors) do
        activeActorsById[obj.id] = obj
    end
    
    local actor = activeActorsById[actorId]
    if not actor then
        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "teleportFollower", "Actor " .. actorId .. " not found in active actors - skipping teleport")
        return
    end
    
    local player = world.players[1]
    local playerForward = player.rotation * util.vector3(0, 1, 0)
    
    -- Determine if follower is behind the player by checking dot product
    local toActor = (actor.position - player.position):normalize()
    local isBehind = playerForward:dot(toActor) < 0
    
    local offset
    if isBehind then
        offset = util.vector3(0, FOLLOWER_PLACEMENT_DISTANCE, 0)
        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "teleportFollower", actor.recordId .. " is behind player, teleporting to front")
    else
        offset = util.vector3(0, -FOLLOWER_PLACEMENT_DISTANCE, 0)
        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "teleportFollower", actor.recordId .. " is in front of player, teleporting to back")
    end
    
    offset = player.rotation * offset
    local targetPos = playerPosition + offset
    
    actor:sendEvent('FollowersMove_FindSafePosition', {
        position = targetPos,
        playerPosition = playerPosition
    })
    debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "teleportFollower", "Requested safe position for " .. actor.recordId .. " at " .. tostring(targetPos))
end

local function onSafePositionEvent(eventData)
    if debug.DEBUG_SPAM() then
        for k, v in pairs(eventData) do
            if v == nil then
                debug.debugPrint(debug.DEBUG_SPAM(), SCRIPTNAME, "onSafePositionEvent", "WARNING: eventData field is nil: " .. k)
            else
                debug.debugPrint(debug.DEBUG_SPAM(), SCRIPTNAME, "onSafePositionEvent", "Received event field: " .. k .. " " .. tostring(v) .. " type: " .. type(v))
            end
        end
    end
    debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onSafePositionEvent", "Received safe position for " .. eventData.recordId .. ": " .. tostring(eventData.safePos))
    
    -- Build lookup table of active actors by ID
    local activeActorsById = {}
    for _, obj in ipairs(world.activeActors) do
        if not types.Actor.isDead(obj) and types.Actor.isInActorsProcessingRange(obj) then
            activeActorsById[obj.id] = obj
        end
    end
    
    local actor = activeActorsById[eventData.actorId]
    
    if actor then
        actor:teleport(world.players[1].cell, eventData.safePos)
        
        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onSafePositionEvent", "Teleported " .. actor.recordId .. " to " .. tostring(eventData.safePos))
        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onSafePositionMessageEvent", "Teleported " .. eventData.displayName, true)
    else
        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onSafePositionEvent", "Actor " .. eventData.actorId .. " not found for teleport")
    end
end

local function onTeleportEvent(eventData)
    if not eventData.follower then return end
    
    playerPosition = eventData.playerPosition
    debug.debugPrint(debug.DEBUG_VERBOSE(), SCRIPTNAME, "onTeleportEvent", "Updated player position: " .. tostring(playerPosition))
    
    teleportFollower(eventData.follower.id)
end

local function cleanupDeadFollowers()
    local followers = globalData:asTable()
    local removedCount = 0
    
    -- Build lookup table of active actors by ID
    local activeActorsById = {}
    for _, obj in ipairs(world.activeActors) do
        activeActorsById[obj.id] = obj
    end
    
    for actorId, data in pairs(followers) do
        if data.isFollower then
            local actor = activeActorsById[actorId]
            local shouldRemove = not actor or 
                                types.Actor.isDead(actor) or 
                                not types.Actor.isInActorsProcessingRange(actor)
            
            if shouldRemove then
                globalData:set(actorId, nil)
                removedCount = removedCount + 1
                
                local statusText = "missing"
                if actor then
                    statusText = types.Actor.isDead(actor) and "dead" or "inactive"
                end
                
                debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "cleanupDeadFollowers", 
                    "Removed " .. statusText .. " follower " .. actorId .. " (" .. data.recordId .. ")")
            end
        end
    end
    
    if removedCount > 0 then
        debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "cleanupDeadFollowers", 
            "Removed " .. removedCount .. " dead or inactive followers")
    end
end

local function onShowMessageBox(eventData)
    debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onShowMessageBox", "Received message: " .. eventData.message)
    -- Forward the message box event to the player script for ui access
    world.players[1]:sendEvent('FollowersMove_ShowMessageBox', {
        message = eventData.message
    })
end

return {
    engineHandlers = {
        onInit = function()
            debug.debugPrint(debug.DEBUG(), SCRIPTNAME, "onInit", "[global.lua] initialized")
        end,
        onUpdate = function(dt)
            frameCounter = frameCounter + dt
            cleanupCounter = cleanupCounter + dt
            
            -- Periodically clean up dead followers
            if cleanupCounter >= DEAD_FOLLOWER_CLEANUP_INTERVAL then
                cleanupDeadFollowers()
                cleanupCounter = 0
            end
        end
    },
    eventHandlers = {
        FollowersMove_Update = onEvent,
        FollowersMove_Teleport = onTeleportEvent,
        FollowersMove_SafePosition = onSafePositionEvent,
        FollowersMove_SetDebug = onSetDebug,
        FollowersMove_ShowMessageBox = onShowMessageBox
    }
}
