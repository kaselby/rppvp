-- The settings page under Options > AddOns.
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
local autoflag, plates, chat = find("Reflag"), find("nameplates"), find("chat")
local size, delay = find("size"), find("Popup")
assert(autoflag.get() and plates.get() and chat.get(), "all on by default")

-- The page and the slash commands write the same values.
plates.set(false)
assert(HonorBoundDB.plates == false, "nameplate box writes the saved setting")
SlashCmdList.HONORBOUND("plates")
assert(plates.get() == true, "and the box shows a slash command's change")
size.set(1.3000000001)
assert(HonorBoundDB.scale == 1.3 and playerBadge().scale == 1.3, "size applies at once, rounded to the step")
SlashCmdList.HONORBOUND("options")
assert(opened == 42, "/honor options opens the page")

setFlag(false)
assert(borrowed() > 0, "unflagged: keys borrowed")
autoflag.set(false)
assert(borrowed() == 0 and prompt.shown, "unticked: keys handed back, popup instead")
autoflag.set(true)
assert(borrowed() > 0, "ticked again: keys borrowed")
setFlag(true)

delay.set(10)
instance = true
event("PLAYER_ENTERING_WORLD")
setFlag(false)
advance(2)
instance = false
event("PLAYER_ENTERING_WORLD")
advance(1)
assert(not prompt.shown, "no popup straight after a dungeon")
advance(10)
assert(prompt.shown, "popup after the 10 s chosen")
setFlag(true)
SlashCmdList.HONORBOUND("delay 120")
assert(delay.get() == 120, "/honor delay sets the same value")
SlashCmdList.HONORBOUND("delay 5")
assert(delay.get() == 120, "out of range is refused")
print("options: ok")
