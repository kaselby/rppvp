-- Local display only: never alter outgoing chat or request data per message.
local _, A = ...
local events = {
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_SAY = true, CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true,
    -- Incoming whispers show the sender; outgoing ones the person whispered.
    CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
}
local crests = "Interface\\AddOns\\HonorBound\\Media\\Crest"
local function Icon(faction)
    return "|T" .. crests .. (faction == "Horde" and "Horde" or "Alliance") .. ".tga:0:0|t "
end
-- Debug overlay: light grey while being asked, dark grey once ruled out.
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

-- A stranger's first line prints before their probe answers; keep line IDs to
-- fix it later.
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
-- Re-crest this player's printed lines where the client allows it.
function A.RefreshChatFor(guid)
    local rules = A.chatRules
    if not rules or not guid then return end
    local ids = {}
    for lineID, owner in pairs(lineGuid) do
        if owner == guid then ids[#ids + 1] = lineID end
    end
    if #ids == 0 then return end
    local icon = CurrentIcon(rules, guid)
    local function update(text)
        if not accessible(text) or type(text) ~= "string" or not text:find("|Hplayer:", 1, true) then return end
        for _, lineID in ipairs(ids) do
            local changed = Recrest(text, lineID, icon)
            if changed then return changed end
        end
    end
    -- Clients differ in what they hand over: Forever passes the line's text
    -- and uses what we return (so colours and extras go back unchanged);
    -- others pass an entry table with a message field to edit in place.
    local function textOf(entry)
        if type(entry) == "table" then return entry.message end
        return entry
    end
    local function predicate(entry)
        local text = textOf(entry)
        local changed = update(text)
        return changed ~= nil and changed ~= text
    end
    local function transform(entry, ...)
        if type(entry) == "table" then
            local changed = update(entry.message)
            if changed then entry.message = changed end
            return entry, ...
        end
        return update(entry) or entry, ...
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and type(frame.TransformMessages) == "function" then
            pcall(frame.TransformMessages, frame, predicate, transform)
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
    -- TRP3 rebuilds names: stay last, even after filters re-register, without
    -- replacing anyone else's.
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

-- /honor chatcheck: how this client's chat frames look, for first-line crests. Read only.
local function Raw(text)
    if not accessible(text) then return "(hidden by the game)" end
    if type(text) ~= "string" then return "(" .. type(text) .. ")" end
    text = text:gsub("|", "||")
    return #text > 220 and (text:sub(1, 220) .. "...") or text
end
function A.ChatCheck(say)
    local frame = _G.ChatFrame1
    say("Chat name hook: " .. (A.chatRules and "installed" or "missing (no crests in chat at all)") .. ".")
    if not frame then say("ChatFrame1 not found.") return end
    say("ChatFrame1 can rewrite old lines (TransformMessages): "
        .. (type(frame.TransformMessages) == "function" and "yes" or "no") .. ".")
    local remembered, newest = #lineOrder, lineOrder[#lineOrder]
    say("Chat lines remembered by HonorBound: " .. remembered
        .. (newest and (" (newest line ID " .. tostring(newest) .. ")") or "") .. ".")
    if type(frame.TransformMessages) == "function" then
        local seen, shape, last, matches = 0, nil, nil, 0
        local wanted = {}
        for i = math.max(1, #lineOrder - 20), #lineOrder do wanted[#wanted + 1] = ":" .. tostring(lineOrder[i]) .. ":" end
        local ok, err = pcall(frame.TransformMessages, frame, function(entry)
            seen = seen + 1
            if not shape then
                if type(entry) == "table" then
                    local keys = {}
                    for key in pairs(entry) do keys[#keys + 1] = tostring(key) end
                    table.sort(keys)
                    shape = "table with " .. table.concat(keys, ", ")
                else
                    shape = type(entry)
                end
            end
            local text = type(entry) == "table" and entry.message or entry
            if accessible(text) and type(text) == "string" then
                last = text
                for _, token in ipairs(wanted) do
                    if text:find("|Hplayer:", 1, true) and text:find(token, 1, true) then matches = matches + 1 break end
                end
            end
            return false
        end, function() end)
        if not ok then say("TransformMessages errored: " .. tostring(err)) return end
        say("Lines in ChatFrame1: " .. seen .. ". Each line is a " .. tostring(shape) .. ".")
        say("Lines matching a remembered line ID inside a player link: " .. matches .. ".")
        say("A line as stored: " .. Raw(last))
    end
end
