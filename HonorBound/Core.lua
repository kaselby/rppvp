local _, Addon = ...
Addon.VERSION = "0.4.0"
Addon.PREFIX = "HONORBOUND1"
Addon.CHANNEL = "HonorBound"
Addon.TTL = 180     -- seconds before a silent peer is forgotten
Addon.GRACE = 300   -- seconds a sworn player may stay unflagged before the oath breaks
function Addon.ValidGUID(guid)
    return type(guid) == "string" and #guid <= 80 and guid:match("^Player%-%d+%-%x+$") ~= nil
end
-- "S|2|<GUID>|<1 sworn and flagged, 0 otherwise>|<version>"
function Addon.Encode(guid, sworn)
    return ("S|2|%s|%d|%s"):format(guid, sworn and 1 or 0, Addon.VERSION)
end
function Addon.Decode(message)
    if type(message) ~= "string" or #message > 255 then return end
    local guid, sworn, version = message:match("^S|2|([^|]+)|([01])|([%w%.%-]+)$")
    if not Addon.ValidGUID(guid) then return end
    return guid, { sworn = sworn == "1", version = version }
end
