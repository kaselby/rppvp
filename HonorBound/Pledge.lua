local _, A = ...

local function valid(level)
    return type(level) == "number" and level >= 1 and level <= 60
        and level == math.floor(level)
end

-- "P|1|<GUID>|<level sworn since, 0 none>|<version>"
function A.EncodePledge(guid, level)
    return ("P|1|%s|%d|%s"):format(guid, valid(level) and level or 0, A.VERSION)
end

function A.DecodePledge(message)
    if type(message) ~= "string" or #message > 255 then return end
    local guid, raw, version = message:match("^P|1|([^|]+)|(%d+)|([%w%.%-]+)$")
    if not A.ValidGUID(guid) then return end
    local level = tonumber(raw)
    if raw ~= "0" and (not valid(level) or tostring(level) ~= raw) then return end
    return guid, {sworn = level ~= 0, version = version,
        pledgedSinceLevel = level ~= 0 and level or nil}
end

-- An S message keeps a fresh pledge level but never extends its lifetime.
function A.MergePledgePeer(previous, incoming, now, isPledge)
    incoming.seen = now
    if isPledge and incoming.sworn then
        incoming.pledgeSeen = now
    elseif incoming.sworn and previous and previous.pledgeSeen
        and now - previous.pledgeSeen < A.TTL then
        incoming.pledgedSinceLevel = previous.pledgedSinceLevel
        incoming.pledgeSeen = previous.pledgeSeen
    end
    return incoming
end

function A.PeerPledgeLevel(peer, now)
    if peer and peer.pledgeSeen and now - peer.pledgeSeen < A.TTL then
        return A.PledgeLevel(peer)
    end
end

function A.StartPledge(record, level)
    record.pledgedSinceLevel = valid(level) and level or nil
end

function A.EnsurePledge(record, level)
    if not record.sworn then
        record.pledgedSinceLevel = nil
    elseif valid(level) and (not valid(record.pledgedSinceLevel) or record.pledgedSinceLevel > level) then
        A.StartPledge(record, level)
    end
end

function A.PledgeLevel(record)
    if record and record.sworn and valid(record.pledgedSinceLevel) then
        return record.pledgedSinceLevel
    end
end
