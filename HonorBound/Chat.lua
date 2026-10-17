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
-- Debug overlay in chat, matching nameplates: light grey while being asked,
-- dark grey once marked no-addon.
local GREY = {asked = "255:255:255", none = "102:102:102"}
local function GreyIcon(state)
    return "|T" .. crests .. "Grey.tga:0:0:0:0:128:128:0:128:0:128:" .. GREY[state] .. "|t "
end
local function accessible(value)
    return not (issecretvalue and issecretvalue(value))
        and (not canaccessvalue or canaccessvalue(value))
end

-- The crest a sender should wear right now, or "" for none.
local function CurrentIcon(rules, guid)
    if not rules.enabled() then return "" end
    if rules.pledged(guid) then return Icon(rules.faction(guid)) end
    local state = rules.overlay and rules.overlay(guid)
    return GREY[state] and GreyIcon(state) or ""
end

-- Recent chat lines by line ID, so a crest can be fixed once a probe
-- answers: the first message from a stranger prints before we know them.
local LINES_KEPT = 300
local lineGuid, lineOrder = {}, {}
local function RememberLine(lineID, guid)
    if lineGuid[lineID] then return end
    lineGuid[lineID] = guid
    lineOrder[#lineOrder + 1] = lineID
    if #lineOrder > LINES_KEPT then lineGuid[table.remove(lineOrder, 1)] = nil end
end

function A.CreateChatFilter(enabled, pledged, faction, overlay)
    local rules = {enabled = enabled, pledged = pledged, faction = faction, overlay = overlay}
    return function(event, name, ...)
        if not accessible(event) or not events[event] then return end
        local lineID, guid = select(11, ...)
        if not accessible(name) or type(name) ~= "string"
            or not accessible(guid) or not A.ValidGUID(guid) then return end
        if accessible(lineID) and type(lineID) == "number" then RememberLine(lineID, guid) end
        if name:find(crests, 1, true) then return end
        local icon = CurrentIcon(rules, guid)
        if icon ~= "" then return icon .. name end
    end, rules
end

-- Swap the crest inside a player link's [name], dropping any older crest.
local function Recrest(text, lineID, icon)
    local head, shown, tail = text:match("^(.-|Hplayer:[^|]-:" .. lineID .. ":[^|]*|h)(.-)(|h.*)$")
    if not head then return end
    shown = shown:gsub("|T[^|]-Media\\Crest[^|]-|t ", "")
    shown = shown:gsub("%[", "[" .. icon, 1)
    return head .. shown .. tail
end
-- Bring already-printed lines from this player up to date, where the chat
-- frames allow rewriting history. Lines the game keeps hidden are skipped.
function A.RefreshChatFor(guid)
    local rules = A.chatRules
    if not rules or not guid then return end
    local ids = {}
    for lineID, owner in pairs(lineGuid) do
        if owner == guid then ids[#ids + 1] = lineID end
    end
    if #ids == 0 then return end
    local icon = CurrentIcon(rules, guid)
    local function update(entry)
        local text = type(entry) == "table" and entry.message
        if not accessible(text) or type(text) ~= "string" or not text:find("|Hplayer:", 1, true) then return end
        for _, lineID in ipairs(ids) do
            local changed = Recrest(text, lineID, icon)
            if changed then return changed end
        end
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and type(frame.TransformMessages) == "function" then
            pcall(frame.TransformMessages, frame,
                function(entry) local changed = update(entry) return changed ~= nil and changed ~= entry.message end,
                function(entry) local changed = update(entry) if changed then entry.message = changed end end)
        end
    end
end

function A.InstallChat(enabled, pledged, faction, overlay)
    if A.chatFilter then return true end
    local api = ChatFrameUtil
    if not api or type(api.AddSenderNameFilter) ~= "function"
        or type(api.RemoveSenderNameFilter) ~= "function" then return false end
    local filter, rules = A.CreateChatFilter(enabled, pledged, faction, overlay)
    A.chatFilter, A.chatRules = filter, rules
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
