-- Simulated client for tests/scenario.lua; each scenario is appended to it.
local A = {}
assert(loadfile("HonorBound/Core.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Pledge.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Verify.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Save.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Chat.lua"))("HonorBound", A)
local me, other = "Player-70-ABC123", "Player-70-DEF456"

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
local inGuild = true
function IsInGuild() return inGuild end
local lockdown, players, systemFilters, statusResult, whisperResult = false, {}, {}, nil, nil
function UnitIsPlayer(unit) return units[unit] ~= nil end
-- Near enough to see; a unit can say otherwise (a party member elsewhere).
function UnitIsVisible(unit) return units[unit] ~= nil and units[unit].far ~= true end
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
local playerBadge = function() return PlayerFrame.HonorBoundWidget end
local targetBadge = function() return TargetFrame.HonorBoundWidget end

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
local function borrowed() local n = 0 for _ in pairs(overrides) do n = n + 1 end return n end
local function setFlag(on) desired, units.player.flagged = on, on event("PLAYER_FLAGS_CHANGED", "player") end

local function setup()
    event("PLAYER_LOGIN")
    advance(18)
    prompt.swear.scripts.OnClick()
    units.target, units.nameplate1 = nil, nil
end
local function addon(message, sender) event("CHAT_MSG_ADDON", A.PREFIX, message, "WHISPER", sender) end
