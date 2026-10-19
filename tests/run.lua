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

local now, group, combat = 0, false, false
local desired = true
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
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:GetWidth() return self.width or 64 end
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
function UnitLevel() return 20 end
function time() return 1000000 + now end
local inGuild = true
function IsInGuild() return inGuild end
local lockdown, players, systemFilters, statusResult, whisperResult = false, {}, {}, nil, nil
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
function InCombatLockdown() return combat end
function IsInGroup(category) return not category and group end
function IsInRaid() return false end
C_ChatInfo = {
    RegisterAddonMessagePrefix = noop,
    InChatMessagingLockdown = function() return lockdown end,
    SendAddonMessage = function(_, message, route, target)
        sent[#sent + 1] = {message = message, route = route, target = target}
        -- Set to a result code to refuse: statusResult for group/guild, whisperResult for whispers.
        if route == "WHISPER" then return whisperResult or 0 end
        return statusResult or 0
    end,
}
C_Timer = {
    After = function(delay, callback) tasks[#tasks + 1] = {at = now + delay, callback = callback} end,
    NewTicker = function(_, callback) tickers[#tickers + 1] = callback end,
}
Enum = { TooltipDataType = { Unit = 1 } }
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) tooltipCallback = callback end }
tooltipLines = {}
-- Active unless a test says not (away protection).
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
-- Lines shown to the player outside debug output that contain text.
local function printed(text)
    local n = 0
    for _, line in ipairs(debugLines) do
        local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if plain:find("^HonorBound: ") and plain:find(text, 1, true) then n = n + 1 end
    end
    return n
end
local playerBadge = function() return PlayerFrame.HonorBoundWidget end
local targetBadge = function() return TargetFrame.HonorBoundWidget end
local function peer(sworn) event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(other, sworn), "GUILD", "Surname-bearing Name") end

-- First login, already flagged: offered the oath, no crest yet.
event("PLAYER_LOGIN")
check(prompt.shown and prompt.swear.shown, "welcome prompt offers the oath")
check(not playerBadge().shown, "no crest before swearing")
advance(18)

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
SlashCmdList.HONORBOUND("plates")
check(not plateCrest.shown, "nameplate crest toggle")
SlashCmdList.HONORBOUND("plates")
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

SlashCmdList.HONORBOUND("scale 1.5")
SlashCmdList.HONORBOUND("offset -10 20")
check(playerBadge().scale == 1.5, "crest size setting")
SlashCmdList.HONORBOUND("reset")
check(HonorBoundDB.plates and playerBadge().scale == 1, "reset appearance")

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

-- Swearing again completes once flagged.
SlashCmdList.HONORBOUND("swear")
check(not HonorBoundCharDB.sworn, "swear waits for the flag")
desired, units.player.flagged = true, true
event("PLAYER_FLAGS_CHANGED", "player")
check(HonorBoundCharDB.sworn and playerBadge().shown, "oath retaken on flag")

SlashCmdList.HONORBOUND("renounce")
check(HonorBoundCharDB.sworn, "renounce asks for confirmation")
SlashCmdList.HONORBOUND("renounce confirm")
check(HonorBoundCharDB.sworn == false and not playerBadge().shown, "renounce removes crest")

advance(A.TTL + 1)
check(not targetBadge().shown, "expire silent peers")
peer(true)

-- Whisper probes.
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
check(probe and probe.message:sub(1, #me + 5) == "WQ|1|" .. me, "mouseover sends a whisper probe")
units.mouseover = { guid = "Player-99-EEE555", flagged = true, faction = "Alliance", name = "Enemy", realm = "Other Realm" }
event("UPDATE_MOUSEOVER_UNIT")
advance(3)
check(#whispers("Enemy-OtherRealm") == 0, "no probes across factions")

addon("WR|1|" .. far .. "|1|20|0.2.0", "Farguy-OtherRealm")
units.nameplate1 = { guid = far, flagged = true, faction = "Horde", name = "Farguy", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(plate.UnitFrame.HonorBoundCrest.shown, "whisper reply gives a badge")
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
check(systemFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "No player named 'Silent-OtherRealm' is currently playing.") == true, "unreachable-player error is hidden")
advance(40)
say("Silent-OtherRealm", silent)
advance(5)
check(#whispers("Silent-OtherRealm") == 1, "players without the addon are not asked again")

-- Outside instances whispers are unpaced unless /honor rate caps them.
advance(30)
sent = {}
for i = 1, 80 do say(("P%d-OtherRealm"):format(i), ("Player-99-%06X"):format(4096 + i)) end
advance(1)
check(#whispers() == 80, "every speaker in a crowd is whispered at once (" .. #whispers() .. ")")
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
probeSentTo("Neighbour-Home")
advance(31)
check(HonorBoundDB.noAddon[neighbour], "a silent player is marked no-addon")
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(neighbour, true), "GUILD", "Neighbour")
check(HonorBoundDB.noAddon[neighbour] == nil, "hearing a player clears their no-addon entry")
check(plate.UnitFrame.HonorBoundCrest.shown, "and their crest appears")

-- Refused sends are reported, debug or not: at once, then one summary per 10 s.
debugLines = {}
whisperResult = 3
sent = {}
for i = 1, 5 do say(("T%d-OtherRealm"):format(i), ("Player-99-%06X"):format(12288 + i)) end
advance(1)
check(printed("refused") == 1, "refused whispers are reported at once")
for i = 6, 9 do say(("T%d-OtherRealm"):format(i), ("Player-99-%06X"):format(12288 + i)) end
advance(3)
check(printed("refused") == 1, "further refusals wait for the next summary")
advance(8)
check(printed("refused") == 2, "then one summary")
whisperResult = nil
ERR_CHAT_THROTTLED = "You are sending too many messages."
check(systemFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", ERR_CHAT_THROTTLED) == nil, "the server's own throttle notice stays visible")
advance(11)
check(printed("refused") == 3, "and is counted as a rate limit")

local function chatName(factionOf, name)
    local filter = A.CreateChatFilter(function() return true end, function() return true end, factionOf)
    local args = {}
    args[12] = other -- sender GUID
    return filter("CHAT_MSG_SAY", name, unpack(args, 1, 12))
end
local horde = chatName(function() return "Horde" end, "Bob")
check(horde:find("CrestHorde.tga", 1, true) and horde:find("Bob$"), "chat uses the Horde crest")
check(chatName(function() return "Alliance" end, "Bob"):find("CrestAlliance.tga", 1, true), "chat uses the Alliance crest")
check(chatName(function() return "Horde" end, horde) == nil, "chat crest is not added twice")

-- Simulation.
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
check(crest.shown and crest.desaturated and crest.tint[2] == 1, "light grey crest while the probe is waiting")
advance(4)
check(crest.shown and not crest.desaturated, "simulated user gets a standard crest within 3 s")
units.target = { guid = simmed, flagged = false, faction = "Horde", name = "Simmy", realm = "Other Realm" }
event("PLAYER_TARGET_CHANGED")
check(targetBadge().shown, "simulated user's crest shows on the target frame without a PvP flag")
local simChat = chatCrest(simmed, "Simmy")
check(simChat and simChat:find("CrestHorde.tga", 1, true), "simulated user's crest shows in chat")
check(HonorBoundDB.likely[simmed] == nil, "simulated users are never saved")
advance(12)
local under = 0
for i = 1, 2000 do if A.SimHash(("Player-99-%08X"):format(i * 7919)) < 10 then under = under + 1 end end
check(under > 120 and under < 280, "about 10% of players fall under 10 (" .. under .. ")")

sent = {}
SlashCmdList.HONORBOUND("sim 0")
local plain = "Player-99-5AA004"
units.nameplate1 = { guid = plain, flagged = false, faction = "Horde", name = "Plain", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
probeSent("Plain-OtherRealm")
advance(31)
check(crest.shown and crest.desaturated and crest.tint[1] < 0.5 and crest.tint[1] == crest.tint[2], "dark grey crest once marked no-addon")
check(HonorBoundDB.noAddon[plain], "no-addon still saved while simulating")

SlashCmdList.HONORBOUND("sim 100")
units.nameplate1 = { guid = simmed, flagged = false, faction = "Horde", name = "Simmy", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
advance(1)
SlashCmdList.HONORBOUND("sim off")
check(not crest.shown and HonorBoundDB.noAddon[plain], "sim off removes simulated crests, keeps what was learned")

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

local ruled = "Player-99-5AA0F0"
HonorBoundDB.noAddon[ruled] = time() + 7200
SlashCmdList.HONORBOUND("sim 100")
units.nameplate1 = { guid = ruled, flagged = false, faction = "Horde", name = "Ruled", realm = "Other Realm" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
probeSent("Ruled-OtherRealm")
advance(4)
check(crest.shown and not crest.desaturated, "a simulated user on the no-addon list still gets a full crest")
check(HonorBoundDB.noAddon[ruled], "the saved no-addon list itself is untouched")
SlashCmdList.HONORBOUND("sim off")

-- Grey states in chat while debugging.
SlashCmdList.HONORBOUND("debug on")
local askedInChat = "Player-99-C4A001"
say("Asked-OtherRealm", askedInChat)
probeSent("Asked-OtherRealm")
local line = chatCrest(askedInChat, "Asked")
check(line and line:find("CrestGrey.tga", 1, true) and line:find(":255:255:255|t", 1, true), "light grey crest in chat while being asked")
advance(31)
line = chatCrest(askedInChat, "Asked")
check(line and line:find("CrestGrey.tga", 1, true) and line:find(":102:102:102|t", 1, true), "dark grey crest in chat once marked no-addon")
SlashCmdList.HONORBOUND("debug off")
check(chatCrest(askedInChat, "Asked") == nil, "no grey crests in chat when debug is off")

-- Lines already in chat get their crest once the probe answers.
local history = {}
-- Like Forever: callbacks get the line's text and colours, and return replacements.
ChatFrame1 = { TransformMessages = function(self, predicate, transform)
    for _, entry in ipairs(history) do
        if predicate(entry.message, entry.r, entry.g, entry.b) then
            entry.message, entry.r, entry.g, entry.b = transform(entry.message, entry.r, entry.g, entry.b)
        end
    end
end }
-- Other clients: callbacks edit the entry table in place.
local tableHistory = {}
ChatFrame3 = { TransformMessages = function(self, predicate, transform)
    for _, entry in ipairs(tableHistory) do if predicate(entry) then transform(entry) end end
end }
ChatFrame2 = {} -- no history rewriting
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
probeSent("Trader-OtherRealm")
advance(4)
check(crests(first) == 1 and first.message:find("|h[|T", 1, true), "the first line gets one crest, inside the name, once they answer")
check(first.message:find("|h: WTS stuff", 1, true), "the message text is untouched")
check(first.r == 1 and first.g == 0.75 and first.b == 0.75, "the line's colour survives the rewrite")
check(tableHistory[#tableHistory].message:find("|h[|T", 1, true), "clients that pass entry tables are updated too")
local second = printChat("Trader-OtherRealm", trader, "still selling")

SlashCmdList.HONORBOUND("sim 0")
SlashCmdList.HONORBOUND("debug on")
local silentTrader = "Player-99-F1A002"
local line = printChat("Lfger-OtherRealm", silentTrader, "LFG")
probeSent("Lfger-OtherRealm")
advance(31)
check(line.message:find(":102:102:102|t", 1, true) and crests(line) == 1, "grey crests on old lines are replaced, never stacked")
SlashCmdList.HONORBOUND("debug off")

SlashCmdList.HONORBOUND("sim off")
check(crests(first) == 0 and crests(second) == 0, "sim off removes simulated crests from old lines")
ChatFrame1, ChatFrame2, ChatFrame3 = nil, nil, nil

-- Debug output reads as sentences: no raw protocol strings or bare GUIDs.
debugLines = {}
SlashCmdList.HONORBOUND("debug verbose")
players["Player-99-DB0001"] = { name = "Readable", realm = "Other Realm" }
addon("WQ|1|Player-99-DB0001|1|12|0.3.1", "Readable-OtherRealm")
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(other, true), "GUILD", "Neighbour")
units.mouseover = { guid = "Player-99-DB0005", flagged = true, faction = "Horde", name = "Quiet", realm = "Other Realm" }
event("UPDATE_MOUSEOVER_UNIT")
sent = {}
statusResult = 8
advance(70)
statusResult = nil
SlashCmdList.HONORBOUND("debug on")
local raw, guids = {}, {}
for _, line in ipairs(debugLines) do
    local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if plain:find("|") then raw[#raw + 1] = plain end
    if plain:find("Player%-%d") then guids[#guids + 1] = plain end
end
check(#debugLines > 0 and #raw == 0, "no protocol text in debug lines: " .. table.concat(raw, " / "))
check(#guids == 0, "no raw GUIDs in debug lines: " .. table.concat(guids, " / "))
local statusTries = 0
for _, m in ipairs(sent) do if m.route == "GUILD" and m.message:find("^S|") then statusTries = statusTries + 1 end end
check(statusTries >= 1 and statusTries <= 8, "refused status updates back off (" .. statusTries .. " tries in 70 s)")
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
ActionButton1, ActionButton2, BT4Button3 = object("ActionButton1"), object("ActionButton2"), object("BT4Button3")
StanceButton1 = object("StanceButton1")
-- Inside, the client's whisper limit applies.
instance = true
advance(30)
sent = {}
for i = 1, 20 do say(("D%d-OtherRealm"):format(i), ("Player-99-%06X"):format(16384 + i)) end
advance(1)
check(#whispers() >= 1 and #whispers() <= 6, "inside an instance whispers are paced (" .. #whispers() .. " in a second)")
instance = false
advance(31)
local function overlays()
    local found = {}
    for _, frame in ipairs(frames) do
        if frame.attributes.macrotext1 then found[#found + 1] = frame end
    end
    return found
end
local function borrowed() local n = 0 for _ in pairs(overrides) do n = n + 1 end return n end
local function macroFor(key) return HonorBoundReflagButton.attributes["*macrotext-" .. overrides[key].button] end
local function clicks(macro, name)
    local _, n = (macro or ""):gsub("/click " .. name .. " ", "")
    return n
end
local function flagsThenPresses(key, name)
    local macro = macroFor(key)
    return macro and macro:find("^/pvp\n") and clicks(macro, name) > 0
end
local function setFlag(on) desired, units.player.flagged = on, on event("PLAYER_FLAGS_CHANGED", "player") end

setFlag(true)
SlashCmdList.HONORBOUND("swear")
check(HonorBoundCharDB.sworn, "sworn again for the reflag checks")
instance = true
event("PLAYER_ENTERING_WORLD")
setFlag(false)
check(borrowed() == 0 and not prompt.shown, "inside a dungeon: no borrowed keys, no popup")
check(playerBadge().shown, "inside a dungeon: unflagged, but your crest stays")
statusResult = 0 advance(11) event("GROUP_ROSTER_UPDATE")
check(lastSent():find("|1|"), "inside a dungeon: you still announce yourself as sworn")
units.target = { guid = other, flagged = false, faction = units.player.faction, name = "Dungeon", realm = "Mate" }
peer(true) event("PLAYER_TARGET_CHANGED")
check(targetBadge().shown, "inside a dungeon: an unflagged sworn peer keeps the crest")
advance(A.GRACE + 30)
check(HonorBoundCharDB.sworn, "dungeon time doesn't run the countdown down")
instance = false
event("PLAYER_ENTERING_WORLD")
check(not playerBadge().shown and not targetBadge().shown, "outside, unflagged: no crests until the flag is back")
check(borrowed() > 0 and overrides["1"].name == "HonorBoundReflagButton", "leaving borrows the bar keys")
check(not prompt.shown, "no popup while the keys are borrowed")
check(flagsThenPresses("1", "ActionButton1"), "key 1 flags, then presses its own button")
check(flagsThenPresses("SHIFT-Q", "ActionButton2"), "second binding of a bar button")
check(flagsThenPresses("3", "BT4Button3"), "bar addon button through its CLICK binding")
check(clicks(macroFor("Z"), "StanceButton1") == 1, "stance buttons get one click, not two")
check(overrides["W"] == nil, "movement keys are never borrowed")
local clickOverlays = overlays()
local overlayHost = clickOverlays[1].parent
check(overlayHost.shown, "click overlays shown while armed")
local overBT4
for _, overlay in ipairs(clickOverlays) do
    if clicks(overlay.attributes.macrotext1, "BT4Button3") > 0 then overBT4 = overlay end
end
check(overBT4 and overBT4.attributes.macrotext2:find("/click BT4Button3 RightButton", 1, true), "right click passes through as a right click")
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
check(borrowed() > 0 and overlayHost.shown, "borrowed again after combat")
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
setFlag(false)
check(borrowed() > 0 and prompt.shown, "manual unflag: popup at once, keys borrowed")
setFlag(true)
-- Flag lost to a zone change: keys first, popup after the delay (30 s).
instance = true
event("PLAYER_ENTERING_WORLD")
setFlag(false)
advance(2)
instance = false
event("PLAYER_ENTERING_WORLD")
advance(1)
check(borrowed() > 0 and not prompt.shown, "after a dungeon: keys borrowed, no popup yet")
advance(31)
check(prompt.shown and borrowed() > 0, "popup after 30 s, keys still borrowed")
setFlag(true)
check(borrowed() == 0 and not prompt.shown, "flagging any other way hands the keys back")
SlashCmdList.HONORBOUND("autoflag off")
setFlag(false)
check(borrowed() == 0 and prompt.shown, "autoflag off: popup, no borrowed keys")
SlashCmdList.HONORBOUND("autoflag on")
check(borrowed() > 0, "autoflag on borrows the keys")
setFlag(true)
check(borrowed() == 0, "and hands them back once flagged")

-- Forever names: whispers to "First Surname-Realm" bounce; replies go to "First-Surname".
advance(400)
sent = {}
local fg = "Player-97-F0F001"
players[fg] = { name = "Aninja Rppvp", realm = "ClassicBetaPvE" }
addon("WQ|1|" .. fg .. "|1|20|0.4.0", "Aninja Rppvp-ClassicBetaPvE")
advance(2)
check(#whispers("Aninja-Rppvp") == 1 and #whispers("Aninja Rppvp-ClassicBetaPvE") == 0, "reply goes to First-Surname, not First Surname-Realm")
check(HonorBoundDB.likely[fg] and HonorBoundDB.likely[fg].name == "Aninja-Rppvp", "remembered under the whisperable name")

sent = {}
local both = "Player-97-F0F003"
units.mouseover = { guid = both, flagged = true, faction = units.player.faction, name = "Both", realm = "Sides" }
event("UPDATE_MOUSEOVER_UNIT")
probeSent("Both-Sides")
addon("WQ|1|" .. both .. "|1|20|0.4.0", "Both Sides-ClassicBetaPvE")
advance(2)
local replied = false
for _, m in ipairs(whispers("Both-Sides")) do replied = replied or m.message:find("^WR|") ~= nil end
check(replied, "a probe crossing ours still gets a reply")

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

sent = {}
local gone = "Player-97-F0F004"
addon("WQ|1|" .. gone .. "|0|0|0.4.0", "Gone Away-ClassicBetaPvE")
advance(2)
check(systemFilters.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", "No player named 'Gone-Away' is currently playing.") == true, "bounced reply error hidden")

-- Saved oath status: a remembered sworn player's crest shows while a re-check goes out.
advance(400)
sent = {}
local cg = "Player-96-C0C001"
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
advance(31)
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(plate.UnitFrame.HonorBoundCrest.shown, "one missed re-check keeps the crest")
sent = {}
probeSent("Cache-Dname")
advance(31)
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(not plate.UnitFrame.HonorBoundCrest.shown, "two missed re-checks drop it")
local cn = "Player-96-C0C002"
HonorBoundDB.likely[cn] = { name = "Gave-Up", seen = time(), sworn = true }
units.nameplate1 = { guid = cn, flagged = true, faction = units.player.faction, name = "Gave", realm = "Up" }
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
addon("WR|1|" .. cn .. "|0|0|0.4.3", "Gave Up-ClassicBetaPvE")
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(not plate.UnitFrame.HonorBoundCrest.shown, "a 'not sworn' answer replaces the saved status")
units.nameplate1 = nil

-- Away protection: unflagged and idle, the grace countdown waits.
SlashCmdList.HONORBOUND("autoflag off")
HonorBoundCharDB.sworn = true
moving = false
setFlag(false)
advance(A.GRACE + 60)
check(HonorBoundCharDB.sworn, "idle while unflagged: the oath holds past the grace period")
moving = true
advance(A.GRACE - 60)
check(HonorBoundCharDB.sworn, "active again: the countdown resumes from where it stopped")
advance(70)
check(not HonorBoundCharDB.sworn, "and breaks the oath once the rest runs out")
HonorBoundCharDB.sworn, HonorBoundCharDB.graceLeft = true, nil
setFlag(true)
moving = false
setFlag(false)
for _ = 1, A.GRACE + 5 do
    event("UNIT_SPELLCAST_SUCCEEDED", "player")
    advance(1)
end
check(not HonorBoundCharDB.sworn, "casting while standing still keeps the countdown running")
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

-- Pledge level in the tooltip, and never above the player's current level.
local function tooltipFor(guid, name, realm)
    units.target = { guid = guid, flagged = true, faction = units.player.faction, name = name, realm = realm }
    tooltipLines = {}
    tooltipCallback(GameTooltip)
    return table.concat(tooltipLines, " / ")
end
local tl = "Player-96-C0C010"
players[tl] = { name = "Tip Level", realm = "ClassicBetaPvE" }
addon("WQ|1|" .. tl .. "|1|12|0.4.3", "Tip Level-ClassicBetaPvE")
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

-- Scenarios needing a fresh client, each in its own process (tests/scenario.lua).
local lua = arg and arg[-1] or "luajit"
local scenarios = {"renounce", "idle_reset", "resurrect_crest", "inside", "options", "party", "remember", "options_broken"}
for _, name in ipairs(scenarios) do
    local ok = os.execute(lua .. " tests/scenario.lua " .. name .. " >/dev/null")
    check(ok == true or ok == 0, "scenario " .. name .. " (luajit tests/scenario.lua " .. name .. ")")
end

-- Nameplates the game never announced still get a crest, and one failing
-- nameplate doesn't stop the others.
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
check(printed("broken plate") == 1, "a failing nameplate is reported once, not every second (" .. printed("broken plate") .. ")")
C_NamePlate = realPlates
units.nameplate2, units.nameplate3 = nil, nil
event("NAME_PLATE_UNIT_REMOVED", "nameplate2")
event("NAME_PLATE_UNIT_REMOVED", "nameplate3")
SlashCmdList.HONORBOUND("sim off")
-- Empty party frames (no unit) must not stop nameplates updating.
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
check(printed("broken tick") == 1, "a broken tick is reported once (" .. printed("broken tick") .. ")")
local later = plate.UnitFrame.HonorBoundCrest
check(later.shown and later.desaturated and later.tint[1] < 0.5, "the nameplate still redraws (dark grey) while the tick is broken")
C_ChatInfo.InChatMessagingLockdown = realLockdown
SlashCmdList.HONORBOUND("debug off")
print("Passed " .. assertions .. " assertions; scenarios: " .. table.concat(scenarios, ", ") .. ".")
