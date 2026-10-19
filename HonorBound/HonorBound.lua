-- HonorBound: a community crest for players sworn to RP-PvP.
--
-- The oath. Each character swears once. A sworn character stays flagged for
-- PvP: "Disable" in the portrait menu is greyed out, and if anything unflags
-- you (typing /pvp, entering a dungeon) you get GRACE seconds to reflag
-- before the oath breaks. A broken oath can be sworn again with /honor swear.
--
-- Reflagging. Blizzard won't let addons set the flag; only your own click or
-- keypress can. So while a sworn player is unflagged, the addon borrows their
-- action bar keys: the next press runs /pvp and then the ability on that key,
-- and the keys go back at once. /pvp is left alone, because a replaced /pvp
-- can't flag you either. Dungeons and raids pause the countdown (you can't
-- reflag inside), and it restarts when you leave.
--
-- The badge. Your crest shows only while you're sworn and flagged. Other
-- players' crests need both their sworn broadcast and the server's live flag
-- (UnitIsPVP), so an unflagged player never wears one.
local _, A = ...
local MEDIA = "Interface\\AddOns\\HonorBound\\Media\\"
local eventFrame = CreateFrame("Frame")
local db, char, myGUID, myServer, lastAnnounce, lastPayload, lastPledgePayload
local announceRetryAt = 0
local peers, widgets, plates = {}, {}, {}
local lastAnswer, lastMinute = -100, 0
local guarded, countLeft, countedAt, prompt, promptAfterCombat
local Refresh, Announce, UpdatePrompt, RefreshPlate

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd479HonorBound:|r " .. text)
end
-- Session-only diagnostics: no extra network traffic or saved logs.
-- "on" shows status updates, failures and a summary a minute; "verbose"
-- adds every whisper probe and reply.
local debugEnabled, debugVerbose = false, false
local function Debug(text, verbose)
    if debugEnabled and (debugVerbose or not verbose) then
        local clock = date and date("%H:%M:%S") or ("%.0fs"):format(GetTime())
        DEFAULT_CHAT_FRAME:AddMessage("|cff9d9d9dHonorBound " .. clock .. "|r  " .. text)
    end
end
-- Coloured first word so a line reads at a glance.
local SENT, HEARD, FAILED = "|cffffd100Sent|r", "|cff55ff55Heard|r", "|cffff5555Couldn't send|r"
local ROUTES = {CHANNEL = "the realm channel", GUILD = "your guild", PARTY = "your party",
    RAID = "your raid", INSTANCE_CHAT = "your instance group", WHISPER = "a whisper",
    YELL = "a yell", SAY = "say"}
-- Plain reasons for the game's addon-message result codes.
local REASONS = {InvalidPrefix = "the addon's message name isn't registered",
    InvalidMessage = "the message was rejected", AddonMessageThrottle = "sending too fast, the game is throttling us",
    InvalidChatType = "that kind of message isn't allowed here", NotInGroup = "you're not in a group",
    TargetRequired = "no target was given", InvalidChannel = "you're not in that channel",
    ChannelThrottle = "the channel is busy, the game is throttling us", GeneralError = "the game refused it",
    NotInGuild = "you're not in a guild", AddOnMessageLockdown = "addon messages are blocked during encounters",
    TargetOffline = "that player is offline"}
-- Codes from Enum.SendAddonMessageResult, for clients that don't expose it.
local CODE_NAMES = {[1] = "InvalidPrefix", [2] = "InvalidMessage", [3] = "AddonMessageThrottle",
    [4] = "InvalidChatType", [5] = "NotInGroup", [6] = "TargetRequired", [7] = "InvalidChannel",
    [8] = "ChannelThrottle", [9] = "GeneralError", [11] = "AddOnMessageLockdown"}
local function Reason(result)
    local codes = Enum and Enum.SendAddonMessageResult
    if type(codes) == "table" then
        for name, code in pairs(codes) do
            if code == result then return REASONS[name] or name end
        end
    end
    local name = CODE_NAMES[result]
    return name and REASONS[name] or ("the game refused it (code " .. tostring(result) .. ")")
end
-- "1 player", "2 players".
local function Count(n, word, plural)
    return n .. " " .. (n == 1 and word or (plural or word .. "s"))
end
local function StatusWords(sworn, level)
    if not sworn then return "not sworn" end
    return level and level > 0 and ("sworn since level " .. level) or "sworn"
end
-- Names and message descriptions need the discovery tables, defined below.
local Who, Describe
local function Secret(value)
    return issecretvalue and issecretvalue(value)
end
local function GUID(unit)
    if type(unit) ~= "string" then return end
    local value = UnitGUID(unit)
    if Secret(value) or not A.ValidGUID(value) then return end
    return value
end
local function Desired()
    return GetPVPDesired() and true or false
end
local function Flagged(unit)
    local value = UnitIsPVP(unit)
    if Secret(value) then return false end
    return value and true or false
end
local function Faction(unit)
    local faction = UnitFactionGroup(unit)
    if Secret(faction) or (faction ~= "Alliance" and faction ~= "Horde") then return "Alliance" end
    return faction
end
-- Chat senders aren't units: read the faction from their race, falling back
-- to our own (whispers and most chat don't cross factions anyway).
local RACE_FACTION = {
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance",
    Draenei = "Alliance", Worgen = "Alliance", VoidElf = "Alliance", LightforgedDraenei = "Alliance",
    DarkIronDwarf = "Alliance", KulTiran = "Alliance", Mechagnome = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde", BloodElf = "Horde",
    Goblin = "Horde", Nightborne = "Horde", HighmountainTauren = "Horde", MagharOrc = "Horde",
    ZandalariTroll = "Horde", Vulpera = "Horde",
}
local function ChatFaction(guid)
    if guid ~= UnitGUID("player") and GetPlayerInfoByGUID then
        local _, _, _, race = GetPlayerInfoByGUID(guid)
        if not Secret(race) and RACE_FACTION[race] then return RACE_FACTION[race] end
    end
    return Faction("player")
end
local function InPausedInstance()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid" or kind == "scenario") or false
end
-- Dungeons and raids unflag you and you can't reflag inside, so there a
-- sworn player keeps the crest. Anyone we can see in one is in it with us;
-- a group member who's in one without us says so ("I" messages), and that
-- word holds for groupInside.fresh seconds unless they say they've left.
-- groupInside.at[guid]: when they last said so. groupInside.told: whether
-- our own last announcement said we were inside.
local groupInside = {fresh = 150, at = {}, told = false}
local function FlaggedOrInside(unit, guid)
    if Flagged(unit) or InPausedInstance() then return true end
    local at = guid and groupInside.at[guid]
    return at ~= nil and GetTime() - at < groupInside.fresh
end
local function Sworn()
    return char and char.sworn and (Desired() or InPausedInstance())
end
local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Status updates go to the group and guild; everyone else is reached by
-- whisper. No hidden channel.

-- The client's per-prefix allowance (10, refilling 1 a second) doesn't apply
-- to whispers outside instanced content, so whispers go out unpaced there.
-- Inside dungeons and raids, and for group/guild messages, keep this budget.
local TOKEN_MAX, TOKEN_RATE = 5, 0.5
local tokens, tokenTime = TOKEN_MAX, 0
local function Refill()
    local now = GetTime()
    tokens = math.min(TOKEN_MAX, tokens + (now - tokenTime) * TOKEN_RATE)
    tokenTime = now
end
local function Afford(cost)
    Refill()
    return tokens >= cost
end
local function Instanced()
    if not IsInInstance then return false end
    local inside = IsInInstance()
    return inside and true or false
end
-- Refused sends, for developers: debug mode only. The first at once, then
-- one summary every 10 s so a burst doesn't flood chat.
local REFUSED_EVERY = 10
local refused = {count = 0, reasons = {}, reported = -100}
local function NoteRefused(reason)
    refused.count = refused.count + 1
    refused.reasons[reason] = (refused.reasons[reason] or 0) + 1
end
local function ReportRefused(now)
    if refused.count == 0 or now - refused.reported < REFUSED_EVERY then return end
    local why = {}
    for reason, n in pairs(refused.reasons) do why[#why + 1] = reason .. (n > 1 and (" ×" .. n) or "") end
    table.sort(why)
    Debug("|cffff5555Rate limited:|r " .. Count(refused.count, "message") .. " refused"
        .. (refused.reported > 0 and (" in the last " .. REFUSED_EVERY .. " s") or "") .. ": " .. table.concat(why, "; ") .. ".")
    refused.count, refused.reasons, refused.reported = 0, {}, now
end
-- During boss encounters the game blocks addon messages, and while zoning
-- (the loading screen and a few seconds after arriving) it rejects them.
-- Don't even try then: nothing is sent, counted as refused or retried; it
-- resumes afterwards. A.zonePauseUntil is set by the zoning events.
A.ZONE_SETTLE = 3
local function SendingBlocked()
    if (A.zonePauseUntil or 0) > GetTime() then return true end
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() and true or false
end
local function Send(message, route, target)
    if SendingBlocked() then return false end
    if route ~= "WHISPER" or Instanced() then
        Refill()
        tokens = math.max(-TOKEN_MAX, tokens - 1)
    end
    local result = C_ChatInfo.SendAddonMessage(A.PREFIX, message, route, target)
    local ok = result == true or result == 0
    if not ok then
        -- The client pushed back: stop optional group/guild traffic for a moment.
        tokens = math.min(tokens, -2)
        NoteRefused(Reason(result))
    end
    if debugEnabled then
        local where = route == "WHISPER" and ("a whisper to " .. tostring(target)) or ROUTES[route] or route
        -- Failures always show; every successful send only in verbose.
        if ok then
            Debug(SENT .. " " .. Describe(message) .. " via " .. where .. ".", true)
        else
            Debug(FAILED .. " " .. Describe(message) .. " via " .. where .. ": " .. Reason(result) .. ".")
        end
    end
    return ok
end
local function GroupRoute()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end
local function PledgePayload()
    return A.EncodePledge(myGUID or "", Sworn() and A.PledgeLevel(char))
end
local lastPledgePayload
Announce = function(force)
    if not db or not myGUID then return end
    local now = GetTime()
    local payload = A.Encode(myGUID, Sworn())
    local pledgePayload = PledgePayload()
    local inside = InPausedInstance()
    -- Include metadata changes in the existing announcement throttle.
    local unchanged = payload == lastPayload and pledgePayload == lastPledgePayload and inside == groupInside.told
    -- Keep repeated world/group events from flooding the group,
    -- but let a changed oath through straight away.
    if unchanged and lastAnnounce and now - lastAnnounce < 3 then return end
    if not force and unchanged and lastAnnounce and now - lastAnnounce < 60 then return end
    -- Nothing got through last time: wait before trying again.
    if now < announceRetryAt then return end
    -- Not during an encounter or while zoning; it goes out once that's over.
    if SendingBlocked() then A.announceAfterPause = true return end
    local reached = {}
    local function To(route, target, extra)
        if Send(payload, route, target) and Send(pledgePayload, route, target)
            and (not extra or Send(extra, route, target)) then
            reached[#reached + 1] = ROUTES[route]
        end
    end
    -- The group hears whether we're inside: while we are, and once more
    -- when we come out.
    if GroupRoute() then To(GroupRoute(), nil, (inside or groupInside.told) and A.EncodeInside(myGUID, inside)) end
    if IsInGuild() then To("GUILD") end
    local mine = StatusWords(Sworn(), Sworn() and A.PledgeLevel(char))
    if #reached > 0 then
        lastAnnounce, lastPayload, lastPledgePayload, groupInside.told = now, payload, pledgePayload, inside
        Debug(SENT .. " your status (" .. mine .. ") to " .. table.concat(reached, ", ") .. ".")
    elseif GroupRoute() or IsInGuild() then
        announceRetryAt = now + 10
        Debug("Couldn't announce your status (" .. mine .. "). Trying again in 10 s.")
    end
end
---------------------------------------------------------------------------
-- Whisper probes: everyone we see (nameplates, mouseover, target, chat) is
-- asked directly, same realm or not. A probe carries our own status, so the
-- other side learns us from it and never needs to probe back. One reply
-- completes the exchange.

local PROBE_TIMEOUT = 30         -- no reply by then: treat as no addon
local PROBE_STALE = 30           -- queued this long without sending (instances only): drop
local NO_ADDON = 7200            -- our own silent probe: don't ask for 2 hours
local LIKELY_KEEP = 14 * 86400   -- remember addon users for two weeks
-- Refresh peers still in view well before they expire: REPROBE_AFTER plus up
-- to REPROBE_JITTER spreads re-checks out.
local REPROBE_AFTER, REPROBE_JITTER = A.TTL - 90, 45
local QUEUE_MAX, REPLY_MAX, REPLY_GAP = 500, 200, 60
-- Lower sends first: known addon users, mouseover/target, chat, nameplates.
local PRIORITY_LIKELY, PRIORITY_UNIT, PRIORITY_CHAT, PRIORITY_PLATE = 0, 1, 2, 3
local probes, probeCount, pending, replies, replied = {}, 0, {}, {}, {}
local noAddon, likely = {}, {}  -- saved; keyed by GUID, times from time()
local names, jitter = {}, {}
-- Optional pacing for testing: whispers per second, nil = unlimited.
local whisperCap
local stats = {probed = 0, answered = 0, silent = 0, unreachable = 0}

-- Simulation (/honor sim N): N% of the players we ask pretend to have the
-- addon and answer quickly. Everything else stays real: probes, budget,
-- timeouts and the no-addon list. Who pretends is a fixed hash of the GUID,
-- so every tester with the same N sees the same players. Session only.
local simPercent
local SIM_DELAY = {0.5, 3} -- round trip plus the other side's reply queue
-- Seen-to-result timings for the coverage line: {total seconds, count}.
local seenAt, probeTimed = {}, {}
local timings = {probe = {0, 0}, answer = {0, 0}, none = {0, 0}}
local function SimHash(guid)
    local h = 5381
    for i = 1, #guid do h = (h * 33 + guid:byte(i)) % 4294967296 end
    return h % 100
end
A.SimHash = SimHash
local function Simulated(guid)
    return simPercent ~= nil and SimHash(guid) < simPercent
end
-- On the no-addon list right now. A simulated user stands in for someone who
-- has the addon, who wouldn't be on it, so the list never blocks them.
local function RuledOut(guid)
    return noAddon[guid] and time() < noAddon[guid] and not Simulated(guid)
end
-- A remembered addon user's last known oath. It shows their crest the moment
-- they're seen, while a re-check goes out; a fresh answer replaces it, and it
-- stops counting after CACHE_MISSES unanswered re-checks in a row.
local CACHE_MISSES = 2
local function Cached(guid)
    local entry = likely[guid]
    return entry and entry.sworn and (entry.misses or 0) < CACHE_MISSES and not RuledOut(guid) or false
end
local function Seen(guid)
    if seenAt[guid] == nil then seenAt[guid] = GetTime() end
end
local function Timed(kind, guid)
    local t, at = timings[kind], seenAt[guid]
    if at then t[1], t[2] = t[1] + GetTime() - at, t[2] + 1 end
end
local function TimeProbe(guid)
    if not probeTimed[guid] then probeTimed[guid] = true Timed("probe", guid) end
end
-- First result only: a later refresh of the same player isn't "populating".
local function TimeResult(kind, guid)
    Timed(kind, guid)
    if seenAt[guid] then seenAt[guid] = false end
end

local function Server(guid)
    return guid and guid:match("^Player%-(%d+)%-")
end
local function OtherRealm(guid)
    return myServer and Server(guid) ~= myServer
end
local function Locked()
    return SendingBlocked()
end
local function Between(range)
    return range[1] + math.random() * (range[2] - range[1])
end
-- Whisper targets need Name-Realm, with the realm's spaces and dashes removed.
local function FullName(name, realm)
    if Secret(name) or Secret(realm) or type(name) ~= "string" or name == "" then return end
    if type(realm) == "string" and realm ~= "" and not name:find("-", 1, true) then
        name = name .. "-" .. realm:gsub("[%s%-]", "")
    end
    return name
end
-- Forever names are "First Surname". Whispers there go to "First-Surname",
-- the form UnitName gives (surname in the realm slot); "First Surname-Realm",
-- from GetPlayerInfoByGUID or a whisper's sender, bounces. Elsewhere names
-- have no spaces and pass through unchanged.
local function Address(name)
    if type(name) ~= "string" or Secret(name) then return name end
    local first, surname = name:match("^([^%s%-]+)%s+([^%-]+)")
    if not first then return name end
    return first .. "-" .. surname:gsub("[%s%-]", "")
end
local function GuidName(guid)
    if not GetPlayerInfoByGUID then return end
    local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
    return Address(FullName(name, realm))
end
local function ValidName(name)
    return type(name) == "string" and #name <= 64 and name:match("^[^%-|]+%-[^%-|]+$") ~= nil
end
-- A player's name for debug lines, falling back to a short ID.
Who = function(guid)
    if not guid then return "someone" end
    if guid == myGUID then return "you" end
    return names[guid] or GuidName(guid) or (likely[guid] and likely[guid].name)
        or ("player " .. (guid:match("^Player%-(.+)$") or guid))
end
-- What an addon message says, in words.
Describe = function(message)
    local kind = message:match("^(%u+)|")
    if kind == "S" then
        local guid, sworn = message:match("^S|2|([^|]+)|([01])|")
        return (guid == myGUID and "your" or (Who(guid) .. "'s")) .. " status (" .. StatusWords(sworn == "1") .. ")"
    elseif kind == "P" then
        local guid, level = message:match("^P|1|([^|]+)|(%d+)|")
        return (guid == myGUID and "your" or (Who(guid) .. "'s")) .. " pledge level ("
            .. (level and level ~= "0" and ("since level " .. level) or "none") .. ")"
    elseif kind == "Q" then
        return "a question: does " .. Who(message:match("^Q|1|(.+)$")) .. " have the addon?"
    elseif kind == "WQ" then
        return "a probe (do you have the addon? here's my status)"
    elseif kind == "WR" then
        return "a reply (yes, I have the addon, here's my status)"
    elseif kind == "I" then
        local guid, inside = message:match("^I|1|([^|]+)|([01])|")
        return (guid == myGUID and "that you're" or (Who(guid) .. " is")) .. (inside == "1" and " inside" or " out of")
            .. " a dungeon or raid"
    elseif kind == "F" then
        local _, name = message:match("^F|1|([^|]+)|([^|]+)|")
        return "a find: " .. tostring(name) .. " has the addon"
    elseif kind == "FS" then
        local _, name = message:match("^FS|1|([^|]+)|([^|]+)|")
        return "a simulated find: " .. tostring(name)
    elseif kind == "N" then
        local list = message:match("^N|1|(.*)$") or ""
        local _, commas = list:gsub(",", "")
        return "a list of " .. Count(commas + 1, "player") .. " without the addon"
    end
    return "a message (" .. message .. ")"
end
local function DecodeStatus(sworn, raw, version)
    local level = tonumber(raw)
    if not level or level > 60 then return end
    return {sworn = sworn == "1", version = version, pledgedSinceLevel = level > 0 and level or nil}
end
local function WhisperPayload(kind)
    local level = Sworn() and A.PledgeLevel(char) or 0
    return ("W%s|1|%s|%d|%d|%s"):format(kind, myGUID, Sworn() and 1 or 0, level, A.VERSION)
end
local function DecodeWhisper(message)
    local kind, guid, sworn, raw, version = message:match("^W([QR])|1|([^|]+)|([01])|(%d+)|([%w%.%-]+)$")
    if not A.ValidGUID(guid) then return end
    local peer = DecodeStatus(sworn, raw, version)
    if peer then return kind, guid, peer end
end
local function FoundPayload(guid, name, peer)
    return ("F|1|%s|%s|%d|%d|%s"):format(guid, name, peer.sworn and 1 or 0,
        peer.pledgedSinceLevel or 0, peer.version or "?")
end
-- Same status as the last one shared for this player?
local function SameStatus(record, peer)
    return record and record.sworn == peer.sworn and record.level == (peer.pledgedSinceLevel or 0)
end

-- A player's status changed: fix the crest on their recent chat lines too.
local function ChatChanged(guid)
    if A.RefreshChatFor then A.RefreshChatFor(guid) end
end
-- A simulated user answering our probe. Only resolves if we're still
-- waiting: a real reply, an unreachable error or a timeout wins.
local function SimAnswer(guid, name)
    if not simPercent or not pending[guid] then return end
    pending[guid] = nil
    local now = GetTime()
    stats.answered = stats.answered + 1
    peers[guid] = {sworn = true, version = "sim", simulated = true, seen = now}
    Debug(HEARD .. " a simulated answer from " .. (name or Who(guid)) .. ".", true)
    TimeResult("answer", guid)
    ChatChanged(guid)
    Refresh()
end
local function SimProbe(guid, name)
    TimeProbe(guid)
    if Simulated(guid) then
        C_Timer.After(Between(SIM_DELAY), function() SimAnswer(guid, name) end)
    end
end

local function Probe(guid, priority, name)
    local now = GetTime()
    local peer = peers[guid]
    -- Spread re-probes so everyone doesn't refresh the same player at once.
    jitter[guid] = jitter[guid] or math.random(0, REPROBE_JITTER)
    if peer and now - peer.seen < REPROBE_AFTER + jitter[guid] then return end
    if pending[guid] or RuledOut(guid) then return end
    if likely[guid] then priority = PRIORITY_LIKELY end
    name = name or names[guid] or (likely[guid] and likely[guid].name)
    Seen(guid)
    local entry = probes[guid]
    if entry then
        entry.priority = math.min(entry.priority, priority)
        entry.name = entry.name or name
        return
    end
    if probeCount >= QUEUE_MAX then return end
    probes[guid], probeCount = {priority = priority, at = now, name = name}, probeCount + 1
end
local function Unqueue(guid)
    if probes[guid] then probes[guid], probeCount = nil, probeCount - 1 end
end
-- Everyone gets a whisper probe, same realm or not.
local function Query(guid, priority, name)
    if not guid or not myGUID or guid == myGUID then return end
    return Probe(guid, priority or PRIORITY_PLATE, name)
end
local function QueryUnit(unit, priority)
    local guid = GUID(unit)
    if not guid or guid == myGUID or not UnitIsPlayer(unit) then return end
    -- Whispers can't cross factions; skip anyone we couldn't reach anyway.
    local theirs, ours = UnitFactionGroup(unit), UnitFactionGroup("player")
    if Secret(theirs) or Secret(ours) or theirs ~= ours then return end
    Query(guid, priority, FullName(UnitName(unit)))
end

local function MarkNoAddon(guid, why)
    -- A remembered user gets a second chance: one dropped whisper shouldn't
    -- hide a crest. The next sighting asks again.
    local entry = likely[guid]
    if entry and (entry.misses or 0) + 1 < CACHE_MISSES then
        entry.misses = (entry.misses or 0) + 1
        Debug(Who(guid) .. " didn't answer a re-check; their saved status stands until one more goes unanswered.", true)
        return
    end
    noAddon[guid] = time() + NO_ADDON
    likely[guid] = nil
    stats[why] = stats[why] + 1
    TimeResult("none", guid)
    ChatChanged(guid)
end

-- Whether another whisper may go out this tick: unlimited outside instances
-- unless /honor rate sets a cap; inside, the client's budget applies.
local function MayWhisper(sentThisTick)
    if Instanced() then return Afford(1) end
    return not whisperCap or sentThisTick < whisperCap
end
-- Every tick: all waiting replies, then every queued probe, most urgent first.
local function PumpWhispers(now)
    for guid, p in pairs(pending) do
        if now - p.at > PROBE_TIMEOUT then
            pending[guid] = nil
            MarkNoAddon(guid, "silent")
            Debug("No answer from " .. p.name .. " after " .. PROBE_TIMEOUT .. " s: marked as not having the addon for 2 hours.", true)
        end
    end
    local sent = 0
    while replies[1] and now - replies[1].at > PROBE_STALE do table.remove(replies, 1) end
    -- A refused send didn't happen: nothing is marked or used up, it stays
    -- queued, and the pass stops until the next second.
    while replies[1] and MayWhisper(sent) do
        local reply = replies[1]
        if not Send(WhisperPayload("R"), "WHISPER", reply.name) then return end
        table.remove(replies, 1)
        replied[reply.name] = now
        sent = sent + 1
    end
    local order = {}
    for guid, e in pairs(probes) do
        if now - e.at > PROBE_STALE then
            probes[guid], probeCount = nil, probeCount - 1
        else
            order[#order + 1] = {guid = guid, e = e, tie = math.random()}
        end
    end
    table.sort(order, function(a, b)
        if a.e.priority ~= b.e.priority then return a.e.priority < b.e.priority end
        return a.tie < b.tie
    end)
    for _, item in ipairs(order) do
        if not MayWhisper(sent) then return end
        local guid, e = item.guid, item.e
        Unqueue(guid)
        local name = e.name or GuidName(guid)
        if name then -- not resolvable yet: the next sighting re-queues
            if not Send(WhisperPayload("Q"), "WHISPER", name) then
                -- Refused: not asked after all, so no answer is awaited (no
                -- false "no addon"). Back in line; it's dropped if it waits
                -- too long, and asked again when next seen.
                probes[guid], probeCount = e, probeCount + 1
                return
            end
            pending[guid] = {at = now, name = name}
            stats.probed = stats.probed + 1
            sent = sent + 1
            ChatChanged(guid)
            SimProbe(guid, name)
        end
    end
end
local function PumpProbes()
    local now = GetTime()
    if Locked() or not myGUID then return end
    PumpWhispers(now)
end

local function OnWhisper(message, sender)
    if Secret(sender) or type(sender) ~= "string" then return end
    sender = Address(sender)
    local kind, guid, peer = DecodeWhisper(message)
    if not kind or guid == myGUID then return end
    -- The status claims a GUID; it must belong to whoever sent it.
    local known = GuidName(guid)
    if known and known:match("^[^%-]+") ~= sender:match("^[^%-]+") then return end
    Debug(HEARD .. " " .. (kind == "Q" and "a probe from " or "a reply from ") .. sender .. ": they have the addon ("
        .. StatusWords(peer.sworn, peer.pledgedSinceLevel) .. ")" .. (kind == "Q" and ", and now know about you." or "."), true)
    local now = GetTime()
    peers[guid] = A.MergePledgePeer(peers[guid], peer, now, true)
    noAddon[guid] = nil
    local probed = pending[guid]
    pending[guid] = nil
    if probed then stats.answered = stats.answered + 1 end
    TimeResult("answer", guid)
    -- Senders can arrive without a realm; prefer a full Name-Realm.
    local name = (probed and probed.name) or known or sender
    if ValidName(name) then likely[guid] = {name = name, seen = time(), sworn = peer.sworn or nil,
        level = peer.pledgedSinceLevel} end
    Unqueue(guid)
    ChatChanged(guid)
    -- Always answer a probe, even with ours in flight: ours may never arrive.
    local queued = false
    for _, r in ipairs(replies) do queued = queued or r.name == name end
    if kind == "Q" and not queued and #replies < REPLY_MAX
        and not (replied[name] and now - replied[name] < REPLY_GAP) then
        replies[#replies + 1] = {name = name, at = now}
    end
    Refresh()
end
-- A probe to someone unreachable comes back as a system error; hide it.
local function HideUnreachable(_, _, message)
    if Secret(message) or type(message) ~= "string" then return end
    -- The server's own "too fast" notice: count it with the refused sends,
    -- and leave the message visible.
    for _, notice in ipairs({ERR_CHAT_THROTTLED, ERR_GENERIC_THROTTLE}) do
        if type(notice) == "string" and message == notice then
            NoteRefused("the server says we're sending too fast")
            return
        end
    end
    if not ERR_CHAT_PLAYER_NOT_FOUND_S then return end
    for guid, p in pairs(pending) do
        if message == ERR_CHAT_PLAYER_NOT_FOUND_S:format(p.name) then
            pending[guid] = nil
            MarkNoAddon(guid, "unreachable")
            Debug(p.name .. " can't be whispered (offline, or out of reach): marked as not having the addon.", true)
            return true
        end
    end
    local now = GetTime()
    for name, at in pairs(replied) do
        if now - at < 5 and message == ERR_CHAT_PLAYER_NOT_FOUND_S:format(name) then
            Debug("Our reply to " .. name .. " bounced (no player by that name).")
            return true
        end
    end
end
-- Load the saved caches, dropping anything expired or malformed.
local function LoadCaches()
    local now = time()
    db.noAddon = type(db.noAddon) == "table" and db.noAddon or {}
    db.likely = type(db.likely) == "table" and db.likely or {}
    for guid, expires in pairs(db.noAddon) do
        if not A.ValidGUID(guid) or type(expires) ~= "number" or expires <= now then db.noAddon[guid] = nil end
    end
    for guid, entry in pairs(db.likely) do
        if type(entry) == "table" then entry.name = Address(entry.name) end
        if not A.ValidGUID(guid) or type(entry) ~= "table" or not ValidName(entry.name)
            or type(entry.seen) ~= "number" or now - entry.seen > LIKELY_KEEP then
            db.likely[guid] = nil
        end
    end
    noAddon, likely = db.noAddon, db.likely
end
local function PruneCaches()
    local now = time()
    for guid, expires in pairs(noAddon) do
        if now >= expires then noAddon[guid] = nil end
    end
    local clock = GetTime()
    for name, at in pairs(replied) do
        if clock - at > REPLY_GAP then replied[name] = nil end
    end
    for guid, at in pairs(seenAt) do
        if at and clock - at > 3600 then seenAt[guid], probeTimed[guid] = nil, nil end
    end
end
-- Debug overlay states for players without a real crest.
local function DebugState(guid)
    if not guid or guid == myGUID then return end
    if pending[guid] then return "asked" end
    if RuledOut(guid) then return "none" end
end
-- How far discovery has got over the nameplates in view, and how long it took.
local function Coverage()
    local addon, none, asked, queued, other, total = 0, 0, 0, 0, 0, 0
    local now = GetTime()
    for unit in pairs(plates) do
        local guid = GUID(unit)
        if guid and guid ~= myGUID and UnitIsPlayer(unit) then
            total = total + 1
            local peer = peers[guid]
            local state = DebugState(guid)
            if peer and now - peer.seen < A.TTL then addon = addon + 1
            elseif state == "asked" then asked = asked + 1
            elseif state == "none" then none = none + 1
            elseif probes[guid] then queued = queued + 1
            else other = other + 1 end
        end
    end
    local function avg(t) return t[2] > 0 and (math.floor(t[1] / t[2] + 0.5) .. " s") or "n/a" end
    return ("%s on screen: %d have the addon, %d don't, %d being asked, %d waiting in line, %d not asked.%s"
        .. " On average after first seeing someone: asked in %s, answered in %s, ruled out in %s.")
        :format(Count(total, "player"), addon, none, asked, queued, other,
            simPercent and (" (Simulating " .. simPercent .. "% addon users.)") or "",
            avg(timings.probe), avg(timings.answer), avg(timings.none))
end
-- One line a minute instead of a line per stranger.
local function DebugSummary()
    if simPercent or next(plates) then Debug(Coverage()) end
    if stats.probed + stats.answered + stats.silent + stats.unreachable == 0 then return end
    local parts = {}
    local function add(count, text, ...)
        if count > 0 then parts[#parts + 1] = text:format(Count(count, ...)) end
    end
    add(stats.probed, "probed %s", "player")
    add(stats.answered, "got %s", "answer")
    add(stats.silent, "%s went unanswered", "probe")
    add(stats.unreachable, "%s couldn't be whispered", "player")
    add(probeCount, "%s still waiting in line", "player")
    Debug("Since the last summary: " .. table.concat(parts, ", ") .. ".")
    for key in pairs(stats) do stats[key] = 0 end
end
-- Whether a unit wears the badge right now.
local function Status(unit)
    local guid = GUID(unit)
    if not guid then return end
    if guid == myGUID then
        if char and char.sworn and FlaggedOrInside("player", guid) then return { version = A.VERSION } end
        return
    end
    if UnitIsPlayer(unit) then
        QueryUnit(unit, unit:find("^nameplate") and PRIORITY_PLATE or PRIORITY_UNIT)
    end
    local peer = peers[guid]
    if peer and GetTime() - peer.seen < A.TTL then
        -- Simulated users stand in for "wears a badge", flagged or not.
        if peer.sworn and (peer.simulated or FlaggedOrInside(unit, guid)) then return peer end
        return
    end
    -- Nothing fresh: their saved status, while the re-check is out. Only for
    -- players a whisper can reach (our faction); nobody else gets re-checked.
    local theirs, ours = UnitFactionGroup(unit), UnitFactionGroup("player")
    local reachable = not Secret(theirs) and not Secret(ours) and theirs == ours
    if reachable and Cached(guid) and FlaggedOrInside(unit, guid) then
        return {sworn = true, cached = true, pledgedSinceLevel = likely[guid].level, pledgeSeen = GetTime()}
    end
end
-- Normal crest, or the debug overlay: light grey while being asked, dark grey
-- once marked no-addon.
local OVERLAY_TINT = {asked = {1, 1, 1}, none = {0.4, 0.4, 0.4}}
local function CrestLook(texture, state)
    if texture.SetDesaturated then texture:SetDesaturated(state ~= nil) end
    local tint = OVERLAY_TINT[state] or OVERLAY_TINT.asked
    if texture.SetVertexColor then texture:SetVertexColor(tint[1], tint[2], tint[3]) end
    texture:SetAlpha(1)
end
local function OverlayState(unit)
    if not unit or not (debugEnabled or simPercent) then return end
    return DebugState(GUID(unit))
end

---------------------------------------------------------------------------
-- The oath

local function GreyOutDisable()
    if not UnitPopupPvpDisableButtonMixin then return false end
    UnitPopupPvpDisableButtonMixin.IsEnabled = function() return false end
    return true
end
-- Greys out "Disable" in the portrait menu. /pvp is left alone: replacing it
-- would stop it flagging you too, and the reflag keys rely on it. Typing /pvp
-- to unflag just starts the grace countdown like any other unflag.
local function Guard()
    if guarded then return end
    guarded = true
    if not GreyOutDisable() then eventFrame:RegisterEvent("ADDON_LOADED") end
end

---------------------------------------------------------------------------
-- Reflag on your next keypress or click. While you're sworn and unflagged
-- outside an instance, your action bar keys are overridden by a secure button
-- whose macro is "/pvp" followed by "/click <the button that key presses>",
-- and transparent secure buttons sit over the bar buttons for mouse clicks.
-- Either way the use flags you and still triggers the ability. They're lifted
-- after one use, as soon as you're flagged, and just before combat (/pvp
-- toggles: a use while already flagged would unflag you).

local BAR_BINDINGS = {
    {"ACTIONBUTTON", "ActionButton"},
    {"MULTIACTIONBAR1BUTTON", "MultiBarBottomLeftButton"},
    {"MULTIACTIONBAR2BUTTON", "MultiBarBottomRightButton"},
    {"MULTIACTIONBAR3BUTTON", "MultiBarRightButton"},
    {"MULTIACTIONBAR4BUTTON", "MultiBarLeftButton"},
    {"MULTIACTIONBAR5BUTTON", "MultiBar5Button"},
    {"MULTIACTIONBAR6BUTTON", "MultiBar6Button"},
    {"MULTIACTIONBAR7BUTTON", "MultiBar7Button"},
    {"SHAPESHIFTBUTTON", "StanceButton"},
    {"BONUSACTIONBUTTON", "PetActionButton"},
    {"EXTRAACTIONBUTTON", "ExtraActionButton"},
}
-- Keys checked for bar addons (Bartender, Dominos...), which bind keys to
-- their own buttons as "CLICK <button>:<mouse button>".
-- Only keys bound to such a CLICK command are borrowed: movement and other
-- keys are never touched.
local COMMON_KEYS = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "`"}
for letter in ("QWERTYUIOPASDFGHJKLZXCVBNM"):gmatch(".") do COMMON_KEYS[#COMMON_KEYS + 1] = letter end
for i = 1, 12 do COMMON_KEYS[#COMMON_KEYS + 1] = "F" .. i end
for i = 0, 9 do COMMON_KEYS[#COMMON_KEYS + 1] = "NUMPAD" .. i end
local reflagButton, reflagArmed, reflagArmedAt, reflagNotified
local reflagPressedAt = -100

-- Away protection: while you're unflagged and doing nothing, the grace
-- countdown waits. Moving, turning, casting, combat or looting is activity;
-- chatting isn't. idle.after seconds without any of it counts as away, and
-- a new countdown starts out away: it waits for your first activity, so an
-- unflag while you're AFK (or a login unflagged) costs nothing until you're
-- back. idle.waiting: no activity yet since this countdown began.
local idle = {last = GetTime(), after = 30}
function idle.Note() idle.last, idle.waiting = GetTime(), nil end
function idle.Wait() idle.last, idle.facing, idle.waiting = -math.huge, nil, true end
function idle.Poll()
    if IsPlayerMoving and IsPlayerMoving() then idle.Note() end
    if UnitAffectingCombat and UnitAffectingCombat("player") then idle.Note() end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if type(facing) == "number" and not Secret(facing) then
        if idle.facing and math.abs(facing - idle.facing) > 0.01 then idle.Note() end
        idle.facing = facing
    end
end
function idle.Away() return GetTime() - idle.last >= idle.after end
-- You turned the flag off yourself (/pvp; the portrait menu is greyed out) rather than the
-- game doing it on a zone change: ask straight away, don't wait for a key.
idle.manual, idle.wasDesired = false, nil
local overlayHost
local overlays = {}
-- Runs after any borrowed key press or overlay click: the keys and overlays
-- go back at once (/pvp toggles, so a second use would unflag you).
local function ReflagPressed()
    Debug("Reflag key or click used.")
    reflagArmed, reflagPressedAt = false, GetTime()
    if overlayHost and not InCombatLockdown() and overlayHost:IsShown() then overlayHost:Hide() end
    if reflagButton and not InCombatLockdown() and ClearOverrideBindings then ClearOverrideBindings(reflagButton) end
end
local function CreateReflagButton()
    local button = CreateFrame("Button", "HonorBoundReflagButton", UIParent, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type", "macro")
    button:HookScript("PostClick", ReflagPressed)
    return button
end
-- Presses a button both ways. A secure action button acts on key down or on
-- key up depending on the player's settings and ignores the other, so sending
-- both lets exactly one through, whichever way it is set.
local function ClickLines(name, mouse)
    -- Stance and pet buttons act on every click, not on one half of it, so a
    -- down plus an up would fire twice (shift in and straight back out).
    if name:find("^StanceButton") or name:find("^PetActionButton") then
        return ("/click %s %s"):format(name, mouse)
    end
    return ("/click %s %s 1\n/click %s %s"):format(name, mouse, name, mouse)
end
-- The button a key presses right now. Override bindings (bar addons such as
-- Bartender take over the default keys) are checked first, so a key whose
-- Blizzard binding has been overridden presses the addon's button, not a
-- hidden Blizzard one.
local function KeyButton(key)
    if not GetBindingAction then return end
    local action = GetBindingAction(key, true)
    if type(action) ~= "string" then return end
    local name, mouse = action:match("^CLICK ([^:]+):(.+)$")
    if not name then
        for _, bar in ipairs(BAR_BINDINGS) do
            local number = action:match("^" .. bar[1] .. "(%d+)$")
            if number then name, mouse = bar[2] .. number, "LeftButton" break end
        end
    end
    if name and name ~= "HonorBoundReflagButton" and _G[name] then return name, mouse end
end
-- Each borrowed key -> the macro lines that press what the key does now, and
-- every bar button worth covering for mouse clicks -> its mouse button.
local function ReflagTargets()
    local targets, seen, buttons = {}, {}, {}
    local function consider(key)
        if not key or seen[key] then return end
        seen[key] = true
        local name, mouse = KeyButton(key)
        if name then
            targets[#targets + 1] = {key = key, line = ClickLines(name, mouse)}
            buttons[name] = buttons[name] or mouse
        end
    end
    -- Keys the Blizzard bars are bound to.
    if GetBindingKey then
        for _, bar in ipairs(BAR_BINDINGS) do
            for i = 1, 12 do
                for _, key in ipairs({GetBindingKey(bar[1] .. i)}) do consider(key) end
            end
        end
    end
    -- Keys bound to a "CLICK <button>:<mouse button>" command, whatever the
    -- key (bar addons that ship their own bindings).
    if GetNumBindings and GetBinding then
        for i = 1, GetNumBindings() do
            local binding = {n = select("#", GetBinding(i)), GetBinding(i)}
            if type(binding[1]) == "string" and binding[1]:find("^CLICK ") then
                for k = 3, binding.n do consider(binding[k]) end
            end
        end
    end
    -- Keys a bar addon may have bound at runtime.
    for _, base in ipairs(COMMON_KEYS) do
        for _, key in ipairs({base, "SHIFT-" .. base, "CTRL-" .. base, "ALT-" .. base}) do consider(key) end
    end
    -- Mouse clicks: every visible Blizzard bar button, bound to a key or not.
    for _, bar in ipairs(BAR_BINDINGS) do
        for i = 1, 12 do
            local name = bar[2] .. i
            local frame = _G[name]
            if frame and frame.IsVisible and frame:IsVisible() then buttons[name] = buttons[name] or "LeftButton" end
        end
    end
    return targets, buttons
end
-- Transparent secure buttons laid over the bar buttons, shown only while
-- armed: a mouse click on a button runs /pvp and then clicks the button
-- underneath. Hiding the host hides them all, even in combat.
local function ShowOverlays(buttons)
    if not overlayHost then
        overlayHost = CreateFrame("Frame", nil, UIParent)
        overlayHost:SetSize(1, 1)
        overlayHost:SetPoint("CENTER")
    end
    local pvp = SLASH_PVP1 or "/pvp"
    for name, mouse in pairs(buttons) do
        local overlay = overlays[name]
        if not overlay then
            overlay = CreateFrame("Button", nil, overlayHost, "SecureActionButtonTemplate")
            overlay:SetFrameStrata("HIGH")
            overlay:RegisterForClicks("AnyUp")
            overlay:SetAttribute("useOnKeyDown", false)
            overlay:SetAttribute("type", "macro")
            overlay:HookScript("PostClick", ReflagPressed)
            overlays[name] = overlay
        end
        overlay:ClearAllPoints()
        overlay:SetAllPoints(_G[name])
        overlay:SetAttribute("macrotext1", pvp .. "\n" .. ClickLines(name, mouse))
        overlay:SetAttribute("macrotext2", pvp .. "\n" .. ClickLines(name, "RightButton"))
        overlay:Show()
    end
    for name, overlay in pairs(overlays) do
        if not buttons[name] then overlay:Hide() end
    end
    overlayHost:Show()
end
-- Returns whether keys and buttons are borrowed now.
local function ArmReflag()
    if reflagArmed then return true end
    -- Just pressed: the flag may not have registered yet, and /pvp toggles.
    -- Count as armed, without keys, until it has had time to.
    if GetTime() - reflagPressedAt < 3 then return true end
    if not SetOverrideBindingClick or InCombatLockdown() or db.autoReflag == false then return false end
    reflagButton = reflagButton or CreateReflagButton()
    local targets, buttons = ReflagTargets()
    if #targets == 0 and not next(buttons) then return false end
    ClearOverrideBindings(reflagButton)
    for i, target in ipairs(targets) do
        reflagButton:SetAttribute("*macrotext-key" .. i, (SLASH_PVP1 or "/pvp") .. "\n" .. target.line)
        SetOverrideBindingClick(reflagButton, true, target.key, "HonorBoundReflagButton", "key" .. i)
    end
    ShowOverlays(buttons)
    reflagArmed = true
    reflagArmedAt = reflagArmedAt or GetTime()
    Debug(("Reflag armed on %d keys and %d bar buttons."):format(#targets, (function() local n = 0 for _ in pairs(buttons) do n = n + 1 end return n end)()))
    return true
end
local function DisarmReflag()
    -- The overlays hold secure buttons, so hiding them is blocked in combat
    -- just like changing key bindings. PLAYER_REGEN_DISABLED hides them first.
    if InCombatLockdown() then return end
    if overlayHost and overlayHost:IsShown() then overlayHost:Hide() end
    if not reflagArmed then return end
    ClearOverrideBindings(reflagButton)
    reflagArmed = false
    Debug("Reflag keys released.")
end
-- A fresh grace period: no countdown yet and nothing carried over.
function idle.ResetGrace()
    countLeft, countedAt, char.graceLeft = nil, nil, nil
end
local function Swear()
    A.StartPledge(char, UnitLevel("player"))
    char.sworn, char.joining, char.declined = true, nil, nil
    idle.ResetGrace()
    Guard()
    Print("You've sworn the oath. Your crest shows to the community while you stay flagged.")
    -- A fresh, verified record; if /played isn't known yet it starts when it is.
    char.verify = A.PlayedNow() and A.NewVerify(A.PlayedNow()) or nil
    A.MarkSave()
    Announce(true)
    Refresh()
end
local function Break(reason)
    if not char.sworn then return end
    char.pledgedSinceLevel = nil
    char.sworn, char.joining = false, nil
    idle.ResetGrace()
    -- Unsworn, nothing needs reflagging: the keys go back now (or, in
    -- combat, from UpdatePrompt once it ends).
    DisarmReflag()
    Print("Oath broken: " .. reason .. ". Your crest is gone. Type /honor swear to take it again.")
    char.verify = nil
    A.MarkSave()
    Announce(true)
    Refresh()
end

-- Verification glue (the rules are in Verify.lua). Kept as fields on A:
-- this file is near Lua's limit of 200 locals.
-- /played as the server counts it now, once we've heard it this session.
function A.PlayedNow()
    if not A.playedAt then return end
    return A.playedAt + (GetTime() - A.playedClock)
end
-- Ask the server for /played without printing it in chat (our request only;
-- typing /played still prints as normal).
function A.RequestPlayed()
    if not RequestTimePlayed then return end
    -- Hidden until our answer arrives (then for one more second), at most 30 s.
    A.hidePlayedUntil = GetTime() + 30
    for _, owner in ipairs({_G, ChatFrameUtil or {}}) do
        local name = owner == _G and "ChatFrame_DisplayTimePlayed" or "DisplayTimePlayed"
        local show = owner[name]
        if type(show) == "function" and not A.playedHooked then
            owner[name] = function(...)
                if GetTime() < (A.hidePlayedUntil or 0) then return end
                return show(...)
            end
            A.playedHooked = true
        end
    end
    A.playedAskedAt = GetTime()
    RequestTimePlayed()
end
-- No answer to our /played request: ask again (3 tries, 30 s apart), then
-- say this session couldn't be checked; the next login checks it.
function A.CheckPlayedAnswer(now)
    if A.playedAt or not A.playedAskedAt or now - A.playedAskedAt < 30 then return end
    A.playedTries = (A.playedTries or 1) + 1
    if A.playedTries <= 3 then
        Debug("No answer to the /played request yet; asking again.")
        A.RequestPlayed()
    else
        A.playedAskedAt = nil
        Debug("No answer to /played after 3 tries; this session is checked at the next login.")
    end
end
function A.OnPlayed(total)
    if type(total) ~= "number" then return end
    A.playedAt, A.playedClock = total, GetTime()
    C_Timer.After(1, function() A.hidePlayedUntil = 0 end)
    if not char.sworn then return end
    local record = char.verify
    if not record then
        -- Sworn before verification existed, or just now: it starts here.
        char.verify = A.NewVerify(total)
        A.verifyAssessed = true
        A.MarkSave()
        Debug("Verification of your pledge starts now.")
        return
    end
    if A.verifyAssessed then return end
    A.verifyAssessed = true
    local gap, over = A.AssessVerify(record, total)
    local allowed = A.VerifyAllowance(record, total)
    if over then
        Break("HonorBound missed " .. A.Duration(record.untracked) .. " of your play time, more than the "
            .. A.Duration(allowed) .. " allowed")
    elseif gap > 0 then
        A.MarkSave()
        Print("HonorBound didn't see " .. A.Duration(gap) .. " of your play time since your last session"
            .. " (addon off, another computer, or a crash). Untracked so far: " .. A.Duration(record.untracked)
            .. " of " .. A.Duration(allowed) .. " allowed.")
    else
        Debug("Verification: no untracked play since your last session.")
    end
end
-- Keep the record's "seen" up to date while we're running.
function A.TrackPlayed()
    local now = A.PlayedNow()
    if now and char.sworn and char.verify then char.verify.seen = math.max(char.verify.seen, now) end
end

-- The save macro (Save.lua). Every change (swear, break, a counted gap) and
-- every SAVE_EVERY seconds while sworn bumps this computer's write counter
-- and writes the macro, after combat if need be. At login the higher counter
-- wins: the macro's (another computer played since) or this computer's (a
-- change here never reached the macro).
A.SAVE_EVERY = 120 -- at most 2 min lost to a crash, which the 2 min gap rule ignores
function A.MarkSave()
    char.saveSeq = (char.saveSeq or 0) + 1
    A.saveDirty, A.savedAt = true, GetTime()
end
function A.LocalSave()
    if char.sworn == nil then return end
    local level = char.sworn and A.PledgeLevel(char) or 0
    if char.sworn and level == 0 then return end -- no level to save yet
    local v = char.sworn and char.verify
    return {level = level, since = v and v.since or 0, seen = v and v.seen or 0,
        untracked = v and v.untracked or 0, n = char.saveSeq or 0}
end
function A.FlushSave()
    if not A.saveDirty or not myGUID then return end
    local record = A.LocalSave()
    if not record then A.saveDirty = nil return end
    local ok, why = A.WriteSave(myGUID, record)
    if ok then
        A.saveDirty = nil
        Debug(SENT .. " your pledge (" .. (record.level > 0 and ("since level " .. record.level) or "not sworn")
            .. ", save #" .. record.n .. ") to the " .. A.SAVE_NAME .. " macro.", true)
    elseif why == "full" then
        A.saveDirty = nil
        if record.level > 0 then A.ShowMacrosFull() end
    elseif why ~= "combat" then
        A.saveDirty = nil
        if not A.saveWarned then
            A.saveWarned = true
            Print("Couldn't save your pledge to a macro on this client; it stays on this computer only.")
        end
    end
end
-- No free character macro slot: a dialog like the pledge prompt asks for
-- one to be cleared. Shown once a session unless Retry finds them still full.
function A.ShowMacrosFull()
    local f = A.macrosFull
    if not f then
        f = CreateFrame("Frame", "HonorBoundMacrosFull", UIParent, "BackdropTemplate")
        f:SetSize(380, 196)
        f:SetPoint("CENTER", 0, 180)
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f.header = f:CreateTexture(nil, "ARTWORK")
        f.header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
        f.header:SetSize(300, 64)
        f.header:SetPoint("TOP", 0, 12)
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", f.header, "TOP", 0, -14)
        f.title:SetText("HonorBound")
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(72, 72)
        f.icon:SetPoint("TOPLEFT", 20, -34)
        f.heading = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        f.heading:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -6)
        f.heading:SetWidth(258)
        f.heading:SetJustifyH("LEFT")
        f.heading:SetText("Your character macros are full")
        f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", f.heading, "BOTTOMLEFT", 0, -8)
        f.text:SetWidth(258)
        f.text:SetJustifyH("LEFT")
        f.text:SetText("HonorBound saves your pledge in a character macro so it follows you to other computers."
            .. " Delete one character macro, then click Retry.")
        local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        open:SetSize(110, 26)
        open:SetPoint("BOTTOMLEFT", 22, 18)
        open:SetText("Open macros")
        open:SetScript("OnClick", function()
            if ShowMacroFrame then ShowMacroFrame() else Print("Type /macro to open your macros.") end
        end)
        local retry = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        retry:SetSize(90, 26)
        retry:SetPoint("LEFT", open, "RIGHT", 6, 0)
        retry:SetText("Retry")
        retry:SetScript("OnClick", function()
            f:Hide()
            A.MarkSave()
            A.FlushSave()
            if not A.saveDirty and not f:IsShown() then Print("Your pledge is saved in the " .. A.SAVE_NAME .. " macro.") end
        end)
        f.retry = retry
        local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        later:SetSize(90, 26)
        later:SetPoint("BOTTOMRIGHT", -22, 18)
        later:SetText("Not now")
        later:SetScript("OnClick", function()
            f:Hide()
            Print("Your pledge stays on this computer only until a character macro slot is free. /honor save tries again.")
        end)
        A.macrosFull = f
    end
    f.icon:SetTexture(MEDIA .. "Crest" .. Faction("player") .. ".tga")
    f:Show()
end
-- At login, once macros are loaded: settle the record, then ask for /played
-- (assessing before this could compare against an out-of-date copy).
function A.SyncSave()
    if not myGUID or A.saveSynced then return end
    A.saveSynced = true
    local saved, why = A.ReadSave(myGUID)
    local mine = char.saveSeq or 0
    if saved and saved.n > mine then
        -- Newer than this computer's copy: another computer played since.
        char.saveSeq = saved.n
        if saved.level == 0 then
            if char.sworn then
                idle.ResetGrace()
                DisarmReflag()
                Print("Your " .. A.SAVE_NAME .. " macro says your oath was broken on another computer, so it's broken here too.")
            end
            char.sworn, char.pledgedSinceLevel, char.joining, char.verify = false, nil, nil, nil
        else
            local before = char.sworn and char.pledgedSinceLevel
            char.sworn, char.pledgedSinceLevel, char.joining, char.declined = true, saved.level, nil, nil
            -- since = seen = 0: sworn before /played was known; verification
            -- starts at the next /played.
            char.verify = (saved.since > 0 or saved.seen > 0)
                and {since = saved.since, seen = saved.seen, untracked = saved.untracked} or nil
            if before ~= saved.level then
                Print("Restored your oath from the " .. A.SAVE_NAME .. " macro: pledged since level " .. saved.level .. ".")
            end
        end
        UpdatePrompt()
        Announce(true)
        Refresh()
    else
        if why == "altered" then
            Print("The " .. A.SAVE_NAME .. " macro was edited, so it was ignored"
                .. (char.sworn ~= nil and " and rewritten from this computer." or "."))
        end
        -- Missing, edited, older or the same: this computer's copy stands.
        if char.sworn ~= nil and (not saved or mine > saved.n) then A.MarkSave() end
    end
    A.RequestPlayed()
end

---------------------------------------------------------------------------
-- The prompt: a secure button runs the real /pvp from your click.

local function CreatePrompt()
    local f = CreateFrame("Frame", "HonorBoundPrompt", UIParent, "BackdropTemplate")
    f:SetSize(380, 196)
    f:SetPoint("CENTER", 0, 180)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) if not InCombatLockdown() then self:StopMovingOrSizing() end end)
    f:Hide()

    f.header = f:CreateTexture(nil, "ARTWORK")
    f.header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    f.header:SetSize(300, 64)
    f.header:SetPoint("TOP", 0, 12)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", f.header, "TOP", 0, -14)
    f.title:SetText("HonorBound")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(72, 72)
    f.icon:SetPoint("TOPLEFT", 20, -34)
    f.oath = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.oath:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -6)
    f.oath:SetWidth(258)
    f.oath:SetJustifyH("LEFT")
    f.oath:SetText("\"I fight under the open sky.\"")
    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", f.oath, "BOTTOMLEFT", 0, -8)
    f.text:SetWidth(258)
    f.text:SetJustifyH("LEFT")

    local flag = CreateFrame("Button", "HonorBoundFlagButton", f, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    flag:SetSize(160, 26)
    flag:SetPoint("BOTTOMLEFT", 22, 18)
    flag:RegisterForClicks("LeftButtonUp")
    -- Without this, "cast on key down" players get no action from a mouse-up click.
    flag:SetAttribute("useOnKeyDown", false)
    flag:SetAttribute("type", "macro")
    flag:SetAttribute("macrotext", SLASH_PVP1 or "/pvp")
    flag:HookScript("PreClick", function()
        if char and not char.sworn then char.joining = true end
    end)
    -- /pvp toggles, so a second click would unflag again. Disarm after one.
    flag:HookScript("PostClick", function(self)
        if not InCombatLockdown() then
            self:SetAttribute("type", nil)
            self.disarmedAt = GetTime()
        end
    end)
    f.flag = flag

    -- Already flagged: swearing needs no secure action.
    local swear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    swear:SetSize(160, 26)
    swear:SetPoint("BOTTOMLEFT", 22, 18)
    swear:SetText("Swear the oath")
    swear:SetScript("OnClick", function() Swear() UpdatePrompt() end)
    swear:Hide()
    f.swear = swear

    local no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    no:SetSize(130, 26)
    no:SetPoint("BOTTOMRIGHT", -22, 18)
    no:SetText("Not now")
    no:SetScript("OnClick", function()
        if char and not char.sworn then
            char.declined, char.joining = true, nil
            Print("Not now. Type /honor swear whenever you're ready.")
            UpdatePrompt()
        end
    end)
    f.no = no

    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 0.25 then return end
        self.elapsed = 0
        UpdatePrompt()
    end)
    return f
end
-- Frames holding a secure button can't be shown or hidden in combat.
local function SetFlagButton(show)
    if prompt.flag:IsShown() == show or InCombatLockdown() then return end
    prompt.flag:SetShown(show)
end
local function SetPromptShown(show)
    if prompt:IsShown() == show then return end
    if InCombatLockdown() then
        promptAfterCombat = true
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if show then prompt.flag:SetAttribute("type", "macro") end
    prompt:SetShown(show)
end
-- Decides whether the prompt is up and what it says, and enforces the
-- grace countdown. Runs every second and on flag changes.
UpdatePrompt = function()
    if not char or not prompt then return end
    prompt.icon:SetTexture(MEDIA .. "Crest" .. Faction("player") .. ".tga")
    local desired = Desired()
    if idle.wasDesired and not desired and not InPausedInstance() then idle.manual = true end
    idle.wasDesired = desired
    if desired then
        idle.manual = false
        idle.ResetGrace()
        reflagArmedAt, reflagNotified = nil, nil
        DisarmReflag()
        if char.sworn then
            Guard()
            SetPromptShown(false)
        elseif char.joining then
            Swear()
            SetPromptShown(false)
        elseif char.sworn == nil and not char.declined then
            prompt.text:SetText("Swear to RP-PvP on this character? You'll stay flagged for good, and the community will see your crest.")
            SetFlagButton(false)
            prompt.swear:Show()
            prompt.no:Show()
            SetPromptShown(true)
        else
            SetPromptShown(false)
        end
        return
    end
    prompt.swear:Hide()

    local welcome = char.sworn == nil and not char.declined
    if not char.sworn and not welcome and not char.joining then
        DisarmReflag()
        SetPromptShown(false)
        return
    end
    if char.sworn and InPausedInstance() then
        -- You can't reflag inside; the countdown starts fresh outside. A flag
        -- that dropped during the loading screen wasn't you.
        idle.ResetGrace()
        reflagArmedAt, idle.manual = nil, false
        DisarmReflag()
        SetPromptShown(false)
        return
    end
    local left
    if char.sworn then
        -- Our own countdown, even while the game's PvP timer runs after a
        -- typed /pvp: only ours pauses while you're away.
        -- Logged in unflagged: grace left from an earlier session carries over.
        -- Counted, not timed: each check takes off the time since the last
        -- one, at most 2 s, and only the part before you went away. Time
        -- with no checks at all (a loading screen, a frozen client) costs
        -- nothing, so it can't break the oath on the next check.
        local now = GetTime()
        if not countLeft then
            countLeft, countedAt = char.graceLeft or A.GRACE, now
            idle.Wait()
        end
        idle.Poll()
        local step = math.min(now - countedAt, 2)
        countLeft = countLeft - math.max(0, math.min(step, idle.last + idle.after - countedAt))
        countedAt = now
        left = countLeft
        if left <= 0 then Break("you stayed unflagged too long") DisarmReflag() SetPromptShown(false) return end
        -- Try the borrowed keys first; the popup follows if they go unused.
        if ArmReflag() then
            if not reflagNotified then
                reflagNotified = true
                Print("You're unflagged. Your next action bar key or click will flag you again.")
            end
            if not idle.manual and GetTime() - reflagArmedAt < db.popupDelay then
                SetPromptShown(false)
                return
            end
        end
    end
    if char.sworn then
        prompt.text:SetText("You're unflagged. "
            .. (reflagArmed and "Press an action bar key, click a bar button, or click below" or "Click below")
            .. " within " .. FormatTime(left) .. ", or your oath breaks and your crest goes."
            .. (idle.waiting and " (The countdown starts when you move.)"
                or idle.Away() and " (Paused while you're away.)" or ""))
        prompt.flag:SetText("Stay flagged")
        SetFlagButton(true)
    else
        prompt.text:SetText("Swear to RP-PvP on this character? You'll flag for PvP now and stay flagged for good, and the community will see your crest.")
        prompt.flag:SetText("Flag and swear")
        SetFlagButton(true)
    end
    -- Re-arm the button if a click didn't take.
    local button = prompt.flag
    if button.disarmedAt and GetTime() - button.disarmedAt > 2 and not InCombatLockdown() then
        button.disarmedAt = nil
        button:SetAttribute("type", "macro")
    end
    prompt.no:SetShown(not char.sworn)
    SetPromptShown(true)
end

---------------------------------------------------------------------------
-- Badges on the player, target and focus frames

local function TooltipLines(tooltip, unit)
    tooltip:AddLine(("|T%sCrest%s.tga:18:18|t HonorBound"):format(MEDIA, Faction(unit)), 1, 0.83, 0.4)
    local guid = GUID(unit)
    local level
    if guid == myGUID then
        level = A.PledgeLevel(char)
    else
        level = A.PeerPledgeLevel(Status(unit), GetTime())
        -- A claim older than the level they are now can't be true.
        local now = UnitLevel(unit)
        if level and type(now) == "number" and not Secret(now) and now > 0 and level > now then level = nil end
    end
    if level then
        tooltip:AddLine("PvP pledged since level " .. level, 0.85, 0.85, 0.85)
    else
        tooltip:AddLine("Sworn to RP-PvP. Always flagged.", 0.85, 0.85, 0.85)
    end
end
local function BadgeTooltip(widget)
    if not widget.unit or not Status(widget.unit) then return end
    GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
    TooltipLines(GameTooltip, widget.unit)
    GameTooltip:Show()
end
local function NewWidget(host, unit)
    local badge = CreateFrame("Frame", nil, host)
    badge.unit, badge.host = unit, host
    badge:SetSize(30, 30)
    badge:SetFrameLevel(host:GetFrameLevel() + 15)
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", BadgeTooltip)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    badge.crest = badge:CreateTexture(nil, "ARTWORK")
    badge.crest:SetAllPoints()
    badge.fade = badge:CreateAnimationGroup()
    local fade = badge.fade:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.35)
    badge:Hide()
    widgets[#widgets + 1] = badge
    return badge
end
local function Portrait(host, unit)
    if host.portrait then return host.portrait end
    if host.Portrait then return host.Portrait end
    if unit == "player" then
        return _G.PlayerPortrait or (host.PlayerFrameContainer and host.PlayerFrameContainer.PlayerPortrait)
    end
    local content = host.TargetFrameContainer
    return (content and content.Portrait) or _G[(host:GetName() or "") .. "Portrait"]
end
local function PvpIcon(host, unit)
    local ok, elements
    if unit == "player" and PlayerFrame_GetPvPIndicatorElements then
        ok, elements = pcall(PlayerFrame_GetPvPIndicatorElements)
    elseif host.GetPvPIndicatorElements then
        ok, elements = pcall(host.GetPvPIndicatorElements, host)
    end
    if ok and elements and elements.pvpIcon then return elements.pvpIcon end
    if host.pvpIcon then return host.pvpIcon end
    if host.PartyMemberOverlay and host.PartyMemberOverlay.PVPIcon then return host.PartyMemberOverlay.PVPIcon end
    if unit == "player" then return _G.PlayerPVPIcon end
    return _G[(host:GetName() or "") .. "TextureFramePVPIcon"]
end
-- The crest stands in for the PvP icon. Atlas icons are cropped to the
-- glyph; the classic 64px file has the glyph in its top-left corner.
local function Attach(widget)
    local icon = PvpIcon(widget.host, widget.unit)
    local portrait = Portrait(widget.host, widget.unit)
    widget.icon = icon
    widget:ClearAllPoints()
    if icon then
        local ok, atlas = pcall(icon.GetAtlas, icon)
        if ok and atlas then
            widget:SetPoint("CENTER", icon, "CENTER", db.offsetX, db.offsetY)
        else
            local size = icon:GetWidth() * 0.31
            widget:SetPoint("CENTER", icon, "TOPLEFT", size + db.offsetX, -size + db.offsetY)
        end
    elseif portrait then
        widget:SetPoint("BOTTOM", portrait, "TOP", db.offsetX, db.offsetY)
    else
        widget:SetPoint("TOPLEFT", widget.host, "TOPLEFT", db.offsetX + 12, db.offsetY + 12)
    end
    -- Party portraits are smaller than the player and target ones.
    widget:SetScale(db.scale * (widget.party and 0.75 or 1))
end
local function DiscoverFrames()
    for _, entry in ipairs({ {"PlayerFrame", "player"}, {"TargetFrame", "target"}, {"FocusFrame", "focus"} }) do
        local host = _G[entry[1]]
        if host and not host.HonorBoundWidget then
            host.HonorBoundWidget = NewWidget(host, entry[2])
        end
    end
    -- Blizzard's party frames (not the raid-style ones), made when the
    -- party first shows. Each follows whichever unit its frame shows now.
    local party = _G.PartyFrame
    for i = 1, 4 do
        local host = party and party["MemberFrame" .. i]
        if host and not host.HonorBoundWidget then
            host.HonorBoundWidget = NewWidget(host, "party" .. i)
            host.HonorBoundWidget.party = true
        end
    end
end
-- The unit a widget's frame shows right now, or nil if it isn't in use.
local function WidgetUnit(widget)
    if not widget.party then return widget.unit end
    local host = widget.host
    local unit = host.GetUnit and host:GetUnit() or host.unit
    if type(unit) == "string" and not Secret(unit) and host:IsShown() then return unit end
end
-- Nameplates: a small crest to the left of the name. Plates are recycled,
-- so the crest lives on the plate and is re-checked for each new unit.
local function PlateCrest(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local host = plate.UnitFrame or plate
    if not host.HonorBoundCrest then
        host.HonorBoundCrest = host:CreateTexture(nil, "OVERLAY")
        host.HonorBoundCrest:SetSize(16, 16)
    end
    local crest, name = host.HonorBoundCrest, host.name
    crest:ClearAllPoints()
    if name and name:IsShown() then
        -- The name string is centred in a wider box: sit beside the text itself.
        local width = name:GetStringWidth() or 0
        if Secret(width) then width = 0 end
        crest:SetPoint("RIGHT", name, "CENTER", -width / 2 - 2, 0)
    else
        crest:SetPoint("BOTTOM", host, "TOP", 0, 2)
    end
    return crest
end
-- Something failed to refresh: tell developers (debug mode, once a minute
-- per kind) with the game's error; everything else keeps updating.
local errorAt = {}
local function ReportError(what, err)
    if GetTime() - (errorAt[what] or -100) >= 60 then
        errorAt[what] = GetTime()
        Debug("Couldn't update " .. what .. " (" .. tostring(err) .. "). Everything else still updates.")
    end
end
local function PlateError(unit, err) ReportError("a nameplate crest", err) end
-- /honor why: for the target (or mouseover), every condition behind their
-- nameplate crest, to find out why one is missing. Read only.
local PLATE_ADDONS = {"Plater", "TidyPlates_ThreatPlates", "TidyPlates", "BetterBlizzPlates", "Kui_Nameplates", "NeatPlates"}
local function WhyNoCrest(say)
    local unit = GUID("target") and "target" or "mouseover"
    local guid = GUID(unit)
    if not guid or not UnitIsPlayer(unit) then say("Target a player (or hover one) first.") return end
    local yes = function(v) return v and "yes" or "|cffff5555no|r" end
    local now = GetTime()
    local peer = peers[guid]
    local fresh = peer and now - peer.seen < A.TTL
    say("Checking " .. Who(guid) .. ":")
    if fresh then
        say("  Known addon user: yes (" .. (peer.simulated and "simulated" or "heard " .. math.floor(now - peer.seen) .. " s ago")
            .. "), sworn: " .. yes(peer.sworn) .. ".")
    elseif likely[guid] then
        say("  Known addon user: remembered only (saved status " .. (likely[guid].sworn and "sworn" or "not sworn")
            .. ", " .. (likely[guid].misses or 0) .. " unanswered re-checks).")
    else
        local state = pending[guid] and "being asked now" or RuledOut(guid) and "no answer, marked as not having the addon"
            or probes[guid] and "waiting to be asked" or Simulated(guid) and "simulated, not asked yet" or "not asked yet"
        say("  Known addon user: |cffff5555no|r (" .. state .. ").")
    end
    local theirs, ours = UnitFactionGroup(unit), UnitFactionGroup("player")
    say("  Same faction (can be whispered): " .. yes(not Secret(theirs) and theirs == ours)
        .. ". PvP-flagged right now: " .. yes(Flagged(unit)) .. (InPausedInstance() and " (inside: not needed)" or "") .. ".")
    local wearing = Status(unit) ~= nil
    local overlay = not wearing and OverlayState(unit)
    say("  Should wear a crest: " .. yes(wearing) .. ". Nameplate crests: " .. yes(db.plates) .. "."
        .. (overlay and (" Debug crest expected: " .. (overlay == "asked" and "light grey (being asked)" or "dark grey (no addon)") .. ".") or ""))
    local plateUnit
    for u in pairs(plates) do if GUID(u) == guid then plateUnit = u end end
    if not plateUnit then say("  Nameplate: none on screen for them.") return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(plateUnit)
    if not plate then say("  Nameplate: the game didn't hand it over.") return end
    if plate.IsForbidden and plate:IsForbidden() then say("  Nameplate: locked by the game here (forbidden), crests can't be added.") return end
    local host = plate.UnitFrame or plate
    local crest = host.HonorBoundCrest
    say("  Blizzard nameplate frame visible: " .. yes(host:IsVisible()) .. ". Crest made: " .. yes(crest ~= nil)
        .. ", showing: " .. yes(crest and crest:IsShown()) .. ", actually visible: " .. yes(crest and crest:IsVisible()) .. ".")
    local loaded = {}
    for _, name in ipairs(PLATE_ADDONS) do
        if (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)) or (IsAddOnLoaded and IsAddOnLoaded(name)) then
            loaded[#loaded + 1] = name
        end
    end
    if #loaded > 0 then
        say("  Nameplate addons loaded: " .. table.concat(loaded, ", ")
            .. (host:IsVisible() and "." or ". They're hiding Blizzard's nameplate, which carries the crest."))
    end
end
RefreshPlate = function(unit)
    local crest = PlateCrest(unit)
    if not crest then return end
    local wearing = Status(unit) ~= nil
    local state = not wearing and OverlayState(unit)
    if db.plates and (wearing or state) then
        crest:SetTexture(MEDIA .. "Crest" .. Faction(unit) .. ".tga")
        CrestLook(crest, state or nil)
        crest:Show()
    else
        crest:Hide()
    end
end
-- One unit frame's crest (player, target, focus, party).
local function RefreshWidget(widget)
    widget.unit = WidgetUnit(widget)
    Attach(widget)
    local wearing = widget.unit ~= nil and Status(widget.unit) ~= nil
    local state = not wearing and OverlayState(widget.unit)
    if wearing or state then
        widget.crest:SetTexture(MEDIA .. "Crest" .. Faction(widget.unit) .. ".tga")
        CrestLook(widget.crest, state or nil)
        if not widget:IsShown() then widget.fade:Play() end
        widget:Show()
    else
        widget:Hide()
    end
    -- Blizzard shows and hides the icon itself; alpha is ours to set.
    if widget.icon then widget.icon:SetAlpha(wearing and 0 or 1) end
end
Refresh = function()
    if not db then return end
    DiscoverFrames()
    -- Each frame on its own: one failing must never skip the nameplates.
    for _, widget in ipairs(widgets) do
        local ok, err = pcall(RefreshWidget, widget)
        if not ok then ReportError("a unit frame crest", err) end
    end
    -- Take the nameplates from the game each pass rather than trusting that
    -- every "added" event arrived (loading screens, reloads), and refresh
    -- each one on its own so one failure can't skip the rest.
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if type(unit) == "string" and not Secret(unit) and not plates[unit] then
                plates[unit] = true
                Debug("Picked up a nameplate the game didn't announce (" .. unit .. ").", true)
            end
        end
    end
    for unit in pairs(plates) do
        local ok, err = pcall(RefreshPlate, unit)
        if not ok then PlateError(unit, err) end
    end
end

---------------------------------------------------------------------------
-- Events

local function OnMessage(prefix, message, route, sender)
    if prefix ~= A.PREFIX or Secret(message) or type(message) ~= "string" or #message > 255 then return end
    if route == "WHISPER" then return OnWhisper(message, sender) end
    if route ~= "GUILD" and route ~= "PARTY" and route ~= "RAID" and route ~= "INSTANCE_CHAT" then return end
    local requested = message:match("^Q|1|(.+)$")
    if requested then
        if requested == myGUID and GetTime() - lastAnswer >= 5 then
            lastAnswer = GetTime()
            Debug("Someone on " .. (ROUTES[route] or route) .. " asked whether you have the addon: announcing your status.", true)
            Announce(true)
        end
        return
    end
    local insider, inside = A.DecodeInside(message)
    if insider then
        -- Only a group member's word counts: they're the ones we can't see.
        if insider ~= myGUID and (route == "PARTY" or route == "RAID" or route == "INSTANCE_CHAT") then
            Debug(HEARD .. " " .. Describe(message) .. " via " .. (ROUTES[route] or route) .. ".", true)
            groupInside.at[insider] = inside and GetTime() or nil
            ChatChanged(insider)
            Refresh()
        end
        return
    end
    local guid, peer = A.DecodePledge(message)
    local isPledge = guid ~= nil
    if not guid then guid, peer = A.Decode(message) end
    if guid and guid ~= myGUID then
        if debugEnabled then
            -- The status line every minute; the pledge-level companion only in verbose.
            Debug(HEARD .. " " .. Describe(message) .. " via " .. (ROUTES[route] or route) .. ".", isPledge)
        end
        -- Hearing from someone always overrides an earlier "no addon".
        noAddon[guid] = nil
        TimeResult("answer", guid)
        peers[guid] = A.MergePledgePeer(peers[guid], peer, GetTime(), isPledge)
        -- Remember sworn players we hear from directly (group, guild, realm
        -- channel) too, so their crest is back the moment we see them after a
        -- relog. A remembered player's saved status follows what they say, so
        -- a renounced oath can't come back from it either.
        local saved = likely[guid]
        if not saved and peer.sworn then
            local name = GuidName(guid) or (type(sender) == "string" and not Secret(sender) and Address(sender))
            if ValidName(name) then saved = {name = name} likely[guid] = saved end
        end
        if saved then
            saved.sworn, saved.seen, saved.misses = peer.sworn or nil, time(), nil
            if isPledge then saved.level = peer.pledgedSinceLevel end
        end
        ChatChanged(guid)
        Refresh()
    end
end
local function OnTooltip(tooltip)
    if tooltip ~= GameTooltip or not db then return end
    local _, unit = tooltip:GetUnit()
    if Secret(unit) or not unit then return end
    if Status(unit) then TooltipLines(tooltip, unit) end
end
local function TickWork(now)
    if A.announceAfterPause and not SendingBlocked() then A.announceAfterPause = nil Announce(true) end
    A.TrackPlayed()
    A.CheckPlayedAnswer(now)
    if A.saveSynced and char.sworn and char.verify and now - (A.savedAt or 0) >= A.SAVE_EVERY then A.MarkSave() end
    if A.saveDirty then A.FlushSave() end
    for guid, peer in pairs(peers) do
        if now - peer.seen >= A.TTL then peers[guid] = nil end
    end
    for guid, at in pairs(groupInside.at) do
        if now - at >= groupInside.fresh then groupInside.at[guid] = nil end
    end
    PumpProbes()
    ReportRefused(now)
    if now - lastMinute >= (simPercent and 15 or 60) then
        lastMinute = now
        PruneCaches()
        DebugSummary()
    end
    if char.sworn and not Desired() then UpdatePrompt() end
    if lastPayload ~= A.Encode(myGUID or "", Sworn()) or lastPledgePayload ~= PledgePayload() or not lastAnnounce or now - lastAnnounce >= 60 then
        Announce(true)
    end
end
-- Once a second. The redraw runs even if the work before it fails.
local function Tick()
    local ok, err = pcall(TickWork, GetTime())
    if not ok then ReportError("discovery", err) end
    Refresh()
end
local function PrintStatus()
    if char.sworn then
        local level = A.PledgeLevel(char)
        Print("You're sworn" .. (level and (" since level " .. level) or "") .. ". Flag: "
            .. (Desired() and "on" or "|cffff4444off|r") .. ".")
        local record, played = char.verify, A.PlayedNow()
        if record and played then
            Print("|cff55ff55Verified|r: HonorBound has missed "
                .. A.Duration(record.untracked) .. " of your play since the pledge (" .. A.Duration(A.VerifyAllowance(record, played)) .. " allowed).")
        else
            Print("Verification: waiting for your play time from the server.")
        end
    else
        Print("You haven't sworn on this character. Type /honor swear.")
    end
    local count = 0
    for _, peer in pairs(peers) do if peer.sworn then count = count + 1 end end
    Print(Count(count, "sworn player") .. " seen recently.")
    Print("Crests in chat: " .. (not A.chatAvailable and "not supported on this client" or db.chatIcons == false and "off" or "on")
        .. ". Reflag on your next action bar key: " .. (db.autoReflag == false and "off" or "on") .. ". /honor help for commands.")
end

SLASH_HONORBOUND1 = "/honor"
SLASH_HONORBOUND2 = "/honorbound"
SlashCmdList.HONORBOUND = function(input)
    if not db then return end
    local debugCommand = (input or ""):lower():match("^%s*debug%s*(.-)%s*$")
    if debugCommand ~= nil then
        if debugCommand == "on" then debugEnabled, debugVerbose = true, false
        elseif debugCommand == "verbose" then debugEnabled, debugVerbose = true, true
        elseif debugCommand == "off" then debugEnabled, debugVerbose = false, false
        elseif debugCommand == "" then debugEnabled, debugVerbose = not debugEnabled, false
        else Print("Use /honor debug on, /honor debug verbose or /honor debug off.") return end
        if not debugEnabled then
            Print("Debug off.")
        else
            Print(debugVerbose and "Debug verbose until you reload or log out: every message sent and received, plus a summary."
                or "Debug on until you reload or log out: status updates, failures and a summary. /honor debug verbose shows every whisper.")
            Debug("Whispers: " .. (whisperCap and ("at most " .. whisperCap .. " a second") or "unpaced") .. " (paced inside dungeons and raids)"
                .. ". Group: " .. (GroupRoute() and ROUTES[GroupRoute()]:gsub("^your ", "") or "none")
                .. ". Guild: " .. (IsInGuild() and "yes" or "no")
                .. ". Last status sent: " .. (lastAnnounce and (math.floor(GetTime() - lastAnnounce) .. " s ago") or "not yet")
                .. ". Waiting to be asked: " .. probeCount .. ". Replies to send: " .. #replies .. ".")
            Debug("Chat crests: " .. (not A.chatAvailable and "unavailable on this client (the chat name hook is missing)"
                or db.chatIcons == false and "off (/honor chat on)" or "on")
                .. (IsAddOnLoaded and IsAddOnLoaded("Prat-3.0") and ". Prat is loaded and may hide them." or "."))
            Debug("\"Sent\" means the game accepted it, not that anyone received it.")
        end
        return
    end
    if (input or ""):lower():match("^%s*save%s*$") then
        if char.sworn == nil then Print("Nothing to save: you haven't sworn on this character.") return end
        A.MarkSave()
        A.FlushSave()
        if not A.saveDirty and not (A.macrosFull and A.macrosFull:IsShown()) then
            Print("Your pledge is saved in the " .. A.SAVE_NAME .. " macro.")
        elseif A.saveDirty then
            Print("You're in combat; your pledge will be saved when it ends.")
        end
        return
    end
    local rateCommand = (input or ""):lower():match("^%s*rate%s*(.-)%s*$")
    if rateCommand ~= nil then
        local value = tonumber(rateCommand)
        if rateCommand == "off" or rateCommand == "0" then whisperCap = nil
        elseif value and value >= 1 and value == math.floor(value) then whisperCap = value
        elseif rateCommand ~= "" then Print("Use /honor rate N (whispers a second) or /honor rate off.") return end
        Print("Whispers: " .. (whisperCap and ("at most " .. whisperCap .. " a second") or "unpaced") .. " outside dungeons and raids.")
        return
    end
    local simCommand = (input or ""):lower():match("^%s*sim%s*(.-)%s*$")
    if simCommand ~= nil then
        if simCommand == "off" then
            simPercent = nil
            for guid, peer in pairs(peers) do
                if peer.simulated then peers[guid] = nil ChatChanged(guid) end
            end
            debugEnabled, debugVerbose = false, false
            Print("Simulation off, and debug with it. Simulated badges removed; everything learned for real is kept.")
        elseif simCommand ~= "" then
            local value = tonumber(simCommand:match("^(%d+)%%?$") or "")
            if not value or value > 100 then Print("Use /honor sim 0-100 or /honor sim off.") return end
            simPercent, debugEnabled = value, true
            seenAt, probeTimed = {}, {}
            timings = {probe = {0, 0}, answer = {0, 0}, none = {0, 0}}
            Print(("Simulation on: %d%% of the players you ask answer as addon users. Probes, rate limits, timeouts and the no-addon list are real. Debug on."):format(value))
        elseif not simPercent then
            Print("Simulation off. /honor sim 10 makes 10% of the players you ask answer as addon users.")
        end
        if simPercent then Print(Coverage()) end
        Refresh()
        return
    end
    if (input or ""):lower():match("^%s*chatcheck%s*$") then
        A.ChatCheck(Print)
        return
    end
    if (input or ""):lower():match("^%s*why%s*$") then
        WhyNoCrest(Print)
        return
    end
    local chatCommand = (input or ""):lower():match("^%s*chat%s*(.-)%s*$")
    if chatCommand ~= nil then
        if chatCommand == "on" then db.chatIcons = true
        elseif chatCommand == "off" then db.chatIcons = false
        elseif chatCommand ~= "" then Print("Use /honor chat on or /honor chat off.") return end
        Print(not A.chatAvailable and "Crests in chat aren't supported on this client."
            or (db.chatIcons == false and "Crests in chat off." or "Crests in chat on."))
        return
    end
    if not db then return end
    local command, arg = input:lower():match("^(%S*)%s*(.-)%s*$")
    if command == "swear" or command == "join" then
        if char.sworn then
            Print("You're already sworn.")
        elseif Desired() then
            Swear()
        else
            char.declined, char.joining = nil, true
        end
        UpdatePrompt()
    elseif command == "renounce" then
        if arg ~= "confirm" then
            Print("This breaks your oath and removes your crest. Type /honor renounce confirm to proceed.")
        else
            Break("you renounced it")
            char.declined = true
        end
    elseif command == "autoflag" then
        if arg == "on" then db.autoReflag = true
        elseif arg == "off" then db.autoReflag = false DisarmReflag() end
        Print("Reflag on your next action bar key: " .. (db.autoReflag == false and "off" or "on")
            .. ". /honor autoflag on|off")
        UpdatePrompt()
    elseif command == "plates" then
        db.plates = not db.plates
        Print("Nameplate crests " .. (db.plates and "on" or "off") .. ".")
    elseif command == "scale" then
        local value = tonumber(arg)
        if not value or value < 0.6 or value > 2 then Print("Use /honor scale 0.6–2") return end
        db.scale = value
        Print("Crest size set to " .. value .. ".")
    elseif command == "offset" then
        local x, y = arg:match("^(%-?%d+)%s+(%-?%d+)$")
        x, y = tonumber(x), tonumber(y)
        if not x or not y or math.abs(x) > 200 or math.abs(y) > 200 then Print("Use /honor offset X Y (−200 to 200)") return end
        db.offsetX, db.offsetY = x, y
        Print(("Crest moved to %d, %d from the PvP icon."):format(x, y))
    elseif command == "options" or command == "settings" or command == "config" then
        if A.optionsCategory and Settings.OpenToCategory then
            Settings.OpenToCategory(A.optionsCategory:GetID())
        else
            Print("There's no settings page on this client; the commands in /honor help still work.")
        end
    elseif command == "delay" then
        local value = tonumber(arg)
        if not value or value < A.POPUP_MIN or value > A.POPUP_MAX then
            Print(("Use /honor delay %d-%d (seconds before the popup after a dungeon)."):format(A.POPUP_MIN, A.POPUP_MAX))
            return
        end
        db.popupDelay = math.floor(value + 0.5)
        Print("After a dungeon, the popup waits " .. A.Seconds(db.popupDelay) .. ".")
    elseif command == "reset" then
        db.scale, db.offsetX, db.offsetY, db.plates = 1, 0, 0, true
        Print("Crest size and position reset, and nameplate crests turned on.")
    elseif command == "" or command == "status" then
        PrintStatus()
    else
        -- One command per line. Developer commands are in /honor devhelp.
        local dev = command == "devhelp"
        local list = dev and {
            {"debug on", "Developer messages in chat until you reload."},
            {"debug verbose", "Also every whisper sent and received."},
            {"debug off", "Turn developer messages off."},
            {"sim 10", "Pretend 10% of players you ask have the addon (0-100)."},
            {"sim off", "Stop simulating; remove simulated crests."},
            {"rate 5", "Cap whispers at 5 a second (rate off: no cap)."},
            {"why", "Explain your target's nameplate crest."},
            {"chatcheck", "Check how this client stores chat lines."},
        } or {
            {"", "Your oath, flag and verification."},
            {"swear", "Take the oath."},
            {"renounce", "Give up the oath (asks to confirm)."},
            {"options", "Open the settings page."},
            {"save", "Save your pledge to its macro again."},
            {"autoflag on|off", "Reflag on your next action bar key."},
            {"plates", "Show or hide crests on nameplates."},
            {"chat on|off", "Show or hide crests in chat."},
            {"scale 0.6-2", "Crest size."},
            {"offset X Y", "Move the crest."},
            {"delay 10-120", "Seconds before the popup after a dungeon."},
            {"reset", "Reset crest size and position."},
        }
        Print(dev and "Developer commands:" or "Commands:")
        for _, entry in ipairs(list) do
            -- Gold command, grey dash, light grey description.
            DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/honor" .. (entry[1] ~= "" and (" " .. entry[1]) or "")
                .. "|r |cff808080-|r |cffc8c8c8" .. entry[2] .. "|r")
        end
    end
    Refresh()
end

-- Built while the game loads: secure buttons can't be set up in combat,
-- and a /reload can land you in combat before PLAYER_LOGIN.
prompt = CreatePrompt()

for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_FACTION", "PLAYER_FLAGS_CHANGED", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT", "TIME_PLAYED_MSG", "UPDATE_MACROS",
    "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_LEAVING_WORLD"}) do
    eventFrame:RegisterEvent(event)
end
-- Speakers we might not know yet. Group and guild chat are covered by
-- their own routes, so only open chat feeds the probe queue.
local probeChat = {CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true,
    CHAT_MSG_CHANNEL = true, CHAT_MSG_WHISPER = true}
for event in pairs(probeChat) do eventFrame:RegisterEvent(event) end
-- Combat is polled (PLAYER_REGEN_DISABLED has its own handler below).
idle.events = {PLAYER_STARTED_MOVING = true, UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_SUCCEEDED = true,
    LOOT_OPENED = true}
for event in pairs(idle.events) do eventFrame:RegisterEvent(event) end
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        HonorBoundDB = type(HonorBoundDB) == "table" and HonorBoundDB or {}
        db = HonorBoundDB
        db.scale = math.min(2, math.max(0.6, tonumber(db.scale) or 1))
        db.offsetX = math.min(200, math.max(-200, tonumber(db.offsetX) or 0))
        db.offsetY = math.min(200, math.max(-200, tonumber(db.offsetY) or 0))
        db.ring = nil
        if db.plates == nil then db.plates = true end
        db.popupDelay = math.min(A.POPUP_MAX, math.max(A.POPUP_MIN, math.floor(tonumber(db.popupDelay) or A.POPUP_DEFAULT)))
        HonorBoundCharDB = type(HonorBoundCharDB) == "table" and HonorBoundCharDB or {}
        char = HonorBoundCharDB
        -- Existing oaths start their history now; never invent an earlier level.
        A.EnsurePledge(char, UnitLevel("player"))
        myGUID = GUID("player")
        myServer = Server(myGUID)
        LoadCaches()
        local addFilter = ChatFrame_AddMessageEventFilter
            or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
        if addFilter then addFilter("CHAT_MSG_SYSTEM", HideUnreachable) end
        A.chatAvailable = A.InstallChat(function() return db.chatIcons ~= false end, function(guid)
            if guid == myGUID then return Sworn() end
            local peer = peers[guid]
            if peer and GetTime() - peer.seen < A.TTL then return peer.sworn end
            return Cached(guid)
        end, ChatFaction, function(guid)
            -- Grey crests in chat only while debugging or simulating.
            if debugEnabled or simPercent then return DebugState(guid) end
        end)
        C_ChatInfo.RegisterAddonMessagePrefix(A.PREFIX)
        if TooltipDataProcessor and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltip)
        elseif GameTooltip:HasScript("OnTooltipSetUnit") then
            GameTooltip:HookScript("OnTooltipSetUnit", OnTooltip)
        end
        -- The settings page is a convenience: if the game's Settings API ever
        -- differs from what we expect, lose the page, not the addon.
        local built, category = pcall(A.InstallOptions, db, function(key)
            if key == "autoflag" then
                if db.autoReflag == false then DisarmReflag() end
                UpdatePrompt()
            end
            Refresh()
        end)
        A.optionsCategory = built and category or nil
        if not built then
            Print("Couldn't build the settings page. The /honor commands still work.")
            Debug("Settings page error: " .. tostring(category))
        end
        C_Timer.NewTicker(1, Tick)
        -- Read the save once the game says macros are loaded (UPDATE_MACROS),
        -- or after 10 s if that already happened; /played is asked for then.
        C_Timer.After(10, A.SyncSave)
        UpdatePrompt()
        Refresh()
        if char.sworn then
            Print("Sworn to RP-PvP. /honor for status.")
        elseif char.sworn == false or char.declined then
            Print("Not sworn on this character. Type /honor swear to earn your crest.")
        end
    elseif not db then
        return
    elseif event == "PLAYER_LOGOUT" then
        if char.sworn and countLeft then char.graceLeft = math.max(0, countLeft) end
        A.TrackPlayed()
        if A.saveSynced and char.sworn ~= nil then A.MarkSave() A.FlushSave() end
    elseif event == "TIME_PLAYED_MSG" then
        A.OnPlayed(...)
    elseif event == "UPDATE_MACROS" then
        A.SyncSave()
    elseif event == "LOADING_SCREEN_ENABLED" or event == "PLAYER_LEAVING_WORLD" then
        -- Zoning: hold everything (at most a minute, in case the end is missed).
        A.zonePauseUntil = GetTime() + 60
    elseif event == "LOADING_SCREEN_DISABLED" then
        A.zonePauseUntil = GetTime() + A.ZONE_SETTLE
    elseif idle.events[event] then
        local unit = ...
        if not event:find("^UNIT_") or unit == "player" then idle.Note() end
    elseif event == "CHAT_MSG_ADDON" then
        OnMessage(...)
    elseif probeChat[event] then
        local sender, guid = select(2, ...), select(12, ...)
        if Secret(guid) or not A.ValidGUID(guid) then return end
        -- Chat gives "First Surname" (a space, no realm), which bounces as a
        -- whisper address; the whisper form is "First-Surname".
        Query(guid, PRIORITY_CHAT, Address(FullName(sender)))
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        QueryUnit("mouseover", PRIORITY_UNIT)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        if Secret(unit) or not unit then return end
        plates[unit] = true
        RefreshPlate(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        if Secret(unit) or not unit then return end
        local crest = PlateCrest(unit)
        if crest then crest:Hide() end
        plates[unit] = nil
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Fires just before combat lockdown, the last moment bindings can change.
        DisarmReflag()
    elseif event == "PLAYER_REGEN_ENABLED" then
        promptAfterCombat = nil
        UpdatePrompt()
    elseif event == "ADDON_LOADED" then
        if GreyOutDisable() then self:UnregisterEvent("ADDON_LOADED") end
    else
        if event == "PLAYER_ENTERING_WORLD" then A.zonePauseUntil = GetTime() + A.ZONE_SETTLE end
        if event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FACTION" or event == "PLAYER_ENTERING_WORLD" then UpdatePrompt() end
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_FLAGS_CHANGED" then Announce(true) end
        Refresh()
    end
end)
