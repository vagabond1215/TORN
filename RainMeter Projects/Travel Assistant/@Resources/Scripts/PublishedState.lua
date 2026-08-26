local statePath = ''
local heartbeatPath = ''

local function trim(value)
    local text = tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function readKv(path)
    local out = {}
    local file = io.open(path,'r')
    if not file then return out end
    for line in file:lines() do
        local key,value = line:match('^([^=]+)=(.*)$')
        if key then out[trim(key)] = trim(value) end
    end
    file:close()
    return out
end

local function readEpoch(path)
    local file = io.open(path,'r')
    if not file then return 0 end
    local raw = trim(file:read('*a') or '')
    file:close()
    -- Accept both the restored numeric heartbeat and the short-lived
    -- epoch|generation manifest so a partially updated Rainmeter process can
    -- survive a working-tree transition without throwing every second.
    local epoch = raw:match('^(%d+)')
    return tonumber(epoch) or 0
end

local module = {}

function module.configure(stateFile,heartbeatFile)
    statePath = stateFile or ''
    heartbeatPath = heartbeatFile or ''
end

function module.read()
    return readKv(statePath)
end

function module.epoch()
    return readEpoch(heartbeatPath)
end

return module
