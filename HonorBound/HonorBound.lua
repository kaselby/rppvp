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
local peers, queries, widgets, plates = {}, {}, {}, {}
local lastQuery, lastAnswer, lastJoin, lastMinute = -100, -100, -100, 0
local guarded, deadline, prompt, promptAfterCombat
local REFLAG_POPUP_DELAY = 30    -- seconds the borrowed keys get before the popup shows too
local Refresh, Announce, UpdatePrompt, RefreshPlate

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd479HonorBound:|r " .. text)
end
-- Session-only diagnostics: no extra network traffic or saved logs.
-- "on" shows broadcasts, channel shares and a summary a minute; "verbose"
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
local function Sworn()
    return char and char.sworn and Desired()
end
local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Sharing status over the hidden channel and group addon messages.

local function ChannelID()
    local id = GetChannelName(A.CHANNEL)
    if type(id) == "number" and id > 0 then return id end
end
-- One budget for every send. Announcements always go out but still spend;
-- queries and whisper probes wait until there's room. Sustained use stays
-- at half the server's roughly one-message-a-second allowance per prefix.
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
local function Send(message, route, target)
    Refill()
    tokens = math.max(-TOKEN_MAX, tokens - 1)
    local result = C_ChatInfo.SendAddonMessage(A.PREFIX, message, route, target)
    -- The server pushed back: stop optional traffic for a few seconds.
    if not (result == true or result == 0) then tokens = math.min(tokens, -2) end
    if debugEnabled then
        local ok = result == true or result == 0
        local where = route == "WHISPER" and ("a whisper to " .. tostring(target)) or ROUTES[route] or route
        -- Failures always show; every successful send only in verbose.
        if ok then
            Debug(SENT .. " " .. Describe(message) .. " via " .. where .. ".", true)
        else
            Debug(FAILED .. " " .. Describe(message) .. " via " .. where .. ": " .. Reason(result) .. ".")
        end
    end
    return result == true or result == 0
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
    -- Include metadata changes in the existing announcement throttle.
    local unchanged = payload == lastPayload and pledgePayload == lastPledgePayload
    -- Keep repeated world/group events from flooding the channel,
    -- but let a changed oath through straight away.
    if unchanged and lastAnnounce and now - lastAnnounce < 3 then return end
    if not force and unchanged and lastAnnounce and now - lastAnnounce < 60 then return end
    -- Nothing got through last time: wait before trying again, rather than
    -- hammering a busy channel every second.
    if now < announceRetryAt then return end
    local reached = {}
    local function To(route, target)
        if Send(payload, route, target) and Send(pledgePayload, route, target) then
            reached[#reached + 1] = ROUTES[route]
        end
    end
    local channel = ChannelID()
    if channel then To("CHANNEL", tostring(channel)) end
    if GroupRoute() then To(GroupRoute()) end
    if IsInGuild() then To("GUILD") end
    local mine = StatusWords(Sworn(), Sworn() and A.PledgeLevel(char))
    if #reached > 0 then
        lastAnnounce, lastPayload, lastPledgePayload = now, payload, pledgePayload
        Debug(SENT .. " your status (" .. mine .. ") to " .. table.concat(reached, ", ") .. ".")
    elseif channel or GroupRoute() or IsInGuild() then
        -- Sends were refused: back off. With nowhere to send yet, nothing is
        -- sent either, so keep checking every second.
        announceRetryAt = now + 10
        Debug("Couldn't announce your status (" .. mine .. "). Trying again in 10 s.")
    end
end
local function JoinChannel()
    if not db or GetTime() - lastJoin < 30 then return end
    lastJoin = GetTime()
    if ChannelID() then Announce(true) return end
    local join = JoinTemporaryChannel or JoinPermanentChannel
    if join then join(A.CHANNEL) end
    C_Timer.After(2, function()
        if ChatFrame_RemoveChannel then
            for i = 1, NUM_CHAT_WINDOWS or 10 do
                local frame = _G["ChatFrame" .. i]
                if frame then ChatFrame_RemoveChannel(frame, A.CHANNEL) end
            end
        end
        Announce(true)
    end)
end
---------------------------------------------------------------------------
-- Whisper probes: players from other realms can't hear our hidden channel,
-- so ask the ones we actually meet (mouseover, nameplate, chat) directly.
-- A probe carries our own status, so the other side learns us from it and
-- never needs to probe back. One reply completes the exchange.
--
-- Realm sharing: whatever one of us learns about another realm's players is
-- posted once on our own realm's channel, so nobody else here has to ask.
-- Finds ("F") go out after a short random wait unless someone beat us to it;
-- players without the addon ("N") go out in small batches, and the more
-- of us there are, the less often each one posts.

local PROBE_TIMEOUT = 30         -- no reply by then: treat as no addon
local PROBE_STALE = 30           -- queued this long without sending: drop
local NO_ADDON = 7200            -- our own silent probe: don't ask for 2 hours
local NO_ADDON_SHARED = 1800     -- someone else's: 30 minutes
local LIKELY_KEEP = 14 * 86400   -- remember addon users for two weeks
-- Refresh peers still in view well before they expire: REPROBE_AFTER plus up
-- to REPROBE_JITTER spreads a realm out, and the rest leaves room for the queue.
local REPROBE_AFTER, REPROBE_JITTER = A.TTL - 90, 45
local QUEUE_MAX, REPLY_MAX, REPLY_GAP = 40, 20, 60
local SHARE_WAIT, SHARE_STALE, SHARE_REFRESH = {2, 10}, 60, 150
local NO_BATCH, NO_GAP, NO_MAX = 15, {20, 40}, 60
-- Lower sends first: known addon users, mouseover/target, chat, nameplates.
local PRIORITY_LIKELY, PRIORITY_UNIT, PRIORITY_CHAT, PRIORITY_PLATE = 0, 1, 2, 3
local probes, probeCount, pending, replies, replied = {}, 0, {}, {}, {}
local noAddon, likely = {}, {}  -- saved; keyed by GUID, times from time()
local names, jitter, heard, shares = {}, {}, {}, {}
local unsharedNo, nextNoPost, sharingPausedUntil = {}, 0, 0
-- Same-realm players asked on the channel and not yet heard from.
local ASK_TIMEOUT = 10
local asking = {}
local stats = {asked = 0, askedSilent = 0, probed = 0, answered = 0, silent = 0, unreachable = 0,
    sharedF = 0, sharedN = 0, heardF = 0, heardN = 0}

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
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
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
-- A simulated user answering our probe or question. Only resolves if we're
-- still waiting: a real reply, an unreachable error or a timeout wins.
local function SimAnswer(guid, name)
    if not simPercent or not (pending[guid] or asking[guid]) then return end
    pending[guid], asking[guid] = nil, nil
    local now = GetTime()
    stats.answered = stats.answered + 1
    peers[guid] = {sworn = true, version = "sim", simulated = true, seen = now}
    Debug(HEARD .. " a simulated answer from " .. (name or Who(guid)) .. ".", true)
    TimeResult("answer", guid)
    ChatChanged(guid)
    -- Tell other testers on our realm (FS: ignored by everyone not simulating).
    if OtherRealm(guid) and ValidName(name) and not shares[guid] then
        shares[guid] = {due = now + Between(SHARE_WAIT), peer = peers[guid],
            payload = ("FS|1|%s|%s|1|0|sim"):format(guid, name)}
    end
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
    -- Spread re-probes so a whole realm doesn't refresh the same player at once.
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
    if probeCount >= QUEUE_MAX then
        -- Full: a more urgent probe displaces the least urgent, oldest one.
        local worst, worstEntry
        for queued, e in pairs(probes) do
            if not worstEntry or e.priority > worstEntry.priority
                or (e.priority == worstEntry.priority and e.at < worstEntry.at) then
                worst, worstEntry = queued, e
            end
        end
        if worstEntry.priority <= priority then return end
        probes[worst], probeCount = nil, probeCount - 1
    end
    probes[guid], probeCount = {priority = priority, at = now, name = name}, probeCount + 1
end
local function Unqueue(guid)
    if probes[guid] then probes[guid], probeCount = nil, probeCount - 1 end
end
-- Same-realm players hear the channel: ask there. Anyone else gets a probe.
local function Query(guid, priority, name)
    if not guid or not myGUID or guid == myGUID then return end
    if OtherRealm(guid) then return Probe(guid, priority or PRIORITY_PLATE, name) end
    -- Ask each same-realm stranger once; silence puts them on the list.
    if asking[guid] or RuledOut(guid) then return end
    local now = GetTime()
    if peers[guid] and now - peers[guid].seen < 60 then return end
    Seen(guid)
    if now - lastQuery < 1 then return end
    if queries[guid] and now - queries[guid] < 15 then return end
    local id, route = ChannelID(), GroupRoute()
    local cost = (id and 1 or 0) + (route and 1 or 0) + (IsInGuild() and 1 or 0)
    if cost == 0 or not Afford(cost) then return end
    local message = "Q|1|" .. guid
    local sent = false
    if id then sent = Send(message, "CHANNEL", tostring(id)) or sent end
    if route then sent = Send(message, route) or sent end
    if IsInGuild() then sent = Send(message, "GUILD") or sent end
    if sent then
        queries[guid], lastQuery, asking[guid] = now, now, now
        stats.asked = stats.asked + 1
        ChatChanged(guid)
        SimProbe(guid)
    end
end
local function QueryUnit(unit, priority)
    local guid = GUID(unit)
    if not guid or guid == myGUID or not UnitIsPlayer(unit) then return end
    if OtherRealm(guid) then
        -- Whispers can't cross factions; skip anyone we couldn't reach anyway.
        local theirs, ours = UnitFactionGroup(unit), UnitFactionGroup("player")
        if Secret(theirs) or Secret(ours) or theirs ~= ours then return end
    end
    Query(guid, priority, FullName(UnitName(unit)))
end

-- A player from another realm confirmed by us: tell our realm, unless the
-- news is already out.
local function ShareFound(guid, name, peer)
    if not OtherRealm(guid) or not ValidName(name) then return end
    local record = heard[guid]
    if SameStatus(record, peer) and GetTime() - record.at < SHARE_REFRESH then return end
    if shares[guid] then return end
    shares[guid] = {due = GetTime() + Between(SHARE_WAIT), payload = FoundPayload(guid, name, peer), peer = peer}
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
    if OtherRealm(guid) and #unsharedNo < NO_MAX then
        -- Start a batch: collect for a while before posting.
        if #unsharedNo == 0 then nextNoPost = math.max(nextNoPost, GetTime() + Between(NO_GAP)) end
        unsharedNo[#unsharedNo + 1] = guid
    end
    stats[why] = stats[why] + 1
    TimeResult("none", guid)
    ChatChanged(guid)
end

-- At most one whisper a second, and only while the shared budget allows.
-- Replies go first: someone is waiting on them.
local function PumpWhispers(now)
    for guid, p in pairs(pending) do
        if now - p.at > PROBE_TIMEOUT then
            pending[guid] = nil
            MarkNoAddon(guid, "silent")
            Debug("No answer from " .. p.name .. " after " .. PROBE_TIMEOUT .. " s: marked as not having the addon for 2 hours.", true)
        end
    end
    while replies[1] and now - replies[1].at > PROBE_STALE do table.remove(replies, 1) end
    if not Afford(1) then return end
    local reply = table.remove(replies, 1)
    if reply then
        replied[reply.name] = now
        Send(WhisperPayload("R"), "WHISPER", reply.name)
        return
    end
    -- Most urgent first; ties broken at random so players on the same realm
    -- spread out over a crowd instead of all asking the same stranger.
    local best, bestEntry, ties = nil, nil, 0
    for guid, e in pairs(probes) do
        if now - e.at > PROBE_STALE then
            probes[guid], probeCount = nil, probeCount - 1
        elseif not bestEntry or e.priority < bestEntry.priority then
            best, bestEntry, ties = guid, e, 1
        elseif e.priority == bestEntry.priority then
            ties = ties + 1
            if math.random(ties) == 1 then best, bestEntry = guid, e end
        end
    end
    if not best then return end
    Unqueue(best)
    local name = bestEntry.name or GuidName(best)
    if not name then return end -- not resolvable yet; the next sighting re-queues
    pending[best] = {at = now, name = name}
    stats.probed = stats.probed + 1
    Send(WhisperPayload("Q"), "WHISPER", name)
    ChatChanged(best)
    SimProbe(best, name)
end
-- Channel posts are optional: they wait for spare budget and back off when
-- the server pushes back.
local function PumpShares(now)
    local id = ChannelID()
    if not id or now < sharingPausedUntil then return end
    for guid, s in pairs(shares) do
        if now - s.due > SHARE_STALE then shares[guid] = nil end
    end
    if not Afford(2) then return end
    for guid, s in pairs(shares) do
        if now >= s.due then
            shares[guid] = nil
            heard[guid] = {at = now, sworn = s.peer.sworn, level = s.peer.pledgedSinceLevel or 0}
            if Send(s.payload, "CHANNEL", tostring(id)) then
                stats.sharedF = stats.sharedF + 1
                Debug(SENT .. " to your realm: " .. Describe(s.payload):gsub("^a ", "") .. ".")
            else
                sharingPausedUntil = now + 120
                Debug("Sharing paused for 2 minutes while the channel is busy.")
            end
            return
        end
    end
    if #unsharedNo == 0 or now < nextNoPost then return end
    local batch = {}
    while #batch < NO_BATCH and unsharedNo[1] do
        batch[#batch + 1] = table.remove(unsharedNo, 1):sub(8) -- drop "Player-"
    end
    nextNoPost = now + Between(NO_GAP)
    if Send("N|1|" .. table.concat(batch, ","), "CHANNEL", tostring(id)) then
        stats.sharedN = stats.sharedN + 1
        Debug(SENT .. " to your realm: " .. Count(#batch, "player") .. " without the addon.")
    else
        sharingPausedUntil = now + 120
        Debug("Sharing paused for 2 minutes while the channel is busy.")
    end
end
local function PumpProbes()
    local now = GetTime()
    for guid, at in pairs(asking) do
        if now - at > ASK_TIMEOUT then
            asking[guid] = nil
            MarkNoAddon(guid, "askedSilent")
            Debug(Who(guid) .. " (your realm) didn't answer within " .. ASK_TIMEOUT .. " s: marked as not having the addon.", true)
        end
    end
    if Locked() or not myGUID then return end
    PumpWhispers(now)
    PumpShares(now)
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
    ShareFound(guid, name, peer)
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
-- Shared on our channel by someone on our realm.
local function OnShare(message)
    local guid, name, sworn, raw, version = message:match("^F|1|([^|]+)|([^|]+)|([01])|(%d+)|([%w%.%-?]+)$")
    name = Address(name)
    if guid then
        local peer = A.ValidGUID(guid) and guid ~= myGUID and ValidName(name) and DecodeStatus(sworn, raw, version)
        if not peer then return true end
        local now = GetTime()
        stats.heardF = stats.heardF + 1
        Debug(HEARD .. " from your realm: " .. name .. " has the addon (" .. StatusWords(peer.sworn, peer.pledgedSinceLevel) .. ").")
        heard[guid] = {at = now, sworn = peer.sworn, level = peer.pledgedSinceLevel or 0}
        -- Someone beat us to it: drop our own copy if it says the same thing.
        if shares[guid] and SameStatus(heard[guid], shares[guid].peer) then shares[guid] = nil end
        -- A direct answer outranks a relay.
        local current = peers[guid]
        if not (current and not current.relayed and now - current.seen < A.TTL) then
            peer.relayed = true
            peers[guid] = A.MergePledgePeer(current, peer, now, true)
        end
        names[guid], noAddon[guid] = name, nil
        likely[guid] = {name = name, seen = time(), sworn = peer.sworn or nil,
            level = peer.pledgedSinceLevel}
        Unqueue(guid)
        ChatChanged(guid)
        Refresh()
        return true
    end
    local list = message:match("^N|1|([%x%-,]+)$")
    if not list then return end
    stats.heardN = stats.heardN + 1
    local _, commas = list:gsub(",", "")
    Debug(HEARD .. " from your realm: " .. Count(commas + 1, "player") .. " without the addon.")
    local expires = time() + NO_ADDON_SHARED
    local now = GetTime()
    local seen = {}
    for id in list:gmatch("[^,]+") do
        local guid = "Player-" .. id
        if A.ValidGUID(guid) then
            seen[guid] = true
            local peer = peers[guid]
            -- Never let a relay hide a player we know has the addon, or one
            -- we're simulating (a tester on a lower percentage would).
            if not likely[guid] and not (peer and now - peer.seen < A.TTL) and not Simulated(guid) then
                noAddon[guid] = math.max(noAddon[guid] or 0, expires)
                Unqueue(guid)
                ChatChanged(guid)
            end
        end
    end
    -- Already said by someone else: no need for us to say it again.
    for i = #unsharedNo, 1, -1 do
        if seen[unsharedNo[i]] then table.remove(unsharedNo, i) end
    end
    nextNoPost = math.max(nextNoPost, now + Between(NO_GAP))
    return true
end
-- Another tester's simulated find. Only taken when our own hash agrees, so
-- mismatched settings never push fakes onto our screen.
local function OnSimShare(message)
    local guid, name = message:match("^FS|1|([^|]+)|([^|]+)|1|0|sim$")
    if not guid or guid == myGUID or not A.ValidGUID(guid) or not Simulated(guid) then return end
    local now = GetTime()
    heard[guid] = {at = now, sworn = true, level = 0}
    shares[guid] = nil
    local current = peers[guid]
    Debug(HEARD .. " from another tester: " .. name .. " (simulated).")
    if not (current and now - current.seen < A.TTL) then
        peers[guid] = {sworn = true, version = "sim", simulated = true, relayed = true, seen = now}
        TimeResult("answer", guid)
    end
    if ValidName(name) then names[guid] = name end
    Unqueue(guid)
    ChatChanged(guid)
    Refresh()
end

-- A probe to someone unreachable comes back as a system error; hide it.
local function HideUnreachable(_, _, message)
    if Secret(message) or type(message) ~= "string" or not ERR_CHAT_PLAYER_NOT_FOUND_S then return end
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
    for guid, record in pairs(heard) do
        if clock - record.at > A.TTL then heard[guid] = nil end
    end
    for guid, at in pairs(seenAt) do
        if at and clock - at > 3600 then seenAt[guid], probeTimed[guid] = nil, nil end
    end
end
-- Debug overlay states for players without a real crest.
local function DebugState(guid)
    if not guid or guid == myGUID then return end
    if pending[guid] or asking[guid] then return "asked" end
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
    if stats.asked + stats.probed + stats.sharedF + stats.sharedN + stats.heardF + stats.heardN == 0 then return end
    local parts = {}
    local function add(count, text, ...)
        if count > 0 then parts[#parts + 1] = text:format(Count(count, ...)) end
    end
    add(stats.asked, "asked %s on your realm" .. (stats.askedSilent > 0 and (" (" .. stats.askedSilent .. " silent)") or ""), "player")
    add(stats.probed, "probed %s on other realms", "player")
    add(stats.answered, "got %s", "answer")
    add(stats.silent, "%s went unanswered", "probe")
    add(stats.unreachable, "%s couldn't be whispered", "player")
    add(stats.sharedF, "shared %s", "find")
    add(stats.sharedN, "shared %s", "no-addon list")
    add(stats.heardF, "heard %s from your realm", "find")
    add(stats.heardN, "heard %s", "no-addon list")
    add(probeCount, "%s still waiting in line", "player")
    Debug("Since the last summary: " .. table.concat(parts, ", ") .. ".")
    for key in pairs(stats) do stats[key] = 0 end
end
-- Whether a unit wears the badge right now.
local function Status(unit)
    local guid = GUID(unit)
    if not guid then return end
    if guid == myGUID then
        if char and char.sworn and Flagged("player") then return { version = A.VERSION } end
        return
    end
    if UnitIsPlayer(unit) then
        QueryUnit(unit, unit:find("^nameplate") and PRIORITY_PLATE or PRIORITY_UNIT)
    end
    local peer = peers[guid]
    if peer and GetTime() - peer.seen < A.TTL then
        -- Simulated users stand in for "wears a badge", flagged or not.
        if peer.sworn and (peer.simulated or Flagged(unit)) then return peer end
        return
    end
    -- Nothing fresh: their saved status, while the re-check is out.
    if Cached(guid) and Flagged(unit) then
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
    if not (debugEnabled or simPercent) then return end
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
-- chatting isn't. idle.after seconds without any of it counts as away.
local idle = {last = GetTime(), after = 30}
function idle.Note() idle.last = GetTime() end
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
local function InPausedInstance()
    if not IsInInstance then return false end
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid" or kind == "scenario") or false
end
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
local function Swear()
    A.StartPledge(char, UnitLevel("player"))
    char.sworn, char.joining, char.declined, char.graceLeft = true, nil, nil, nil
    deadline = nil
    Guard()
    Print("You've sworn the oath. Your crest shows to the community while you stay flagged.")
    Announce(true)
    Refresh()
end
local function Break(reason)
    if not char.sworn then return end
    char.pledgedSinceLevel = nil
    char.sworn, char.joining, char.graceLeft = false, nil, nil
    deadline = nil
    Print("Oath broken (" .. reason .. "). Your crest is gone. Type /honor swear to take it again.")
    Announce(true)
    Refresh()
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
-- grace deadline. Runs every second and on flag changes.
UpdatePrompt = function()
    if not char or not prompt then return end
    prompt.icon:SetTexture(MEDIA .. "Crest" .. Faction("player") .. ".tga")
    if Desired() then
        deadline, char.graceLeft = nil, nil
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
        SetPromptShown(false)
        return
    end
    if char.sworn and InPausedInstance() then
        -- You can't reflag inside; the countdown starts fresh outside.
        deadline, char.graceLeft, reflagArmedAt = nil, nil, nil
        DisarmReflag()
        SetPromptShown(false)
        return
    end
    local left
    if char.sworn then
        if IsPVPTimerRunning() then
            left = (GetPVPTimer() or 0) / 1000
            deadline = GetTime() + left
        else
            -- Logged in unflagged: grace left from an earlier session carries over.
            deadline = deadline or (GetTime() + (char.graceLeft or A.GRACE))
            idle.Poll()
            if idle.Away() then
                -- Away: hold the countdown where it was.
                idle.frozen = idle.frozen or math.max(0, deadline - GetTime())
                deadline = GetTime() + idle.frozen
            else
                idle.frozen = nil
            end
            left = deadline - GetTime()
        end
        if left <= 0 then Break("unflagged") DisarmReflag() SetPromptShown(false) return end
        -- Try the borrowed keys first; the popup follows if they go unused.
        if ArmReflag() then
            if not reflagNotified then
                reflagNotified = true
                Print("You're unflagged. Your next action bar key or click will flag you again.")
            end
            if GetTime() - reflagArmedAt < REFLAG_POPUP_DELAY then
                SetPromptShown(false)
                return
            end
        end
    end
    if char.sworn then
        prompt.text:SetText("You're unflagged. Press an action bar key, click a bar button, or click below within "
            .. FormatTime(left) .. ", or your oath breaks and your crest goes."
            .. (idle.frozen and " (Paused while you're away.)" or ""))
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
    if not Status(widget.unit) then return end
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
    widget:SetScale(db.scale)
end
local function DiscoverFrames()
    for _, entry in ipairs({ {"PlayerFrame", "player"}, {"TargetFrame", "target"}, {"FocusFrame", "focus"} }) do
        local host = _G[entry[1]]
        if host and not host.HonorBoundWidget then
            host.HonorBoundWidget = NewWidget(host, entry[2])
        end
    end
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
Refresh = function()
    if not db then return end
    DiscoverFrames()
    for _, widget in ipairs(widgets) do
        Attach(widget)
        local wearing = Status(widget.unit) ~= nil
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
    for unit in pairs(plates) do RefreshPlate(unit) end
end

---------------------------------------------------------------------------
-- Events

local function OnMessage(prefix, message, route, sender)
    if prefix ~= A.PREFIX or Secret(message) or type(message) ~= "string" or #message > 255 then return end
    if route == "WHISPER" then return OnWhisper(message, sender) end
    if route == "CHANNEL" and message:find("^FS|") then
        local me = UnitName("player")
        if simPercent and not (type(sender) == "string" and not Secret(sender) and sender:match("^[^%-]+") == me) then
            OnSimShare(message)
        end
        return
    end
    if route == "CHANNEL" and message:find("^[FN]|") then
        -- Our own posts echo back on the channel; we already know what they say.
        local me = UnitName("player")
        if type(sender) == "string" and not Secret(sender) and sender:match("^[^%-]+") == me then return end
        OnShare(message)
        return
    end
    if route ~= "GUILD" and route ~= "CHANNEL" and route ~= "PARTY" and route ~= "RAID" and route ~= "INSTANCE_CHAT" then return end
    local requested = message:match("^Q|1|(.+)$")
    if requested then
        if requested == myGUID and GetTime() - lastAnswer >= 5 then
            lastAnswer = GetTime()
            Debug("Someone on " .. (ROUTES[route] or route) .. " asked whether you have the addon: announcing your status.", true)
            Announce(true)
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
        noAddon[guid], asking[guid] = nil, nil
        TimeResult("answer", guid)
        peers[guid] = A.MergePledgePeer(peers[guid], peer, GetTime(), isPledge)
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
local function Tick()
    local now = GetTime()
    for guid, peer in pairs(peers) do
        if now - peer.seen >= A.TTL then peers[guid] = nil end
    end
    for guid, at in pairs(queries) do
        if now - at > A.TTL then queries[guid] = nil end
    end
    PumpProbes()
    if now - lastMinute >= (simPercent and 15 or 60) then
        lastMinute = now
        PruneCaches()
        DebugSummary()
    end
    if char.sworn and not Desired() then UpdatePrompt() end
    if lastPayload ~= A.Encode(myGUID or "", Sworn()) or lastPledgePayload ~= PledgePayload() or not lastAnnounce or now - lastAnnounce >= 60 then
        Announce(true)
    end
    if not ChannelID() and now - lastJoin >= 60 then JoinChannel() end
    Refresh()
end
local function PrintStatus()
    Print("Chat icons: " .. (not A.chatAvailable and "unavailable" or db.chatIcons == false and "off" or "on")
        .. ". /honor chat on|off")
    local level = A.PledgeLevel(char)
    if level then Print("PvP pledged since level " .. level .. " (honor-system record).") end
    if char.sworn then
        Print("You're sworn to RP-PvP. Flag: " .. (Desired() and "on" or "|cffff4444off|r") .. ".")
    else
        Print("You haven't sworn on this character. Type /honor swear.")
    end
    local count = 0
    for _, peer in pairs(peers) do if peer.sworn then count = count + 1 end end
    Print(count .. " sworn players heard from recently.")
    Print(ChannelID() and "Community channel connected." or "Community channel pending; group sharing is also available.")
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
                or "Debug on until you reload or log out: status, shares, failures and a summary. /honor debug verbose shows everything.")
            local channel = ChannelID()
            Debug("Realm channel: " .. (channel and ("connected (/" .. channel .. ")") or "not joined yet")
                .. ". Group: " .. (GroupRoute() and ROUTES[GroupRoute()]:gsub("^your ", "") or "none")
                .. ". Guild: " .. (IsInGuild() and "yes" or "no")
                .. ". Last status sent: " .. (lastAnnounce and (math.floor(GetTime() - lastAnnounce) .. " s ago") or "not yet")
                .. ". Waiting in line: " .. probeCount .. ". Replies to send: " .. #replies .. ".")
            Debug("Chat crests: " .. (not A.chatAvailable and "unavailable on this client (the chat name hook is missing)"
                or db.chatIcons == false and "off (/honor chat on)" or "on")
                .. (IsAddOnLoaded and IsAddOnLoaded("Prat-3.0") and ". Prat is loaded and may hide them." or "."))
            Debug("\"Sent\" means the game accepted it, not that anyone received it.")
        end
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
    local chatCommand = (input or ""):lower():match("^%s*chat%s*(.-)%s*$")
    if chatCommand ~= nil then
        if chatCommand == "on" then db.chatIcons = true
        elseif chatCommand == "off" then db.chatIcons = false
        elseif chatCommand ~= "" then Print("Use /honor chat on or /honor chat off.") return end
        Print(not A.chatAvailable and "Chat icons unavailable: this client lacks the sender-name filter API."
            or (db.chatIcons == false and "Chat icons off." or "Chat icons on (recent advertised pledge)."))
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
            Break("renounced")
            char.declined = true
        end
    elseif command == "autoflag" then
        if arg == "on" then db.autoReflag = true
        elseif arg == "off" then db.autoReflag = false DisarmReflag() end
        Print("Reflag on your next action key: " .. (db.autoReflag == false and "off" or "on")
            .. ". /honor autoflag on|off")
        UpdatePrompt()
    elseif command == "plates" then
        db.plates = not db.plates
        Print("Nameplate crests " .. (db.plates and "on" or "off") .. ".")
    elseif command == "scale" then
        local value = tonumber(arg)
        if not value or value < 0.6 or value > 2 then Print("Use /honor scale 0.6–2") return end
        db.scale = value
    elseif command == "offset" then
        local x, y = arg:match("^(%-?%d+)%s+(%-?%d+)$")
        x, y = tonumber(x), tonumber(y)
        if not x or not y or math.abs(x) > 200 or math.abs(y) > 200 then Print("Use /honor offset X Y (−200 to 200)") return end
        db.offsetX, db.offsetY = x, y
    elseif command == "reset" then
        db.scale, db.offsetX, db.offsetY, db.plates = 1, 0, 0, true
        Print("Badge placement reset.")
    elseif command == "" or command == "status" then
        PrintStatus()
    else
        Print("/honor · /honor swear · /honor renounce · /honor autoflag · /honor plates · /honor scale 1 · /honor offset 0 0 · /honor reset")
    end
    Refresh()
end

-- Built while the game loads: secure buttons can't be set up in combat,
-- and a /reload can land you in combat before PLAYER_LOGIN.
prompt = CreatePrompt()

for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_FACTION", "PLAYER_FLAGS_CHANGED", "GROUP_ROSTER_UPDATE", "CHAT_MSG_ADDON", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UPDATE_MOUSEOVER_UNIT"}) do
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
        -- Give the client's usual channels time to claim their channel numbers.
        lastJoin = GetTime() - 45
        C_ChatInfo.RegisterAddonMessagePrefix(A.PREFIX)
        if TooltipDataProcessor and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltip)
        elseif GameTooltip:HasScript("OnTooltipSetUnit") then
            GameTooltip:HookScript("OnTooltipSetUnit", OnTooltip)
        end
        C_Timer.After(15, JoinChannel)
        C_Timer.NewTicker(1, Tick)
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
        if char.sworn and deadline then char.graceLeft = math.max(0, deadline - GetTime()) end
    elseif idle.events[event] then
        local unit = ...
        if not event:find("^UNIT_") or unit == "player" then idle.Note() end
    elseif event == "CHAT_MSG_ADDON" then
        OnMessage(...)
    elseif probeChat[event] then
        local sender, guid = select(2, ...), select(12, ...)
        if Secret(guid) or not A.ValidGUID(guid) then return end
        Query(guid, PRIORITY_CHAT, FullName(sender))
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
        if event == "PLAYER_FLAGS_CHANGED" or event == "UNIT_FACTION" or event == "PLAYER_ENTERING_WORLD" then UpdatePrompt() end
        if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_FLAGS_CHANGED" then Announce(true) end
        Refresh()
    end
end)
