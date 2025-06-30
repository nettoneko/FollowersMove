local core = require('openmw.core')
local world = require('openmw.world')
local util = require('openmw.util')
local types = require('openmw.types')

local EVENTS = {
    Update           = 'FollowersMove_Update',
    Teleport         = 'FollowersMove_Teleport',
    FindSafePosition = 'FollowersMove_FindSafePosition',
    SafePosition     = 'FollowersMove_SafePosition',
    SetDebug         = 'FollowersMove_SetDebug',
    ShowMessageBox   = 'FollowersMove_ShowMessageBox',
}

local M = {}

function M.mapById(list)
    local out = {}
    for _, obj in ipairs(list) do
        out[obj.id] = obj
    end
    return out
end

function M.getActiveActorsById(list)
    local out = {}
    for _, obj in ipairs(list) do
        if not types.Actor.isDead(obj) and types.Actor.isInActorsProcessingRange(obj) then
            out[obj.id] = obj
        end
    end
    return out
end

function M.isBehind(player, actor)
    local forward = player.rotation * util.vector3(0, 1, 0)
    local toActor = (actor.position - player.position):normalize()
    return forward:dot(toActor) < 0
end

function M.teleportTarget(player, actor, distance)
    local behind = M.isBehind(player, actor)
    local offset = util.vector3(0, (behind and distance or -distance), 0)
    local rotated = player.rotation * offset
    return player.position + rotated
end

function M.sendUpdate(action, actor)
    core.sendGlobalEvent(EVENTS.Update, {
        action   = action,
        actorId  = actor.id,
        recordId = actor.recordId,
    })
end

function M.requestTeleport(follower, playerPos)
    core.sendGlobalEvent(EVENTS.Teleport, {
        follower       = follower,
        playerPosition = playerPos,
    })
end

function M.requestSafePosition(actorId, position, playerPosition)
    core.sendGlobalEvent(EVENTS.FindSafePosition, {
        actorId        = actorId,
        position       = position,
        playerPosition = playerPosition,
    })
end

function M.showMessageBox(message)
    core.sendGlobalEvent(EVENTS.ShowMessageBox, { message = message })
end

function M.setDebug(flag, value)
    core.sendGlobalEvent(EVENTS.SetDebug, { flag = flag, value = value })
end

return M 