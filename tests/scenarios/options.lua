-- 0.4.6: the settings page under Options > AddOns.
local registered, opened = {}, nil
local category = {GetID = function() return 42 end}
Settings = {
    VarType = {Boolean = "boolean", Number = "number"},
    RegisterVerticalLayoutCategory = function(name) category.name = name return category end,
    RegisterProxySetting = function(cat, variable, kind, name, default, get, set)
        local s = {variable = variable, kind = kind, name = name, default = default, get = get, set = set}
        registered[#registered + 1] = s
        return s
    end,
    CreateCheckbox = function(cat, setting) setting.control = "checkbox" end,
    CreateSliderOptions = function(min, max, step)
        return {min = min, max = max, step = step, SetLabelFormatter = function(self, _, f) self.format = f end}
    end,
    CreateSlider = function(cat, setting, options) setting.control, setting.options = "slider", options end,
    RegisterAddOnCategory = function(cat) category.addon = true end,
    OpenToCategory = function(id) opened = id end,
}
MinimalSliderWithSteppersMixin = {Label = {Right = 2}}
setup()
local function find(text)
    for _, s in ipairs(registered) do if s.name:find(text, 1, true) then return s end end
end
assert(category.addon and category.name == "HonorBound", "registered under Options > AddOns as HonorBound")
assert(#registered == 5, "five settings (" .. #registered .. ")")
for _, s in ipairs(registered) do assert(s.variable:find("^HONORBOUND_"), "setting names are namespaced") end
local autoflag, plates, chat = find("Reflag"), find("nameplates"), find("chat")
local size, delay = find("size"), find("Popup")
assert(autoflag.control == "checkbox" and plates.control == "checkbox" and chat.control == "checkbox", "three checkboxes")
assert(autoflag.get() and plates.get() and chat.get(), "all on by default")
assert(size.control == "slider" and size.options.min == 0.6 and size.options.max == 2 and size.get() == 1, "size slider, 0.6-2")
assert(delay.options.min == 10 and delay.options.max == 120 and delay.get() == 30 and delay.default == 30, "popup delay 10 s-2 min, 30 by default")
assert(delay.options.format(30) == "30 s" and delay.options.format(90) == "1 min 30 s" and delay.options.format(120) == "2 min", "delay reads as time")
assert(size.options.format(1.2) == "1.2", "size reads plainly")

-- The page and the slash commands write the same values.
plates.set(false)
assert(HonorBoundDB.plates == false, "nameplate box writes the saved setting")
SlashCmdList.HONORBOUND("plates")
assert(plates.get() == true, "and the box shows a slash command's change")
chat.set(false)
assert(HonorBoundDB.chatIcons == false, "chat box")
chat.set(true)
size.set(1.3000000001)
assert(HonorBoundDB.scale == 1.3 and playerBadge().scale == 1.3, "size applies at once, rounded to the step")
SlashCmdList.HONORBOUND("options")
assert(opened == 42, "/honor options opens the page")

-- Autoflag off from the page hands the keys back straight away.
setFlag(false)
assert(borrowed() == 5, "unflagged: keys borrowed")
autoflag.set(false)
assert(borrowed() == 0 and prompt.shown, "unticked: keys handed back, popup instead")
autoflag.set(true)
assert(borrowed() == 5, "ticked again: keys borrowed")
setFlag(true)

-- The delay is what the popup waits after a dungeon.
local function afterDungeon()
    instance = true
    event("PLAYER_ENTERING_WORLD")
    setFlag(false)
    advance(2)
    instance = false
    event("PLAYER_ENTERING_WORLD")
    advance(1)
end
delay.set(10)
afterDungeon()
assert(not prompt.shown, "no popup straight after a dungeon")
advance(10)
assert(prompt.shown, "popup after the 10 s chosen")
setFlag(true)
SlashCmdList.HONORBOUND("delay 120")
assert(delay.get() == 120, "/honor delay sets the same value")
SlashCmdList.HONORBOUND("delay 5")
assert(delay.get() == 120, "out of range is refused")
afterDungeon()
advance(100)
assert(not prompt.shown, "a 2 min delay holds the popup")
advance(20)
assert(prompt.shown, "and then it shows")
setFlag(true)
-- A manual unflag still asks at once, whatever the delay.
setFlag(false)
assert(prompt.shown, "turning the flag off yourself asks at once")
setFlag(true)

print("options: ok")
