-- Run from the project root: lua tests/run.lua
local A = {}
assert(loadfile("HonorBound/Core.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Pledge.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Verify.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Save.lua"))("HonorBound", A)
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
function methods:IsVisible() return self.shown ~= false and (not self.parent or not self.parent.IsVisible or self.parent:IsVisible()) end
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
function GameTooltip:AddLine(text) tooltipLines[#tooltipLines + 1] = text end
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
playedRequests = 0
-- Macros like Forever: account ones at 1-120, character ones from 121, and
-- 30 character slots (two rows more than Classic). MAX_CHARACTER_MACROS still
-- says Classic's 18, as the stale constant would.
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS, CHARACTER_SLOTS = 120, 18, 30
macros = {}
function GetNumMacros()
    local account, character = 0, 0
    for index in pairs(macros) do
        if index > 120 then character = character + 1 else account = account + 1 end
    end
    return account, character
end
function GetMacroIndexByName(name)
    for index, m in pairs(macros) do if m.name == name then return index end end
    return 0
end
function GetMacroInfo(index) local m = macros[index] if m then return m.name, m.icon, m.body end end
function CreateMacro(name, icon, body, perCharacter)
    local _, character = GetNumMacros()
    if character >= CHARACTER_SLOTS then error("Too many macros") end
    local index = 121
    while macros[index] do index = index + 1 end
    macros[index] = {name = name, icon = icon, body = body, perCharacter = perCharacter}
    return index
end
function EditMacro(index, name, icon, body)
    local m = macros[index]
    m.name, m.icon, m.body = name or m.name, icon or m.icon, body
    return index
end
function RequestTimePlayed() playedRequests = playedRequests + 1 end
function UnitLevel() return 20 end
function time() return 1000000 + now end
function UnitName(unit) return units[unit] and units[unit].name, units[unit] and units[unit].realm end
-- A guild member: status updates go to the guild now that there is no channel.
local inGuild = true
function IsInGuild() return inGuild end
local lockdown, players, systemFilters, channelResult, whisperResult = false, {}, {}, nil, nil
function UnitIsPlayer(unit) return units[unit] ~= nil end
function UnitName(unit) return units[unit] and units[unit].name, units[unit] and units[unit].realm end
function GetPlayerInfoByGUID(guid)
    local p = players[guid]
    if p then return "Warrior", "WARRIOR", "Orc", "Orc", 2, p.name, p.realm end
end
ChatFrameUtil = { AddSenderNameFilter = function(f) ChatFrameUtil.filter = f end, RemoveSenderNameFilter = function() end }
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
function ChatFrame_AddMessageEventFilter(event, filter) systemFilters[event] = filter end
-- Like the game: no unit is a usage error, not nil.
function UnitGUID(unit)
    if type(unit) ~= "string" then error("Usage: UnitGUID(unit)", 2) end
    return units[unit] and units[unit].guid
end
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
        -- channelResult refuses status routes (group/guild); whisperResult refuses whispers.
        if route == "WHISPER" then return whisperResult or 0 end
        return channelResult or 0
    end,
}
C_Timer = {
    After = function(delay, callback) tasks[#tasks + 1] = {at = now + delay, callback = callback} end,
    NewTicker = function(_, callback) tickers[#tickers + 1] = callback end,
}
-- Tooltips: capture the unit post-call and the lines it adds.
Enum = { TooltipDataType = { Unit = 1 } }
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) tooltipCallback = callback end }
tooltipLines = {}
-- Activity for away protection: the player is active unless a test says not.
moving = true
function IsPlayerMoving() return moving end
assert(loadfile("HonorBound/HonorBound.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Options.lua"))("HonorBound", A)
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
local function peer(sworn) event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(other, sworn), "GUILD", "Surname-bearing Name") end

-- First login, already flagged: offered the oath, no crest yet.
event("PLAYER_LOGIN")
check(prompt.shown and prompt.swear.shown, "welcome prompt offers the oath")
check(not playerBadge().shown, "no crest before swearing")
advance(18)
check(not connected and lastSent():find("|0|"), "announces unsworn to the guild, and never joins a channel")

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

-- Whisper probes: everyone we see is asked by whisper.
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

-- Crowd: no pacing outside instances. 80 speakers at once are all asked
-- within a tick.
advance(30)
sent = {}
for i = 1, 80 do say(("P%d-OtherRealm"):format(i), ("Player-99-%06X"):format(4096 + i)) end
advance(1)
check(#whispers() == 80, "every speaker in a crowd is whispered at once (" .. #whispers() .. ")")
-- /honor rate caps it for testing.
SlashCmdList.HONORBOUND("rate 5")
sent = {}
for i = 1, 30 do say(("R%d-OtherRealm"):format(i), ("Player-99-%06X"):format(8192 + i)) end
advance(1)
check(#whispers() == 5, "/honor rate 5 sends at most 5 a second (" .. #whispers() .. ")")
advance(5)
check(#whispers() == 30, "and the rest follow (" .. #whispers() .. ")")
SlashCmdList.HONORBOUND("rate off")

sent = {}
lockdown = true
say("Late-OtherRealm", "Player-99-FFF666")
advance(5)
check(#whispers() == 0, "no whispers during encounter lockdown")
lockdown = false
advance(2)
check(#whispers("Late-OtherRealm") == 1, "queued probe goes out after lockdown")

-- Same realm: asked by whisper too, never on a channel.
local function channelPosts()
    local list = {}
    for _, m in ipairs(sent) do if m.route == "CHANNEL" then list[#list + 1] = m end end
    return list
end
local function probeSentTo(name)
    for _ = 1, 5 do
        if #whispers(name) > 0 then return true end
        advance(1)
    end
end
advance(200)
sent = {}
local neighbour = "Player-70-0BB001"
units.nameplate1 = { guid = neighbour, flagged = true, faction = "Horde", name = "Neighbour", realm = "Home" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(probeSentTo("Neighbour-Home"), "a same-realm player is whispered a probe")
check(#channelPosts() == 0, "nothing is sent on a channel")
advance(31)
check(HonorBoundDB.noAddon[neighbour], "a silent same-realm player is marked no-addon")
-- Their status in the guild clears the mistake straight away.
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(neighbour, true), "GUILD", "Neighbour")
check(HonorBoundDB.noAddon[neighbour] == nil, "hearing a player clears their no-addon entry")
check(plate.UnitFrame.HonorBoundCrest.shown, "and their crest appears")

-- Rate limits: refused sends are for developers, shown in debug mode only.
local function limited()
    local list = {}
    for _, line in ipairs(debugLines) do if line:find("Rate limited", 1, true) then list[#list + 1] = line end end
    return list
end
debugLines = {}
whisperResult = 3
for i = 1, 3 do say(("Q%d-OtherRealm"):format(i), ("Player-99-%06X"):format(12200 + i)) end
advance(12)
check(#limited() == 0, "players never see rate-limit reports with debug off")
SlashCmdList.HONORBOUND("debug on")
debugLines = {}
sent = {}
for i = 1, 5 do say(("T%d-OtherRealm"):format(i), ("Player-99-%06X"):format(12288 + i)) end
advance(11)
check(#limited() >= 1 and limited()[1]:find("sending too fast", 1, true), "with debug on, refusals are reported: " .. tostring(limited()[1]))
debugLines = {}
for i = 6, 9 do say(("T%d-OtherRealm"):format(i), ("Player-99-%06X"):format(12288 + i)) end
advance(30)
check(#limited() >= 2 and #limited() <= 4, "at most one report every 10 s (" .. #limited() .. " in 30 s)")
whisperResult = nil
debugLines = {}
ERR_CHAT_THROTTLED = "You are sending too many messages."
check(systemFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED) == nil, "the server's own throttle notice stays visible")
advance(11)
local serverNotice = false
for _, line in ipairs(limited()) do serverNotice = serverNotice or line:find("server says we're sending too fast", 1, true) ~= nil end
check(serverNotice, "and is counted as a rate limit")
SlashCmdList.HONORBOUND("debug off")

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
check(#channelPosts() == 0, "simulated answers aren't shared on any channel")
check(A.SimHash(simmed) == A.SimHash(simmed) and A.SimHash(simmed) >= 0 and A.SimHash(simmed) < 100, "fixed verdict per player")
local under = 0
for i = 1, 2000 do if A.SimHash(("Player-99-%08X"):format(i * 7919)) < 10 then under = under + 1 end end
check(under > 120 and under < 280, "about 10% of players fall under 10 (" .. under .. ")")

-- 0%: no fakes, and the no-addon path is exactly the real one.
sent = {}
SlashCmdList.HONORBOUND("sim 0")
local plain = "Player-99-5AA004"
units.nameplate1 = { guid = plain, flagged = false, faction = "Horde", name = "Plain", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(probeSent("Plain-OtherRealm"), "a player outside the simulated share is probed")
advance(31)
check(crest.shown and crest.desaturated and crest.tint[1] < 0.5 and crest.tint[1] == crest.tint[2], "dark grey crest once marked no-addon")
check(HonorBoundDB.noAddon[plain], "no-addon still saved while simulating")

-- Off: simulated crests go, real knowledge stays.
SlashCmdList.HONORBOUND("sim 100")
units.nameplate1 = { guid = simmed, flagged = false, faction = "Horde", name = "Simmy", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
advance(1)
SlashCmdList.HONORBOUND("sim off")
check(not crest.shown, "sim off removes simulated crests")
check(HonorBoundDB.noAddon[plain], "sim off keeps saved no-addon entries")

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
check(on <= off + 2, "simulation sends no more whispers than real (" .. off .. " vs " .. on .. ")")
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
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(other, true), "GUILD", "Neighbour")
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
-- Inside dungeons and raids the client's whisper limit applies: paced again.
instance = true
advance(30)
sent = {}
for i = 1, 20 do say(("D%d-OtherRealm"):format(i), ("Player-99-%06X"):format(16384 + i)) end
advance(1)
check(#whispers() >= 1 and #whispers() <= 6, "inside an instance whispers are paced (" .. #whispers() .. " in a second)")
instance = false
advance(31)
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
check(playerBadge().shown, "inside a dungeon: unflagged, but your crest stays")
channelResult = 0 advance(11) event("GROUP_ROSTER_UPDATE")
check(lastSent():find("|1|"), "inside a dungeon: you still announce yourself as sworn")
units.target = { guid = other, flagged = false, faction = units.player.faction, name = "Dungeon", realm = "Mate" }
peer(true) event("PLAYER_TARGET_CHANGED")
check(targetBadge().shown, "inside a dungeon: an unflagged sworn peer keeps the crest")
advance(A.GRACE + 30)
check(HonorBoundCharDB.sworn, "dungeon time doesn't run the countdown down")
instance = false
event("PLAYER_ENTERING_WORLD")
check(not playerBadge().shown and not targetBadge().shown, "outside, unflagged: no crests until the flag is back")
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
-- Turned off by hand: the popup asks at once, and the keys still work.
setFlag(false)
check(borrowed() == 5 and prompt.shown and prompt.flag.text == "Stay flagged", "manual unflag: popup at once, keys borrowed")
setFlag(true)
-- Flag lost to a zone change (no flag wanted when we last looked): keys first, popup after 30 s.
instance = true
event("PLAYER_ENTERING_WORLD")
setFlag(false)
advance(2)
instance = false
event("PLAYER_ENTERING_WORLD")
advance(1)
check(borrowed() == 5 and not prompt.shown, "after a dungeon: keys borrowed, no popup yet")
advance(31)
check(prompt.shown and prompt.flag.text == "Stay flagged" and borrowed() == 5, "popup after 30 s, keys still borrowed")
setFlag(true)
check(borrowed() == 0 and not prompt.shown, "flagging any other way hands the keys back")
-- Turned off: straight to the popup.
SlashCmdList.HONORBOUND("autoflag off")
setFlag(false)
check(borrowed() == 0 and prompt.shown, "autoflag off: popup, no borrowed keys")
check(not prompt.text.text:find("action bar key", 1, true), "autoflag off: the popup doesn't send you to keys that won't flag you")
SlashCmdList.HONORBOUND("autoflag on")
check(borrowed() == 5, "autoflag on borrows the keys")
check(prompt.text.text:find("action bar key", 1, true), "autoflag on: the popup mentions the keys")
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

-- 0.4.3: away protection. Unflagged and idle, the grace countdown waits.
SlashCmdList.HONORBOUND("autoflag off")
HonorBoundCharDB.sworn = true
moving = false
setFlag(false)
advance(A.GRACE + 60)
check(HonorBoundCharDB.sworn, "idle while unflagged: the oath holds past the grace period")
check(prompt.text.text:find("starts when you move", 1, true), "unflagged while idle: the countdown hasn't started")
-- One step: the countdown runs for idle.after seconds, then holds.
event("PLAYER_STARTED_MOVING")
advance(40)
check(prompt.text.text:find("Paused while you're away", 1, true), "the popup says the countdown is paused")
local heldAt = prompt.text.text:match("within (%d+:%d+)")
check(heldAt == "4:30", "the step cost the 30 s it kept the countdown running, no more")
moving = true
advance(A.GRACE - 40)
check(HonorBoundCharDB.sworn, "active again: the countdown resumes from where it stopped")
advance(20)
check(not HonorBoundCharDB.sworn, "and breaks the oath once the rest runs out")
moving = true
-- Time with no checks at all (a long loading screen after clicking a
-- hearthstone in your bags) isn't charged: 2:00 left, then 2.5 minutes
-- with no ticks, and the oath holds with the time it had.
HonorBoundCharDB.sworn, HonorBoundCharDB.graceLeft = true, nil
setFlag(true)
moving = true
setFlag(false)
advance(A.GRACE - 120)
moving = false
now = now + 150 -- the loading screen: the clock moves, nothing runs
advance(1)
check(HonorBoundCharDB.sworn, "a long gap with no checks doesn't break the oath")
local afterGap = prompt.text.text:match("within (%d+):(%d+)")
check(afterGap and tonumber(afterGap) == 1, "and costs at most a couple of seconds")
moving = true
setFlag(true)
-- Casting counts as activity even standing still.
HonorBoundCharDB.sworn, HonorBoundCharDB.graceLeft = true, nil
setFlag(true)
moving = false
setFlag(false)
for _ = 1, A.GRACE + 5 do
    event("UNIT_SPELLCAST_SUCCEEDED", "player")
    advance(1)
end
check(not HonorBoundCharDB.sworn, "casting while standing still keeps the countdown running")
-- Chatting doesn't.
HonorBoundCharDB.sworn, HonorBoundCharDB.graceLeft = true, nil
setFlag(true)
setFlag(false)
for _ = 1, A.GRACE + 5 do
    event("CHAT_MSG_SAY", "afk", "Me", "", "", "Me", "", 0, 0, "", 0, 1, me)
    advance(1)
end
check(HonorBoundCharDB.sworn, "chatting alone counts as away")
moving = true
setFlag(true)
SlashCmdList.HONORBOUND("autoflag on")

-- 0.4.3: the saved status keeps the pledge level, and a claimed level above
-- the player's current level isn't shown.
local tl = "Player-96-C0C010"
players[tl] = { name = "Tip Level", realm = "ClassicBetaPvE" }
addon("WQ|1|" .. tl .. "|1|12|0.4.3", "Tip Level-ClassicBetaPvE")
check(HonorBoundDB.likely[tl].level == 12, "pledge level saved with the status")
local function tooltipFor(guid, name, realm)
    units.target = { guid = guid, flagged = true, faction = units.player.faction, name = name, realm = realm }
    tooltipLines = {}
    tooltipCallback(GameTooltip)
    return table.concat(tooltipLines, " / ")
end
check(tooltipCallback ~= nil, "tooltip hook installed")
check(tooltipFor(tl, "Tip", "Level"):find("since level 12", 1, true), "fresh answer: level in the tooltip")
local tc = "Player-96-C0C011"
HonorBoundDB.likely[tc] = { name = "Tip-Cached", seen = time(), sworn = true, level = 8 }
check(tooltipFor(tc, "Tip", "Cached"):find("since level 8", 1, true), "saved status: level in the tooltip too")
local tx = "Player-96-C0C012"
players[tx] = { name = "Tall Tale", realm = "ClassicBetaPvE" }
addon("WQ|1|" .. tx .. "|1|40|0.4.3", "Tall Tale-ClassicBetaPvE")
local shown = tooltipFor(tx, "Tall", "Tale")
check(shown:find("Sworn to RP-PvP", 1, true) and not shown:find("level 40", 1, true), "a level above their current one (20) isn't shown")
units.target = nil

-- Scenarios that need a fresh client each: tests/scenarios/*.lua, each run
-- in its own process by tests/scenario.lua.
local lua = arg and arg[-1] or "luajit"
local scenarios = {"renounce", "idle_reset", "idle_pvp_timer", "resurrect_crest", "stale_find", "inside", "options", "party", "remember", "options_broken", "verify_track", "verify_gap", "verify_fail", "verify_rules", "verify_noanswer", "save_restore", "save_crosspc", "save_broken", "save_pending", "save_altered", "save_flow", "save_full", "save_forever_slots"}
for _, name in ipairs(scenarios) do
    local ok = os.execute(lua .. " tests/scenario.lua " .. name .. " >/dev/null")
    check(ok == true or ok == 0, "scenario " .. name .. " (luajit tests/scenario.lua " .. name .. ")")
end

-- /honor why explains a missing nameplate crest.
local function why()
    debugLines = {}
    SlashCmdList.HONORBOUND("why")
    return table.concat(debugLines, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end
SlashCmdList.HONORBOUND("sim 100")
local shown = "Player-99-0EE001"
units.target = { guid = shown, flagged = false, faction = units.player.faction, name = "Shown", realm = "Other Realm" }
units.nameplate1 = units.target
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
advance(5)
local report = why()
check(report:find("Known addon user: yes (simulated)", 1, true) and report:find("Should wear a crest: yes", 1, true)
    and report:find("showing: yes", 1, true), "why: a simulated user's crest is accounted for:\n" .. report)
plate.UnitFrame.shown = false
IsAddOnLoaded = function(name) return name == "Plater" end
report = why()
check(report:find("Blizzard nameplate frame visible: no", 1, true) and report:find("Plater", 1, true)
    and report:find("hiding Blizzard's nameplate", 1, true), "why: a nameplate addon hiding the crest is named:\n" .. report)
plate.UnitFrame.shown, IsAddOnLoaded = true, nil
SlashCmdList.HONORBOUND("sim off")
units.target = { guid = "Player-99-0EE002", flagged = true, faction = units.player.faction, name = "Fresh", realm = "Other Realm" }
report = why()
check(report:find("Known addon user: no", 1, true), "why: an unknown player is reported as not known yet:\n" .. report)
units.target = nil
-- Nameplates the game never announced are still picked up, and one
-- nameplate failing doesn't stop the others.
SlashCmdList.HONORBOUND("sim 100")
local plate2, plate3 = object(), object()
plate2.UnitFrame, plate3.UnitFrame = object(), object()
plate2.UnitFrame.name, plate3.UnitFrame.name = object(), object()
plate2.namePlateUnitToken, plate3.namePlateUnitToken = "nameplate2", "nameplate3"
local realPlates = C_NamePlate
C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        if unit == "nameplate3" then error("broken plate") end
        return (unit == "nameplate1" and plate) or (unit == "nameplate2" and plate2) or nil
    end,
    GetNamePlates = function() return {plate2, plate3} end,
}
units.nameplate2 = { guid = "Player-99-0EE101", flagged = false, faction = units.player.faction, name = "Unannounced", realm = "Other Realm" }
units.nameplate3 = { guid = "Player-99-0EE102", flagged = false, faction = units.player.faction, name = "Broken", realm = "Other Realm" }
debugLines = {}
advance(5) -- no NAME_PLATE_UNIT_ADDED for either
check(plate2.UnitFrame.HonorBoundCrest and plate2.UnitFrame.HonorBoundCrest.shown, "an unannounced nameplate still gets its crest")
local reported = 0
for _, line in ipairs(debugLines) do if line:find("Couldn't update a nameplate crest", 1, true) then reported = reported + 1 end end
check(reported == 1, "a failing nameplate is reported once, not every second (" .. reported .. ")")
C_NamePlate = realPlates
units.nameplate2, units.nameplate3 = nil, nil
event("NAME_PLATE_UNIT_REMOVED", "nameplate2")
event("NAME_PLATE_UNIT_REMOVED", "nameplate3")
SlashCmdList.HONORBOUND("sim off")
-- Debug mode with Blizzard's empty party frames (not in a party): a frame
-- with no unit must not stop nameplates from updating.
PartyFrame = {}
for i = 1, 4 do
    local member = object("PartyMemberFrame" .. i)
    member.shown, member.unit = false, nil
    PartyFrame["MemberFrame" .. i] = member
end
SlashCmdList.HONORBOUND("debug on")
local asked = "Player-99-0EE201"
units.nameplate1 = { guid = asked, flagged = true, faction = units.player.faction, name = "Asked", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
local crestNow = plate.UnitFrame.HonorBoundCrest
check(not crestNow.shown, "a stranger's nameplate starts without a crest")
advance(2)
check(crestNow.shown and crestNow.desaturated and crestNow.tint[2] == 1, "with empty party frames, the nameplate still turns light grey once they're being asked")
SlashCmdList.HONORBOUND("debug off")
PartyFrame = nil
-- A failure in the once-a-second work never stops the redraw.
SlashCmdList.HONORBOUND("debug on")
local ruledLater = "Player-99-0EE301"
units.nameplate1 = { guid = ruledLater, flagged = false, faction = units.player.faction, name = "Later", realm = "Other Realm" }
local realLockdown = C_ChatInfo.InChatMessagingLockdown
C_ChatInfo.InChatMessagingLockdown = function() error("broken tick") end
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
HonorBoundDB.noAddon[ruledLater] = time() + 7200 -- learned after the nameplate appeared
debugLines = {}
advance(2)
local tickReported = 0
for _, line in ipairs(debugLines) do if line:find("Couldn't update discovery (", 1, true) then tickReported = tickReported + 1 end end
check(tickReported == 1, "a broken tick is reported once (" .. tickReported .. ")")
local later = plate.UnitFrame.HonorBoundCrest
check(later.shown and later.desaturated and later.tint[1] < 0.5, "the nameplate still redraws (dark grey) while the tick is broken")
C_ChatInfo.InChatMessagingLockdown = realLockdown
SlashCmdList.HONORBOUND("debug off")
-- Errors are developer information: nothing reaches the player with debug off.
SlashCmdList.HONORBOUND("debug off")
local quietPlates = C_NamePlate
local quietPlate = object()
quietPlate.UnitFrame = object()
quietPlate.namePlateUnitToken = "nameplate7"
C_NamePlate = {
    GetNamePlateForUnit = function(unit) if unit == "nameplate7" then error("broken plate") end end,
    GetNamePlates = function() return {quietPlate} end,
}
units.nameplate7 = { guid = "Player-99-0EE777", flagged = true, faction = units.player.faction, name = "Quiet", realm = "Other Realm" }
debugLines = {}
advance(65)
local leaked = 0
for _, line in ipairs(debugLines) do if line:find("Couldn't update", 1, true) or line:find("broken plate", 1, true) then leaked = leaked + 1 end end
check(leaked == 0, "a failing nameplate shows the player nothing with debug off (" .. leaked .. ")")
C_NamePlate = quietPlates
units.nameplate7 = nil
event("NAME_PLATE_UNIT_REMOVED", "nameplate7")
-- /honor help: player commands only, one per line; /honor devhelp: the rest.
local function helpLines(command)
    debugLines = {}
    SlashCmdList.HONORBOUND(command)
    return debugLines
end
local help = helpLines("help")
local helpText = table.concat(help, "\n")
check(#help == 13 and help[1]:find("Commands:", 1, true), "help lists 12 player commands, one per line (" .. #help .. " lines)")
check(helpText:find("|cffffd100/honor save|r |cff808080-|r |cffc8c8c8Save your pledge", 1, true)
    and helpText:find("|cffffd100/honor swear|r |cff808080-|r |cffc8c8c8Take the oath.|r", 1, true), "gold command, grey dash, light grey description")
for _, devCommand in ipairs({"debug", "sim", "rate", "why", "chatcheck"}) do
    check(not helpText:find("/honor " .. devCommand, 1, true), "help leaves out developer command " .. devCommand)
end
local devText = table.concat(helpLines("devhelp"), "\n")
check(devText:find("Developer commands:", 1, true) and devText:find("/honor debug verbose", 1, true)
    and devText:find("/honor chatcheck", 1, true) and not devText:find("/honor swear", 1, true), "devhelp lists the developer commands only")
check(table.concat(helpLines("nonsense"), "\n") == helpText, "an unknown command shows the player help")
-- Boss encounters: addon messages are blocked, so nothing is even tried.
SlashCmdList.HONORBOUND("debug on")
local attempts = 0
local realSend = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(...) attempts = attempts + 1 return realSend(...) end
group, lockdown = true, true
debugLines = {}
event("GROUP_ROSTER_UPDATE")
say("Boss-OtherRealm", "Player-99-0B0551")
advance(70)
check(attempts == 0, "no addon message is attempted during an encounter (" .. attempts .. ")")
local noise = 0
for _, line in ipairs(debugLines) do if line:find("Rate limited", 1, true) or line:find("Couldn't", 1, true) then noise = noise + 1 end end
check(noise == 0, "and nothing is reported as refused")
lockdown = false
sent = {}
advance(2)
local status = 0
for _, m in ipairs(sent) do if m.route == "PARTY" and m.message:sub(1, 2) == "S|" then status = status + 1 end end
check(status >= 1, "after the encounter the status goes out again")
say("Boss-OtherRealm", "Player-99-0B0551")
advance(1)
check(#whispers("Boss-OtherRealm") == 1, "and players seen afterwards are asked again")
C_ChatInfo.SendAddonMessage = realSend
group = false
SlashCmdList.HONORBOUND("debug off")
-- Zoning (Deeprun Tram, any loading screen): nothing is sent until a few
-- seconds after arriving, and nobody is marked no-addon because of it.
SlashCmdList.HONORBOUND("debug on")
local tries = 0
local sendNow = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(...) tries = tries + 1 return sendNow(...) end
group = true
debugLines, sent = {}, {}
local rider = "Player-99-07A001"
say("Rider-OtherRealm", rider)
event("LOADING_SCREEN_ENABLED")
advance(5)
event("LOADING_SCREEN_DISABLED")
event("PLAYER_ENTERING_WORLD")
advance(2)
check(tries == 0, "nothing is attempted while zoning or in the first seconds after (" .. tries .. ")")
check(not HonorBoundDB.noAddon[rider], "a player seen just before isn't marked no-addon")
local refusedLines = 0
for _, line in ipairs(debugLines) do if line:find("Rate limited", 1, true) or line:find("Couldn't send", 1, true) then refusedLines = refusedLines + 1 end end
check(refusedLines == 0, "and nothing is reported as refused")
say("Rider-OtherRealm", rider)
advance(3)
check(#whispers("Rider-OtherRealm") == 1, "after arriving, probes go out again")
local arrived = 0
for _, m in ipairs(sent) do if m.route == "PARTY" and m.message:sub(1, 2) == "S|" then arrived = arrived + 1 end end
check(arrived >= 1, "and the status update held back on arrival goes out")
-- A loading screen whose end is never seen can't hold sending for long.
tries = 0
event("LOADING_SCREEN_ENABLED")
advance(61)
say("Late-Zoner", "Player-99-07A002")
advance(2)
check(tries > 0, "sending resumes after a minute even if the loading screen's end is missed")
C_ChatInfo.SendAddonMessage = sendNow
group = false
SlashCmdList.HONORBOUND("debug off")
-- Chat names on Forever are "First Surname": probe "First-Surname", the form
-- that works (a space in the address bounces).
sent = {}
say("Blastor Totemborn", "Player-99-0C4A71")
say("Rage Nightwing-ClassicBetaPvE", "Player-99-0C4A72")
advance(1)
check(#whispers("Blastor-Totemborn") == 1 and #whispers("Blastor Totemborn") == 0, "a chat speaker is probed as First-Surname")
check(#whispers("Rage-Nightwing") == 1, "and with a realm attached too")
-- A refused whisper didn't happen: nobody is marked no-addon for it, the
-- pass stops, and it goes out once sends work again.
local tried = 0
local sendReal = C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage = function(...) tried = tried + 1 return sendReal(...) end
whisperResult = 9
sent = {}
for k = 1, 5 do say(("Refused%d-OtherRealm"):format(k), ("Player-99-%06X"):format(0x0F0000 + k)) end
tried = 0
advance(1)
check(tried == 1, "one refusal stops the pass (" .. tried .. " attempts)")
advance(35)
local wronglyMarked = 0
for k = 1, 5 do if HonorBoundDB.noAddon[("Player-99-%06X"):format(0x0F0000 + k)] then wronglyMarked = wronglyMarked + 1 end end
check(wronglyMarked == 0, "nobody is marked no-addon because of a refused probe")
addon("WQ|1|Player-99-0F1001|1|10|0.7.4", "Answer-Me")
advance(1)
whisperResult = nil
sent = {}
advance(1)
check(#whispers("Answer-Me") == 1 and whispers("Answer-Me")[1].message:sub(1, 3) == "WR|", "a refused reply is sent once sends work again")
say("Refused1-OtherRealm", ("Player-99-%06X"):format(0x0F0001))
advance(1)
check(#whispers("Refused1-OtherRealm") == 1, "and a player whose probe was refused is asked when seen again")
C_ChatInfo.SendAddonMessage = sendReal
print("Passed " .. assertions .. " assertions: protocol, oath, grace, peer flag checks, crest placement, nameplates, settings, whisper probes to everyone, rate-limit reports, chat crests, simulation, readable debug, reflag keys and click overlays; scenarios: " .. table.concat(scenarios, ", ") .. ".")
