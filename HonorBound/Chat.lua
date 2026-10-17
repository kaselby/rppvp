-- Local display only: never alter outgoing chat or request data per message.
local _, A = ...
local events = {
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_SAY = true, CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
}
-- The same faction crest as on frames and nameplates. The caller works out
-- the sender's faction; any crest already in the name marks it as done.
local crests = "Interface\\AddOns\\HonorBound\\Media\\Crest"
local function Icon(faction)
    return "|T" .. crests .. (faction == "Horde" and "Horde" or "Alliance") .. ".tga:0:0|t "
end
-- Debug overlay in chat: chat icons can't be faded, so a grey crest tinted
-- dim while being asked, and light once marked no-addon.
local GREY = {asked = "110:110:110", none = "255:255:255"}
local function GreyIcon(state)
    return "|T" .. crests .. "Grey.tga:0:0:0:0:128:128:0:128:0:128:" .. GREY[state] .. "|t "
end
local function accessible(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

function A.CreateChatFilter(enabled, pledged, faction, overlay)
    return function(event, name, ...)
        if not accessible(event) or not events[event] or not enabled() then return end
        local guid = select(12, ...)
        if not accessible(name) or type(name) ~= "string"
            or not accessible(guid) or not A.ValidGUID(guid) then return end
        if name:find(crests, 1, true) then return end
        if pledged(guid) then return Icon(faction(guid)) .. name end
        local state = overlay and overlay(guid)
        if GREY[state] then return GreyIcon(state) .. name end
    end
end

function A.InstallChat(enabled, pledged, faction, overlay)
    if A.chatFilter then return true end
    local api = ChatFrameUtil
    if not api or type(api.AddSenderNameFilter) ~= "function"
        or type(api.RemoveSenderNameFilter) ~= "function" then return false end
    local filter = A.CreateChatFilter(enabled, pledged, faction, overlay)
    A.chatFilter = filter
    api.AddSenderNameFilter(filter)
    -- TRP3 rebuilds names. Run after name filters, including ones re-registered
    -- by settings changes. Never replace another addon's function or filter.
    if hooksecurefunc then
        local reordering = false
        hooksecurefunc(api, "AddSenderNameFilter", function(callback)
            if callback ~= filter and not reordering then
                reordering = true
                api.RemoveSenderNameFilter(filter)
                api.AddSenderNameFilter(filter)
                reordering = false
            end
        end)
    end
    return true
end
