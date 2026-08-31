-- Data transport only: never changes card layout, styling, filters or economics.
local statePath = ''
local heartbeatPath = ''
local cachedKey = nil
local cachedData = {}
local cachedEpoch = 0

local function trim(value)
    local text = tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function readText(path)
    local file = io.open(path,'r')
    if not file then return nil end
    local ok, text = pcall(function() return file:read('*a') end)
    file:close() -- Release the handle before parsing, especially for the manifest.
    if ok then return text end
    return nil
end

local function parseKv(text)
    local out = {}
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do
        local key,value = line:match('^([^=]+)=(.*)$')
        if key then out[trim(key)] = trim(value) end
    end
    return out
end

local function copyData()
    -- StateReader applies local sorting/filter overrides. Do not mutate the cache.
    local out = {}
    for key,value in pairs(cachedData) do out[key] = value end
    return out
end

local module = {}

function module.configure(stateFile,heartbeatFile)
    statePath = stateFile or '' -- Legacy finalized snapshot, for numeric heartbeats.
    heartbeatPath = heartbeatFile or ((statePath:match('^(.*[\\/])') or '') .. 'last-update.txt')
    cachedKey, cachedData, cachedEpoch = nil, {}, 0
end

function module.read()
    local raw = trim(readText(heartbeatPath))
    if raw ~= cachedKey then
        local epoch,name = raw:match('^(%d+)|(ui%-state%-%d+%-%x+%.kv)$')
        local path = nil
        if name then
            path = (statePath:match('^(.*[\\/])') or '') .. name
        elseif raw:match('^%d+$') then
            epoch, path = raw, statePath
        end
        local text = path and readText(path)
        if text then
            local data = parseKv(text)
            if tonumber(data.OpportunityCount) and tonumber(data.UIFreshestMarketSourceTimestamp)
                and (not name or data.UIGeneration == name) then
                cachedKey, cachedData, cachedEpoch = raw, data, tonumber(epoch) or 0
            end
        end
        -- Missing/partial/invalid publication: retain the last complete snapshot
        -- and its timestamp. Retry next tick; never claim a newer heartbeat.
    end
    return copyData()
end

function module.epoch()
    return cachedEpoch
end

return module
