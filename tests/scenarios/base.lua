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
-- Macros like the game: account ones at 1-120, character ones from 121.
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
macros = {}
function GetNumMacros() local n = 0 for _ in pairs(macros) do n = n + 1 end return 0, n end
function GetMacroIndexByName(name)
    for index, m in pairs(macros) do if m.name == name then return index end end
    return 0
end
function GetMacroInfo(index) local m = macros[index] if m then return m.name, m.icon, m.body end end
function CreateMacro(name, icon, body, perCharacter)
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

local function setup()
    event("PLAYER_LOGIN")
    advance(18)
    prompt.swear.scripts.OnClick()
    units.target, units.nameplate1 = nil, nil
end
local function addon(message, sender) event("CHAT_MSG_ADDON", A.PREFIX, message, "WHISPER", sender) end
local function shared(message) event("CHAT_MSG_ADDON", A.PREFIX, message, "CHANNEL", "Neighbour-Home") end
local function dump(prefix)
    for _, m in ipairs(sent) do if m.message:sub(1,#prefix)==prefix then print(m.route, m.message, m.target) end end
end
