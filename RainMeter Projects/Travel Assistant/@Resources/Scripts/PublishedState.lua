local fallbackPath = ''
local manifestPath = ''
local generatedDir = ''
local cachedKey = ''
local cachedData = nil
local cachedEpoch = 0

local function trim(value)
    local text = tostring(value or ''):gsub('^\239\187\191','')
    return (text:gsub('^%s+',''):gsub('%s+$',''))
end

local function readText(path)
    local file = io.open(path,'r')
    if not file then return '' end
    local raw = file:read('*a') or ''
    file:close()
    return trim(raw)
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

local function readManifest()
    local raw = readText(manifestPath)
    local epoch,name = raw:match('^(%d+)|([%w%._%-]+)$')
    if epoch and name and name:match('^ui%-state%-%d+%-%x+%.kv$') then
        return tonumber(epoch) or 0,name
    end
    return tonumber(raw) or 0,''
end

local module = {}

function module.configure(stateFile,heartbeatFile)
    fallbackPath = stateFile or ''
    manifestPath = heartbeatFile or ''
    generatedDir = fallbackPath:match('^(.*[\\/])') or ''
end

function module.read()
    local epoch,name = readManifest()
    if epoch > 0 and name ~= '' then
        local key = tostring(epoch)..'|'..name
        if cachedData ~= nil and cachedKey == key then return cachedData end
        local candidate = readKv(generatedDir..name)
        if tonumber(candidate.UIGeneration) == epoch and candidate.OpportunityCount ~= nil then
            cachedKey = key
            cachedEpoch = epoch
            cachedData = candidate
            return candidate
        end
    end
    if cachedData ~= nil then return cachedData end
    return readKv(fallbackPath)
end

function module.epoch()
    local epoch = readManifest()
    if epoch > 0 then return epoch end
    return cachedEpoch
end

return module
