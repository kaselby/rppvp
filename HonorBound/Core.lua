local _, Addon = ...
Addon.VERSION = "0.7.5"
Addon.PREFIX = "HONORBOUND1"
Addon.TTL = 300     -- seconds before a silent peer is forgotten
Addon.GRACE = 300   -- seconds a sworn player may stay unflagged before the oath breaks
Addon.OATHBREAKER = 24 * 3600 -- a broken oath shows for this long, in or out of game
-- Server time, so the oathbreaker mark runs out at the same moment for everyone.
function Addon.Now() return (GetServerTime and GetServerTime()) or time() end
function Addon.ValidGUID(guid)
    return type(guid) == "string" and #guid <= 80 and guid:match("^Player%-%d+%-%x+$") ~= nil
end
-- "S|2|<GUID>|<1 sworn and flagged (or inside a dungeon/raid), 0 otherwise>|<version>"
function Addon.Encode(guid, sworn)
    return ("S|2|%s|%d|%s"):format(guid, sworn and 1 or 0, Addon.VERSION)
end
function Addon.Decode(message)
    if type(message) ~= "string" or #message > 255 then return end
    local guid, sworn, version = message:match("^S|2|([^|]+)|([01])|([%w%.%-]+)$")
    if not Addon.ValidGUID(guid) then return end
    return guid, { sworn = sworn == "1", version = version }
end
-- "B|1|<GUID>|<server time the oathbreaker mark ends>|<version>"
-- Sent along with the status while the sender is an oathbreaker. Older
-- clients ignore it. An end further off than one full mark is refused.
function Addon.EncodeBroken(guid, untilTime)
    return ("B|1|%s|%d|%s"):format(guid, math.floor(untilTime), Addon.VERSION)
end
function Addon.DecodeBroken(message, now)
    if type(message) ~= "string" or #message > 255 then return end
    local guid, raw = message:match("^B|1|([^|]+)|(%d+)|[%w%.%-]+$")
    if not Addon.ValidGUID(guid) then return end
    local untilTime = tonumber(raw)
    if not untilTime or untilTime > now + Addon.OATHBREAKER + 60 then return end
    return guid, untilTime
end
-- "I|1|<GUID>|<1 inside a dungeon, raid or scenario, 0 not>|<version>"
-- Group only: members outside keep the crest of one who can't be flagged.
function Addon.EncodeInside(guid, inside)
    return ("I|1|%s|%d|%s"):format(guid, inside and 1 or 0, Addon.VERSION)
end
function Addon.DecodeInside(message)
    if type(message) ~= "string" or #message > 255 then return end
    local guid, inside, version = message:match("^I|1|([^|]+)|([01])|([%w%.%-]+)$")
    if not Addon.ValidGUID(guid) then return end
    return guid, inside == "1", version
end
