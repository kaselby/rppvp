-- Run from the project root: lua tests/run.lua
local A = {}
assert(loadfile("HonorBound/Core.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Pledge.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Chat.lua"))("HonorBound", A)
local assertions = 0
local function check(value, message)
    assertions = assertions + 1
    assert(value, message)
end
local me, other = "Player-70-ABC123", "Player-70-DEF456"
local guid, status = A.Decode(A.Encode(other, true))
check(guid == other and status.sworn and status.version == A.VERSION, "protocol roundtrip")
check(select(2, A.Decode(A.Encode(other, false))).sworn == false, "unsworn status roundtrip")
for _, invalid in ipairs({"", "S|1|"..other.."|0.1.0", "S|2|Player-x|1|0.2", "S|2|"..other.."|2|0.2", "S|2|"..other.."|1|", "S|2|"..other.."|1|0.2|extra", string.rep("a", 256)}) do
    check(A.Decode(invalid) == nil, "reject malformed, unbounded or v1 status")
end

local now, connected, group, combat = 0, false, false, false
local desired, timer = true, nil
local sent, tasks, tickers, frames = {}, {}, {}, {}
local units = {
    player = { guid = me, flagged = true, faction = "Horde" },
    target = { guid = other, flagged = true, faction = "Alliance" },
    nameplate1 = { guid = other, flagged = true, faction = "Alliance" },
}
-- Frame stubs: known methods record state, anything else is a no-op.
local methods = {}
local function noop() end
local function object(name)
    return setmetatable({name = name, shown = true, scripts = {}, attributes = {}, alpha = 1}, {
        __index = function(_, key)
            if methods[key] then return methods[key] end
            for _, verb in ipairs({"Set", "Register", "Enable", "Start", "Stop", "Play", "Add"}) do
                if key:sub(1, #verb) == verb then return noop end
            end
        end,
    })
end
function methods:GetName() return self.name end
function methods:GetFrameLevel() return 1 end
function methods:GetDrawLayer() return "BACKGROUND", 0 end
function methods:GetParent() return self.parent end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:GetWidth() return self.width or 64 end
function methods:GetHeight() return self.height or 64 end
function methods:SetPoint(...) self.point = {...} end
function methods:ClearAllPoints() self.point = nil end
function methods:SetScale(n) self.scale = n end
function methods:SetAlpha(n) self.alpha = n end
function methods:SetDesaturated(v) self.desaturated = v end
function methods:SetVertexColor(r, g, b) self.tint = {r, g, b} end
function methods:SetShown(value) self.shown = value and true or false end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback) self.scripts[event] = callback end
function methods:HasScript() return true end
function methods:SetAttribute(key, value) self.attributes[key] = value end
function methods:CreateTexture() return object() end
function methods:CreateFontString() return object() end
function methods:CreateAnimationGroup() return object() end
function methods:CreateAnimation() return object() end
function methods:SetTexture(path) self.texturePath = path end
function methods:SetText(text) self.text = text end
function methods:GetUnit() return "Target", "target" end
function CreateFrame(_, name, parent)
    local frame = object(name)
    frame.parent = parent
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
UIParent = object("UIParent")
PlayerFrame, TargetFrame, FocusFrame = object("PlayerFrame"), object("TargetFrame"), object("FocusFrame")
PlayerPortrait, PlayerPVPIcon = object(), object()
TargetFrame.TargetFrameContainer = { Portrait = object() }
TargetFrame.pvpIcon = object()
FocusFrame.TargetFrameContainer = { Portrait = object() }
FocusFrame.pvpIcon = object()
GameTooltip = object()
local plate = object()
plate.UnitFrame = object()
plate.UnitFrame.name = object()
function methods:GetStringWidth() return 80 end
C_NamePlate = { GetNamePlateForUnit = function(unit) return unit == "nameplate1" and plate or nil end }
UnitPopupPvpDisableButtonMixin = { IsEnabled = function() return true end }
debugLines = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) debugLines[#debugLines + 1] = text end }
SlashCmdList = { PVP = function() desired = not desired end }
local blizzardPvp = SlashCmdList.PVP
LE_PARTY_CATEGORY_INSTANCE = 2
function GetTime() return now end
function UnitLevel() return 20 end
function time() return 1000000 + now end
function UnitName(unit) return units[unit] and units[unit].name, units[unit] and units[unit].realm end
function IsInGuild() return false end
local lockdown, players, systemFilters, channelResult = false, {}, {}, nil
function UnitIsPlayer(unit) return units[unit] ~= nil end
function UnitName(unit) return units[unit] and units[unit].name, units[unit] and units[unit].realm end
function GetPlayerInfoByGUID(guid)
    local p = players[guid]
    if p then return "Warrior", "WARRIOR", "Orc", "Orc", 2, p.name, p.realm end
end
ChatFrameUtil = { AddSenderNameFilter = function(f) ChatFrameUtil.filter = f end, RemoveSenderNameFilter = function() end }
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
function ChatFrame_AddMessageEventFilter(event, filter) systemFilters[event] = filter end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitIsPVP(unit) return units[unit] and units[unit].flagged end
function UnitFactionGroup(unit) return units[unit] and units[unit].faction end
function GetPVPDesired() return desired end
function IsPVPTimerRunning() return timer ~= nil end
function GetPVPTimer() return timer end
function InCombatLockdown() return combat end
function GetChannelName() return connected and 7 or 0 end
function JoinTemporaryChannel() check(now >= 15, "do not join community channel too early"); connected = true end
function IsInGroup(category) return not category and group end
function IsInRaid() return false end
C_ChatInfo = {
    RegisterAddonMessagePrefix = noop,
    InChatMessagingLockdown = function() return lockdown end,
    SendAddonMessage = function(_, message, route, target)
        sent[#sent + 1] = {message = message, route = route, target = target}
        return (route == "CHANNEL" and channelResult) or 0
    end,
}
C_Timer = {
    After = function(delay, callback) tasks[#tasks + 1] = {at = now + delay, callback = callback} end,
    NewTicker = function(_, callback) tickers[#tickers + 1] = callback end,
}
assert(loadfile("HonorBound/HonorBound.lua"))("HonorBound", A)
local events = frames[1]
local prompt = HonorBoundPrompt
local function event(name, ...) events.scripts.OnEvent(events, name, ...) end
local function advance(seconds)
    for _ = 1, seconds do
        now = now + 1
        for i = #tasks, 1, -1 do
            if tasks[i].at <= now then local task = table.remove(tasks, i); task.callback() end
        end
        for _, callback in ipairs(tickers) do callback() end
    end
end
local function lastSent()
    for i = #sent, 1, -1 do
        if sent[i].message:sub(1, 2) == "S|" then return sent[i].message end
    end
    return ""
end
local playerBadge = function() return PlayerFrame.HonorBoundWidget end
local targetBadge = function() return TargetFrame.HonorBoundWidget end
local function peer(sworn) event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(other, sworn), "CHANNEL", "Surname-bearing Name") end

-- First login, already flagged: offered the oath, no crest yet.
event("PLAYER_LOGIN")
check(prompt.shown and prompt.swear.shown, "welcome prompt offers the oath")
check(not playerBadge().shown, "no crest before swearing")
advance(18)
check(connected and lastSent():find("|0|"), "channel connects and announces unsworn")

-- Swearing while flagged.
prompt.swear.scripts.OnClick()
check(HonorBoundCharDB.sworn and not prompt.shown, "swear from prompt")
check(playerBadge().shown and playerBadge().crest.texturePath:find("CrestHorde"), "own faction crest")
check(PlayerPVPIcon.alpha == 0, "crest replaces own PvP icon")
check(lastSent():find("|1|"), "sworn status broadcast immediately")
check(not UnitPopupPvpDisableButtonMixin.IsEnabled(), "portrait menu Disable greyed out")
check(SlashCmdList.PVP == blizzardPvp, "/pvp is left alone, so it can still flag you")

-- Peers: sworn claim plus the server's live flag.
peer(true)
check(targetBadge().shown and targetBadge().crest.texturePath:find("CrestAlliance"), "sworn flagged peer wears crest")
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local plateCrest = plate.UnitFrame.HonorBoundCrest
check(plateCrest.shown and plateCrest.texturePath:find("CrestAlliance"), "nameplate crest for sworn peer")
check(plateCrest.point[1] == "RIGHT" and plateCrest.point[2] == plate.UnitFrame.name and plateCrest.point[4] == -42, "nameplate crest sits left of the name text")
SlashCmdList.HONORBOUND("plates")
check(not plateCrest.shown, "nameplate crest toggle")
SlashCmdList.HONORBOUND("plates")
check(plateCrest.shown, "nameplate crest back on")
check(TargetFrame.pvpIcon.alpha == 0, "crest replaces target PvP icon")
units.target.flagged = false
event("PLAYER_TARGET_CHANGED")
check(not targetBadge().shown and TargetFrame.pvpIcon.alpha == 1, "unflagged peer loses crest, PvP icon restored")
units.nameplate1.flagged = false
event("PLAYER_TARGET_CHANGED")
check(not plateCrest.shown, "unflagged peer loses nameplate crest")
event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
units.nameplate1.flagged = true
event("PLAYER_TARGET_CHANGED")
check(not plateCrest.shown, "recycled plate keeps no stale crest")
units.target.flagged = true
peer(false)
check(not targetBadge().shown, "unsworn peer has no crest")
peer(true)
check(targetBadge().shown, "re-sworn peer shown again")

-- Appearance settings.
SlashCmdList.HONORBOUND("scale 1.5")
SlashCmdList.HONORBOUND("offset -10 20")
check(playerBadge().scale == 1.5 and HonorBoundDB.offsetX == -10, "placement settings")
SlashCmdList.HONORBOUND("scale 99")
check(HonorBoundDB.scale == 1.5, "reject excessive scale")
SlashCmdList.HONORBOUND("reset")
check(HonorBoundDB.plates and HonorBoundDB.ring == nil and HonorBoundDB.scale == 1 and HonorBoundDB.offsetY == 0, "reset appearance")

-- Unflagged by something else: grace, then the oath breaks.
desired, units.player.flagged = false, false
event("PLAYER_FLAGS_CHANGED", "player")
check(prompt.shown and HonorBoundCharDB.sworn, "grace warning while unflagged")
check(not playerBadge().shown, "no crest while unflagged")
event("PLAYER_LOGOUT")
check(HonorBoundCharDB.graceLeft and HonorBoundCharDB.graceLeft <= A.GRACE, "grace carries over logout")
advance(A.GRACE + 2)
check(HonorBoundCharDB.sworn == false and not prompt.shown, "oath breaks after grace")
check(lastSent():find("|0|"), "broken oath broadcast")

-- Swearing again: completes once flagged.
SlashCmdList.HONORBOUND("swear")
check(HonorBoundCharDB.joining and not HonorBoundCharDB.sworn, "swear waits for the flag")
desired, units.player.flagged = true, true
event("PLAYER_FLAGS_CHANGED", "player")
check(HonorBoundCharDB.sworn and playerBadge().shown, "oath retaken on flag")

-- Renouncing needs confirmation.
SlashCmdList.HONORBOUND("renounce")
check(HonorBoundCharDB.sworn, "renounce asks for confirmation")
SlashCmdList.HONORBOUND("renounce confirm")
check(HonorBoundCharDB.sworn == false and not playerBadge().shown, "renounce removes crest")

-- Silent peers expire.
advance(A.TTL + 1)
check(not targetBadge().shown, "expire silent peers")
peer(true)
check(targetBadge().shown, "returning peer discovered")

-- Whisper probes: players from other realms can't hear the channel.
local far, stranger, silent, spoofed = "Player-99-AAA111", "Player-99-BBB222", "Player-99-CCC333", "Player-99-DDD444"
local function whispers(to)
    local list = {}
    for _, m in ipairs(sent) do
        if m.route == "WHISPER" and (not to or m.target == to) then list[#list + 1] = m end
    end
    return list
end
local function addon(message, sender) event("CHAT_MSG_ADDON", A.PREFIX, message, "WHISPER", sender) end
local function say(sender, guid) event("CHAT_MSG_SAY", "hi", sender, "", "", sender, "", 0, 0, "", 0, 1, guid) end
advance(10)
sent = {}
units.mouseover = { guid = far, flagged = true, faction = "Horde", name = "Farguy", realm = "Other Realm" }
event("UPDATE_MOUSEOVER_UNIT")
advance(1)
local probe = whispers("Farguy-OtherRealm")[1]
check(probe and probe.message:sub(1, #me + 5) == "WQ|1|" .. me, "mouseover on another realm sends one whisper probe")
for _, m in ipairs(sent) do check(not (m.message:find(far, 1, true) and m.route ~= "WHISPER"), "no channel query for other-realm players") end
units.mouseover = { guid = "Player-99-EEE555", flagged = true, faction = "Alliance", name = "Enemy", realm = "Other Realm" }
event("UPDATE_MOUSEOVER_UNIT")
advance(3)
check(#whispers("Enemy-OtherRealm") == 0, "no probes across factions")

addon("WR|1|" .. far .. "|1|20|0.2.0", "Farguy-OtherRealm")
units.nameplate1 = { guid = far, flagged = true, faction = "Horde", name = "Farguy", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(plate.UnitFrame.HonorBoundCrest.shown, "whisper reply gives a cross-realm badge")
advance(20)
check(#whispers("Farguy-OtherRealm") == 1, "known peers are not re-probed while fresh")

sent = {}
addon("WQ|1|" .. stranger .. "|0|0|0.2.0", "Bob-OtherRealm")
advance(1)
local answer = whispers("Bob-OtherRealm")
check(#answer == 1 and answer[1].message:sub(1, #me + 5) == "WR|1|" .. me, "incoming probe gets one reply")
addon("WQ|1|" .. stranger .. "|0|0|0.2.0", "Bob-OtherRealm")
advance(3)
check(#whispers("Bob-OtherRealm") == 1, "repeat probes within a minute get no second reply")
say("Bob-OtherRealm", stranger)
advance(3)
check(#whispers("Bob-OtherRealm") == 1, "a prober is learned from its probe, never probed back")

players[spoofed] = { name = "Realguy", realm = "Other Realm" }
addon("WR|1|" .. spoofed .. "|1|20|0.2.0", "Mallory-OtherRealm")
units.nameplate1 = { guid = spoofed, flagged = true, faction = "Horde", name = "Realguy", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
advance(1)
check(not plate.UnitFrame.HonorBoundCrest.shown, "status claiming someone else's GUID is ignored")

sent = {}
say("Silent-OtherRealm", silent)
advance(2)
check(#whispers("Silent-OtherRealm") == 1, "chat speaker on another realm is probed")
check(systemFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "No player named 'Silent-OtherRealm' is currently playing.") == true, "unreachable-player error is hidden")
advance(40)
say("Silent-OtherRealm", silent)
advance(5)
check(#whispers("Silent-OtherRealm") == 1, "players without the addon are not asked again")

-- Crowd: 80 unknown speakers at once stay within the budget.
advance(30)
sent = {}
for i = 1, 80 do say(("P%d-OtherRealm"):format(i), ("Player-99-%06X"):format(4096 + i)) end
advance(60)
local crowd = #whispers()
check(crowd >= 10 and crowd <= 5 + 60 / 2, "crowd probing stays within the budget; stale probes are dropped (" .. crowd .. ")")

sent = {}
lockdown = true
say("Late-OtherRealm", "Player-99-FFF666")
advance(5)
check(#whispers() == 0, "no whispers during encounter lockdown")
lockdown = false
advance(2)
check(#whispers("Late-OtherRealm") == 1, "queued probe goes out after lockdown")

-- Realm sharing: finds and non-users go out once on our own channel.
local function channelPosts(prefix, guid)
    local list = {}
    for _, m in ipairs(sent) do
        if m.route == "CHANNEL" and m.message:sub(1, #prefix) == prefix
            and (not guid or m.message:find(guid, 1, true)) then list[#list + 1] = m end
    end
    return list
end
local function shared(message, sender) event("CHAT_MSG_ADDON", A.PREFIX, message, "CHANNEL", sender or "Someone-Here") end
advance(120)
sent = {}
local found = "Player-99-ABC001"
units.mouseover = { guid = found, flagged = true, faction = "Horde", name = "Finder", realm = "Other Realm" }
event("UPDATE_MOUSEOVER_UNIT")
advance(2)
check(#whispers("Finder-OtherRealm") == 1, "probe before sharing")
addon("WR|1|" .. found .. "|1|30|0.2.0", "Finder-OtherRealm")
advance(12)
local posts = channelPosts("F|1|", found)
check(#posts == 1 and posts[1].message == "F|1|" .. found .. "|Finder-OtherRealm|1|30|0.2.0", "confirmed find shared once on the realm channel")
check(HonorBoundDB.likely[found] and HonorBoundDB.likely[found].name == "Finder-OtherRealm", "addon users are remembered in saved variables")
advance(30)
check(#channelPosts("F|1|", found) == 1, "unchanged finds are not reposted")

-- Someone else posts first: we stay quiet.
sent = {}
local raced = "Player-99-ABC002"
addon("WQ|1|" .. raced .. "|1|12|0.2.0", "Racer-OtherRealm")
shared("F|1|" .. raced .. "|Racer-OtherRealm|1|12|0.2.0")
advance(15)
check(#channelPosts("F|1|", raced) == 0, "a find already posted by someone else is not repeated")

-- A relayed find shows the badge without a probe of our own.
sent = {}
local relayed = "Player-99-ABC003"
shared("F|1|" .. relayed .. "|Relayed-OtherRealm|1|40|0.2.0")
units.nameplate1 = { guid = relayed, flagged = true, faction = "Horde", name = "Relayed", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
advance(5)
check(plate.UnitFrame.HonorBoundCrest.shown, "relayed find wears the crest")
check(#whispers("Relayed-OtherRealm") == 0, "relayed find is not probed")
units.nameplate1.flagged = false
event("PLAYER_TARGET_CHANGED")
check(not plate.UnitFrame.HonorBoundCrest.shown, "relayed status still needs the live PvP flag")
units.nameplate1.flagged = true

-- Players without the addon are batched onto the channel.
sent = {}
for i = 1, 3 do say(("Quiet%d-OtherRealm"):format(i), ("Player-99-%06X"):format(0x900 + i)) end
advance(80)
local lists = channelPosts("N|1|")
check(#lists == 1 and lists[1].message:find("99-000901", 1, true) and lists[1].message:find("99-000903", 1, true), "silent players shared in one batch")
check(HonorBoundDB.noAddon["Player-99-000901"], "silent players remembered in saved variables")
-- Someone else's list stops our probes and our own repeat.
sent = {}
shared("N|1|99-000A01,99-000A02")
say("Listed-OtherRealm", "Player-99-000A01")
advance(5)
check(#whispers("Listed-OtherRealm") == 0, "players on a shared no-addon list are not probed")
shared("N|1|" .. found:sub(8))
check(HonorBoundDB.noAddon[found] == nil, "a shared list never hides a known addon user")
-- Our own posts come back on the channel: ignore them.
units.player.name = "Me"
local before = HonorBoundDB.noAddon["Player-99-000A09"]
shared("N|1|99-000A09", "Me-HomeRealm")
check(HonorBoundDB.noAddon["Player-99-000A09"] == before, "own channel echoes are ignored")
units.player.name = nil

-- Channel throttle: sharing pauses, whispers carry on.
sent = {}
channelResult = 8
addon("WQ|1|Player-99-ABC004|1|5|0.2.0", "Thr-OtherRealm")
advance(12)
check(#channelPosts("F|1|") == 1, "share attempted once")
addon("WQ|1|Player-99-ABC005|1|5|0.2.0", "Thr2-OtherRealm")
advance(60)
check(#channelPosts("F|1|") == 1, "sharing pauses after a channel throttle")
check(#whispers("Thr2-OtherRealm") == 1, "whisper replies continue while sharing is paused")
channelResult = nil

-- Same-realm strangers: asked once on the channel, then left alone.
sent = {}
local neighbour = "Player-70-0BB001"
units.nameplate1 = { guid = neighbour, flagged = true, faction = "Horde", name = "Neighbour" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
advance(90)
local asks = channelPosts("Q|1|", neighbour)
check(#asks == 1, "same-realm stranger asked once (" .. #asks .. ")")
check(HonorBoundDB.noAddon[neighbour], "silent same-realm stranger goes on the no-addon list")
check(#channelPosts("N|1|", neighbour:sub(8)) == 0, "same-realm silence is not shared")
check(#whispers() == 0 or #whispers("Neighbour") == 0, "same-realm strangers are never whispered")
-- Their regular announcement clears the mistake straight away.
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(neighbour, true), "CHANNEL", "Neighbour")
check(HonorBoundDB.noAddon[neighbour] == nil, "hearing a player clears their no-addon entry")
check(plate.UnitFrame.HonorBoundCrest.shown, "and their crest appears")

-- Chat names wear the same faction crest as frames and nameplates.
local function chatName(factionOf, name)
    local filter = A.CreateChatFilter(function() return true end, function() return true end, factionOf)
    local args = {}
    args[12] = other -- the sender GUID is the 12th chat event argument
    return filter("CHAT_MSG_SAY", name, unpack(args, 1, 12))
end
local horde = chatName(function() return "Horde" end, "Bob")
check(horde == "|TInterface\\AddOns\\HonorBound\\Media\\CrestHorde.tga:0:0|t Bob", "chat uses the Horde crest")
check(chatName(function() return "Alliance" end, "Bob"):find("CrestAlliance.tga", 1, true), "chat uses the Alliance crest")
check(chatName(function() return "Horde" end, horde) == nil, "chat crest is not added twice")

-- Simulation: a fixed share of probed players answers as addon users.
local function chatCrest(guid, name)
    local args = {}
    args[12] = guid
    return ChatFrameUtil.filter("CHAT_MSG_SAY", name, unpack(args, 1, 12))
end
local function probeSent(name)
    for _ = 1, 15 do
        if #whispers(name) > 0 then return true end
        advance(1)
    end
end
local crest = plate.UnitFrame.HonorBoundCrest
advance(200)
sent = {}
SlashCmdList.HONORBOUND("sim 100")
local simmed = "Player-99-5AA001"
units.nameplate1 = { guid = simmed, flagged = false, faction = "Horde", name = "Simmy", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(probeSent("Simmy-OtherRealm"), "simulation still sends the real probe")
check(crest.shown and crest.desaturated and crest.alpha == 1 and crest.tint[2] == 1, "light grey crest while the probe is waiting")
advance(4)
check(crest.shown and not crest.desaturated and crest.alpha == 1 and crest.tint[2] == 1, "simulated user gets a standard crest within 3 s")
units.target = { guid = simmed, flagged = false, faction = "Horde", name = "Simmy", realm = "Other Realm" }
event("PLAYER_TARGET_CHANGED")
check(targetBadge().shown, "simulated user's crest shows on the target frame without a PvP flag")
local simChat = chatCrest(simmed, "Simmy")
check(simChat and simChat:find("CrestHorde.tga", 1, true), "simulated user's crest shows in chat")
check(HonorBoundDB.likely[simmed] == nil, "simulated users are never saved")
advance(12)
check(#channelPosts("FS|1|", simmed) == 1 and #channelPosts("F|1|", simmed) == 0, "simulated finds go out as tester-only FS, never F")
check(A.SimHash(simmed) == A.SimHash(simmed) and A.SimHash(simmed) >= 0 and A.SimHash(simmed) < 100, "fixed verdict per player")
local under = 0
for i = 1, 2000 do if A.SimHash(("Player-99-%08X"):format(i * 7919)) < 10 then under = under + 1 end end
check(under > 120 and under < 280, "about 10% of players fall under 10 (" .. under .. ")")

-- Another tester's FS: taken only when our own hash agrees.
local relayedSim = "Player-99-5AA002"
shared("FS|1|" .. relayedSim .. "|Relay-OtherRealm|1|0|sim")
units.nameplate1 = { guid = relayedSim, flagged = false, faction = "Horde", name = "Relay", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
advance(5)
check(crest.shown and not crest.desaturated and #whispers("Relay-OtherRealm") == 0, "another tester's FS gives a crest without a probe")
-- An N list never hides a player we're simulating.
local listed = "Player-99-5AA003"
shared("N|1|" .. listed:sub(8))
check(HonorBoundDB.noAddon[listed] == nil, "shared no-addon list can't hide a simulated user")

-- 0%: no fakes, and the no-addon path is exactly the real one.
sent = {}
SlashCmdList.HONORBOUND("sim 0")
local plain = "Player-99-5AA004"
shared("FS|1|" .. plain .. "|Plain-OtherRealm|1|0|sim")
units.nameplate1 = { guid = plain, flagged = false, faction = "Horde", name = "Plain", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(probeSent("Plain-OtherRealm"), "FS for a player our hash rejects is ignored, so we probe")
advance(31)
check(crest.shown and crest.desaturated and crest.tint[1] < 0.5 and crest.tint[1] == crest.tint[2], "dark grey crest once marked no-addon")
check(HonorBoundDB.noAddon[plain], "no-addon still saved while simulating")
advance(45)
check(#channelPosts("N|1|", plain:sub(8)) == 1, "no-addon still shared while simulating")

-- Off: simulated crests go, real knowledge stays.
SlashCmdList.HONORBOUND("sim 100")
units.nameplate1 = { guid = simmed, flagged = false, faction = "Horde", name = "Simmy", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
advance(1)
SlashCmdList.HONORBOUND("sim off")
check(not crest.shown, "sim off removes simulated crests")
check(HonorBoundDB.noAddon[plain], "sim off keeps saved no-addon entries")
sent = {}
shared("FS|1|" .. relayedSim .. "|Relay-OtherRealm|1|0|sim")
check(#sent == 0, "clients not simulating ignore FS")

-- Same budget with or without simulation.
local function crowdWhispers(percent)
    SlashCmdList.HONORBOUND(percent and ("sim " .. percent) or "sim off")
    advance(30)
    sent = {}
    for i = 1, 60 do say(("C%d-OtherRealm"):format(i), ("Player-98-%06X"):format((percent or 7) * 1000 + i)) end
    advance(60)
    return #whispers()
end
local off, on = crowdWhispers(nil), crowdWhispers(100)
check(on <= 5 + 60 / 2 and on <= off + 2, "simulation sends no more whispers than real (" .. off .. " vs " .. on .. ")")
SlashCmdList.HONORBOUND("sim off")

-- Simulated users already on the no-addon list still get asked and answer.
local ruled = "Player-99-5AA0F0"
HonorBoundDB.noAddon[ruled] = time() + 7200
SlashCmdList.HONORBOUND("sim 100")
units.nameplate1 = { guid = ruled, flagged = false, faction = "Horde", name = "Ruled", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(probeSent("Ruled-OtherRealm"), "a simulated user on the no-addon list is still probed")
advance(4)
check(crest.shown and not crest.desaturated, "and gets a full crest")
check(HonorBoundDB.noAddon[ruled], "the saved no-addon list itself is untouched")
SlashCmdList.HONORBOUND("sim off")

-- Chat shows the grey states while debugging.
SlashCmdList.HONORBOUND("debug on")
local askedInChat = "Player-99-C4A001"
say("Asked-OtherRealm", askedInChat)
check(probeSent("Asked-OtherRealm"), "trade/say speaker gets probed")
local line = chatCrest(askedInChat, "Asked")
check(line and line:find("CrestGrey.tga", 1, true) and line:find(":255:255:255|t", 1, true), "light grey crest in chat while being asked")
advance(31)
line = chatCrest(askedInChat, "Asked")
check(line and line:find("CrestGrey.tga", 1, true) and line:find(":102:102:102|t", 1, true), "dark grey crest in chat once marked no-addon")
check(chatCrest(askedInChat, line) == nil, "grey crest isn't added twice")
SlashCmdList.HONORBOUND("debug off")
check(chatCrest(askedInChat, "Asked") == nil, "no grey crests in chat when debug is off")

-- First messages: lines already in chat get their crest once the probe answers.
local history = {}
-- Like Forever's client: callbacks get the line's text and colours, and the
-- returned values replace them.
ChatFrame1 = { TransformMessages = function(self, predicate, transform)
    for _, entry in ipairs(history) do
        if predicate(entry.message, entry.r, entry.g, entry.b) then
            entry.message, entry.r, entry.g, entry.b = transform(entry.message, entry.r, entry.g, entry.b)
        end
    end
end }
-- Another client style: callbacks get the entry table and edit it in place.
local tableHistory = {}
ChatFrame3 = { TransformMessages = function(self, predicate, transform)
    for _, entry in ipairs(tableHistory) do if predicate(entry) then transform(entry) end end
end }
ChatFrame2 = {} -- a frame without history rewriting is left alone
local nextLine = 5000
local function printChat(sender, guid, text)
    nextLine = nextLine + 1
    local args = {}
    args[11], args[12] = nextLine, guid
    local shown = ChatFrameUtil.filter("CHAT_MSG_CHANNEL", sender:match("^[^%-]+"), unpack(args, 1, 12))
    local entry = { message = ("|Hplayer:%s:%d:CHANNEL:2|h[%s]|h: %s"):format(sender, nextLine, shown or sender:match("^[^%-]+"), text),
        r = 1, g = 0.75, b = 0.75 }
    history[#history + 1] = entry
    tableHistory[#tableHistory + 1] = { message = entry.message }
    event("CHAT_MSG_CHANNEL", text, sender, "", "2. Trade", sender, "", 0, 2, "Trade", 0, nextLine, guid)
    return entry
end
local function crests(entry)
    local _, n = entry.message:gsub("Media\\Crest", "")
    return n
end
SlashCmdList.HONORBOUND("sim 100")
SlashCmdList.HONORBOUND("debug off")
local trader = "Player-99-F1A001"
local first = printChat("Trader-OtherRealm", trader, "WTS stuff")
check(crests(first) == 0, "a stranger's first line prints without a crest")
check(probeSent("Trader-OtherRealm"), "the trade line starts a probe")
advance(4)
check(first.message:find("CrestHorde.tga", 1, true) or first.message:find("CrestAlliance.tga", 1, true), "the first line gets its crest once they answer")
check(crests(first) == 1 and first.message:find("|h[|T", 1, true), "exactly one crest, inside the name")
check(first.message:find("|h: WTS stuff", 1, true), "the message text is untouched")
check(first.r == 1 and first.g == 0.75 and first.b == 0.75, "the line's colour survives the rewrite")
check(tableHistory[#tableHistory].message:find("|h[|T", 1, true), "clients that pass entry tables are updated too")
local second = printChat("Trader-OtherRealm", trader, "still selling")
check(crests(second) == 1, "later lines get the crest when printed")

-- Debug: the grey states show on the line and are replaced, never stacked.
SlashCmdList.HONORBOUND("sim 0")
SlashCmdList.HONORBOUND("debug on")
local silentTrader = "Player-99-F1A002"
local line = printChat("Lfger-OtherRealm", silentTrader, "LFG")
check(probeSent("Lfger-OtherRealm"), "silent trader probed")
check(line.message:find("CrestGrey.tga", 1, true) and line.message:find(":255:255:255|t", 1, true), "first line turns light grey while being asked")
advance(31)
check(line.message:find(":102:102:102|t", 1, true) and crests(line) == 1, "then dark grey, replacing the light grey")
SlashCmdList.HONORBOUND("debug off")

-- Sim off takes simulated crests back off old lines.
SlashCmdList.HONORBOUND("sim off")
check(crests(first) == 0 and crests(second) == 0, "sim off removes simulated crests from old lines")
debugLines = {}
SlashCmdList.HONORBOUND("chatcheck")
local report = table.concat(debugLines, "\n")
if os.getenv("SHOW_CHECK") then print(report) end
check(report:find("rewrite old lines (TransformMessages): yes", 1, true) and report:find("Each line is a string", 1, true)
    and report:find("matching a remembered line ID inside a player link: ", 1, true), "chatcheck reports the chat frame's shape")
ChatFrame1, ChatFrame2, ChatFrame3 = nil, nil, nil

-- Debug output reads as sentences: no raw protocol strings or bare GUIDs.
debugLines = {}
SlashCmdList.HONORBOUND("debug verbose")
players["Player-99-DB0001"] = { name = "Readable", realm = "Other Realm" }
addon("WQ|1|Player-99-DB0001|1|12|0.3.1", "Readable-OtherRealm")
shared("F|1|Player-99-DB0002|Sharer-OtherRealm|1|30|0.3.1")
shared("N|1|99-DB0003,99-DB0004")
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(other, true), "CHANNEL", "Neighbour")
units.mouseover = { guid = "Player-99-DB0005", flagged = true, faction = "Horde", name = "Quiet", realm = "Other Realm" }
event("UPDATE_MOUSEOVER_UNIT")
channelResult = 8
advance(70)
channelResult = nil
SlashCmdList.HONORBOUND("debug on")
local raw, guids = {}, {}
for _, line in ipairs(debugLines) do
    local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if plain:find("|") then raw[#raw + 1] = plain end
    if plain:find("Player%-%d") then guids[#guids + 1] = plain end
end
check(#raw == 0, "no protocol text in debug lines: " .. table.concat(raw, " / "))
check(#guids == 0, "no raw GUIDs in debug lines: " .. table.concat(guids, " / "))
-- A refused status update waits 10 s instead of retrying every second.
local refused = 0
for _, line in ipairs(debugLines) do
    if line:find("Couldn't send", 1, true) and line:find("your status", 1, true) then refused = refused + 1 end
end
check(refused <= 8, "refused status updates back off (" .. refused .. " in 70 s)")
check(#debugLines > 8, "verbose debug produced output (" .. #debugLines .. " lines)")
if os.getenv("SHOW_DEBUG") then for _, line in ipairs(debugLines) do print((line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) end end
SlashCmdList.HONORBOUND("debug off")
-- Reflag on the next keypress, and dungeons pause the countdown.
local overrides, instance = {}, false
local keyActions = {["1"] = "ACTIONBUTTON1", ["2"] = "ACTIONBUTTON2", ["SHIFT-Q"] = "ACTIONBUTTON2",
    ["3"] = "CLICK BT4Button3:LeftButton", ["Z"] = "SHAPESHIFTBUTTON1", ["W"] = "MOVEFORWARD"}
function GetBindingKey(command)
    local keys = {}
    for key, action in pairs(keyActions) do if action == command then keys[#keys + 1] = key end end
    table.sort(keys)
    return unpack(keys)
end
function GetBindingAction(key) return keyActions[key] or "" end
function SetOverrideBindingClick(_, _, key, name, button) overrides[key] = {name = name, button = button} end
function ClearOverrideBindings() for key in pairs(overrides) do overrides[key] = nil end end
function IsInInstance() return instance, instance and "party" or "none" end
function GetCVarBool(name) return name == "ActionButtonUseKeyDown" end
ActionButton1, ActionButton2, BT4Button3 = object("ActionButton1"), object("ActionButton2"), object("BT4Button3")
StanceButton1 = object("StanceButton1")
-- The click overlays: secure buttons whose macro is set per mouse button.
local function overlays()
    local found = {}
    for _, frame in ipairs(frames) do
        if frame.attributes.macrotext1 then found[#found + 1] = frame end
    end
    return found
end
local function borrowed() local n = 0 for _ in pairs(overrides) do n = n + 1 end return n end
local function macroFor(key) return HonorBoundReflagButton.attributes["*macrotext-" .. overrides[key].button] end
local function setFlag(on) desired, units.player.flagged = on, on event("PLAYER_FLAGS_CHANGED", "player") end

setFlag(true)
SlashCmdList.HONORBOUND("swear")
check(HonorBoundCharDB.sworn, "sworn again for the reflag checks")
instance = true
event("PLAYER_ENTERING_WORLD")
setFlag(false)
check(borrowed() == 0 and not prompt.shown, "inside a dungeon: no borrowed keys, no popup")
advance(A.GRACE + 30)
check(HonorBoundCharDB.sworn, "dungeon time doesn't run the countdown down")
instance = false
event("PLAYER_ENTERING_WORLD")
check(borrowed() == 5 and overrides["1"].name == "HonorBoundReflagButton", "leaving borrows the bar keys")
check(not prompt.shown, "no popup while the keys are borrowed")
local both = function(name) return ("/pvp\n/click %s LeftButton 1\n/click %s LeftButton"):format(name, name) end
check(macroFor("1") == both("ActionButton1"), "key 1 flags, then presses its own button: " .. tostring(macroFor("1")))
check(macroFor("SHIFT-Q") == both("ActionButton2"), "second binding of a bar button")
check(macroFor("3") == both("BT4Button3"), "bar addon button through its CLICK binding")
check(macroFor("Z") == "/pvp\n/click StanceButton1 LeftButton", "stance buttons get one click, not two: " .. tostring(macroFor("Z")))
check(overrides["W"] == nil, "movement keys are never borrowed")
local clickOverlays = overlays()
check(#clickOverlays == 4, "click overlays over the bar buttons in use (" .. #clickOverlays .. ")")
local overlayHost = clickOverlays[1].parent
check(overlayHost.shown, "overlays shown while armed")
local overBT4
for _, overlay in ipairs(clickOverlays) do
    if overlay.attributes.macrotext1 == both("BT4Button3") then overBT4 = overlay end
end
check(overBT4 and overBT4.attributes.macrotext2 == "/pvp\n/click BT4Button3 RightButton 1\n/click BT4Button3 RightButton", "right click passes through as a right click")
event("PLAYER_REGEN_DISABLED")
combat = true
advance(2)
check(borrowed() == 0 and not overlayHost.shown, "keys and overlays handed back before combat")
-- Flagged mid-fight: the overlay host holds secure buttons, so it isn't touched in combat.
overlayHost.shown = true
desired, units.player.flagged = true, true
event("PLAYER_FLAGS_CHANGED", "player")
check(overlayHost.shown, "overlays not hidden during combat lockdown")
desired, units.player.flagged = false, false
event("PLAYER_FLAGS_CHANGED", "player")
overlayHost.shown = false
combat = false
event("PLAYER_REGEN_ENABLED")
check(borrowed() == 5 and overlayHost.shown, "borrowed again after combat")
-- The press: the macro's /pvp flags you; the keys go back straight away.
HonorBoundReflagButton.scripts.PostClick(HonorBoundReflagButton)
blizzardPvp()
check(borrowed() == 0 and not overlayHost.shown, "keys and overlays handed back after one press")
advance(1)
check(borrowed() == 0, "not borrowed again while the flag registers")
units.player.flagged = true
event("PLAYER_FLAGS_CHANGED", "player")
advance(5)
check(borrowed() == 0 and HonorBoundCharDB.sworn and not prompt.shown, "reflagged by the keypress, oath kept")
-- Keys unused: the popup follows.
setFlag(false)
check(borrowed() == 5 and not prompt.shown, "unflagged again: keys borrowed")
advance(31)
check(prompt.shown and prompt.flag.text == "Stay flagged" and borrowed() == 5, "popup after 30 s, keys still borrowed")
setFlag(true)
check(borrowed() == 0 and not prompt.shown, "flagging any other way hands the keys back")
-- Turned off: straight to the popup.
SlashCmdList.HONORBOUND("autoflag off")
setFlag(false)
check(borrowed() == 0 and prompt.shown, "autoflag off: popup, no borrowed keys")
SlashCmdList.HONORBOUND("autoflag on")
check(borrowed() == 5, "autoflag on borrows the keys")
setFlag(true)
check(borrowed() == 0, "and hands them back once flagged")

-- 0.4.1: Forever names. Whispers to "First Surname-Realm" bounce; replies
-- go to "First-Surname", the form probes use.
advance(400)
sent = {}
local fg = "Player-97-F0F001"
players[fg] = { name = "Aninja Rppvp", realm = "ClassicBetaPvE" }
addon("WQ|1|" .. fg .. "|1|20|0.4.0", "Aninja Rppvp-ClassicBetaPvE")
advance(2)
check(#whispers("Aninja-Rppvp") == 1 and #whispers("Aninja Rppvp-ClassicBetaPvE") == 0, "reply goes to First-Surname, not First Surname-Realm")
check(HonorBoundDB.likely[fg] and HonorBoundDB.likely[fg].name == "Aninja-Rppvp", "remembered under the whisperable name")

-- Always reply, even while our own probe to them is still waiting.
sent = {}
local both = "Player-97-F0F003"
units.mouseover = { guid = both, flagged = true, faction = units.player.faction, name = "Both", realm = "Sides" }
event("UPDATE_MOUSEOVER_UNIT")
check(probeSent("Both-Sides"), "our probe goes out")
addon("WQ|1|" .. both .. "|1|20|0.4.0", "Both Sides-ClassicBetaPvE")
advance(2)
local replied = false
for _, m in ipairs(whispers("Both-Sides")) do replied = replied or m.message:find("^WR|") ~= nil end
check(replied, "a probe crossing ours still gets a reply")

-- Re-probe a peer in view before the badge expires.
sent = {}
units.mouseover = nil
units.nameplate1 = { guid = both, flagged = true, faction = units.player.faction, name = "Both", realm = "Sides" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local reprobed
for t = 1, A.TTL do
    advance(1)
    event("NAME_PLATE_UNIT_ADDED", "nameplate1")
    if not reprobed then
        for _, m in ipairs(whispers("Both-Sides")) do if m.message:find("^WQ|") then reprobed = t end end
    end
end
check(reprobed and reprobed < A.TTL - 20, "re-probed before the badge expires (" .. tostring(reprobed) .. " s)")

-- Crests in whispers, both directions, and in yell and emotes.
local function crestIn(event_, guid, name)
    local args = {}
    args[12] = guid
    local shown = ChatFrameUtil.filter(event_, name, unpack(args, 1, 12))
    return shown and shown:find("Crest", 1, true) ~= nil
end
addon("WR|1|" .. both .. "|1|20|0.4.0", "Both Sides-ClassicBetaPvE")
for _, e in ipairs({"CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE"}) do
    check(crestIn(e, both, "Both"), e .. " shows the crest")
end

-- /honor sim off turns debug off too.
SlashCmdList.HONORBOUND("sim 10")
SlashCmdList.HONORBOUND("sim off")
debugLines = {}
SlashCmdList.HONORBOUND("debug")
check(not tostring(debugLines[#debugLines]):find("Debug off", 1, true), "debug was already off after sim off")
SlashCmdList.HONORBOUND("debug off")

-- A bounced reply shows in debug.
SlashCmdList.HONORBOUND("debug on")
sent = {}
local gone = "Player-97-F0F004"
addon("WQ|1|" .. gone .. "|0|0|0.4.0", "Gone Away-ClassicBetaPvE")
advance(2)
debugLines = {}
check(systemFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "No player named 'Gone-Away' is currently playing.") == true, "bounced reply error hidden")
local logged = false
for _, line in ipairs(debugLines) do logged = logged or line:find("reply to Gone%-Away bounced") ~= nil end
check(logged, "bounced reply reported in debug")
SlashCmdList.HONORBOUND("debug off")

-- 0.4.3: saved oath status. A remembered sworn player shows a crest as soon
-- as they're seen, while a re-check goes out.
advance(400)
sent = {}
local cg = "Player-96-C0C001"
local sv = "Player-96-C0C000"
players[sv] = { name = "Saved Status", realm = "ClassicBetaPvE" }
addon("WQ|1|" .. sv .. "|1|20|0.4.3", "Saved Status-ClassicBetaPvE")
check(HonorBoundDB.likely[sv] and HonorBoundDB.likely[sv].sworn == true, "an answer saves the oath status with the name")
HonorBoundDB.likely[cg] = { name = "Cache-Dname", seen = time(), sworn = true }
units.nameplate1 = { guid = cg, flagged = true, faction = units.player.faction, name = "Cache", realm = "Dname" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(plate.UnitFrame.HonorBoundCrest.shown, "saved status shows the crest at once")
local function cachedChat() local a = {} a[12] = cg return ChatFrameUtil.filter("CHAT_MSG_SAY", "Cache", unpack(a, 1, 12)) end
check((cachedChat() or ""):find("Crest", 1, true), "and in chat")
check(probeSent("Cache-Dname"), "and a re-check goes out")
units.nameplate1.flagged = false
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(not plate.UnitFrame.HonorBoundCrest.shown, "saved status never overrides the live flag")
units.nameplate1.flagged = true
-- One unanswered re-check: the crest stays. Two: it goes.
advance(31)
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(plate.UnitFrame.HonorBoundCrest.shown and not HonorBoundDB.noAddon[cg], "one missed re-check keeps the crest")
sent = {}
check(probeSent("Cache-Dname"), "a second re-check goes out")
advance(31)
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(not plate.UnitFrame.HonorBoundCrest.shown and HonorBoundDB.noAddon[cg], "two missed re-checks drop it")
-- An answer saying "not sworn" replaces the saved status.
local cn = "Player-96-C0C002"
HonorBoundDB.likely[cn] = { name = "Gave-Up", seen = time(), sworn = true }
units.nameplate1 = { guid = cn, flagged = true, faction = units.player.faction, name = "Gave", realm = "Up" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(plate.UnitFrame.HonorBoundCrest.shown, "saved sworn status shown")
addon("WR|1|" .. cn .. "|0|0|0.4.3", "Gave Up-ClassicBetaPvE")
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(not plate.UnitFrame.HonorBoundCrest.shown and not HonorBoundDB.likely[cn].sworn, "a 'not sworn' answer removes the crest and the saved status")
units.nameplate1 = nil

print("Passed " .. assertions .. " assertions: protocol, oath, grace, peer flag checks, crest placement, nameplates, settings, whisper probes, realm sharing, same-realm queries, chat crests, simulation, readable debug, reflag keys and click overlays.")
