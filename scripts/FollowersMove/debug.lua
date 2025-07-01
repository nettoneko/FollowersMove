-- Usage from Lua console: Lua[Player] I.FollowersMoveDebugInterface.setDebug("DEBUG", true)
local core = require('openmw.core')
local storage = require('openmw.storage')

local globalDebugData = storage.globalSection('FollowersMoveDebug')

local DEBUG_HEADER = "[FollowersMove]"
local SCRIPTNAME = "Debug"

local DEFAULT_DEBUG = true
local DEFAULT_DEBUG_VERBOSE = false
local DEFAULT_DEBUG_SPAM = false

-- Initialize default debug values if they don't exist (this script is loaded by multiple scripts) 
local function initializeDefaults()
    if globalDebugData:get("DEBUG") == nil then globalDebugData:set("DEBUG", DEFAULT_DEBUG) end
    if globalDebugData:get("DEBUG_VERBOSE") == nil then globalDebugData:set("DEBUG_VERBOSE", DEFAULT_DEBUG_VERBOSE) end
    if globalDebugData:get("DEBUG_SPAM") == nil then globalDebugData:set("DEBUG_SPAM", DEFAULT_DEBUG_SPAM) end
end

initializeDefaults()

local debug = {}

debug.DEBUG_HEADER = DEBUG_HEADER

function debug.setDebugFlag(flag, bool)
    if flag == "DEBUG" or flag == "DEBUG_VERBOSE" or flag == "DEBUG_SPAM" then
        globalDebugData:set(flag, bool)
        print(DEBUG_HEADER .. " Set " .. flag .. " to " .. tostring(bool))
        return true
    else
        print(DEBUG_HEADER .. " Invalid debug flag: " .. flag)
        print(DEBUG_HEADER .. " Valid flags: \"DEBUG\", \"DEBUG_VERBOSE\", \"DEBUG_SPAM\"")
        return false
    end
end

function debug.getDebug()
    return {
        {name = "DEBUG", value = debug.DEBUG()},
        {name = "DEBUG_VERBOSE", value = debug.DEBUG_VERBOSE()}, 
        {name = "DEBUG_SPAM", value = debug.DEBUG_SPAM()}
    }
end

function debug.debugPrint(level, source, functionName, msg, messageBox, ...)
    local args = {...}
    
    -- Only log to console if DEBUG(_*) is enabled
    if level then
        local header = DEBUG_HEADER .. "[" .. source .. "][" .. functionName .. "]"
        print(header, msg, ...)
    end
    
    -- If messageBox = true, send event to global script to handle message box display
    if messageBox then
        local fullMessage = tostring(msg)
        for _, v in ipairs(args) do
            fullMessage = fullMessage .. " " .. tostring(v)
        end
        
        debug.debugPrint(debug.DEBUG(), source, functionName, "Sending message: " .. fullMessage)
        core.sendGlobalEvent('FollowersMove_ShowMessageBox', {
            message = fullMessage
        })
    end
end

-- functions that return the debug flag value
debug.DEBUG = function() 
    local value = globalDebugData:get("DEBUG")
    return value == nil and DEFAULT_DEBUG or value
end

debug.DEBUG_VERBOSE = function() 
    local value = globalDebugData:get("DEBUG_VERBOSE")
    return value == nil and DEFAULT_DEBUG_VERBOSE or value
end

debug.DEBUG_SPAM = function() 
    local value = globalDebugData:get("DEBUG_SPAM")
    return value == nil and DEFAULT_DEBUG_SPAM or value
end

return debug 