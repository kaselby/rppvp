-- Options > AddOns > HonorBound. Every setting is also a slash command.
local _, A = ...

local POPUP_MIN, POPUP_MAX, POPUP_DEFAULT = 10, 120, 30
A.POPUP_MIN, A.POPUP_MAX, A.POPUP_DEFAULT = POPUP_MIN, POPUP_MAX, POPUP_DEFAULT

local function Seconds(value)
    value = math.floor(value + 0.5)
    if value < 60 then return value .. " s" end
    local minutes, seconds = math.floor(value / 60), value % 60
    return minutes .. " min" .. (seconds > 0 and (" " .. seconds .. " s") or "")
end
A.Seconds = Seconds

-- db: the saved settings; char: this character's. changed(key): called after
-- the page changes one.
function A.InstallOptions(db, char, changed)
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
        and Settings.CreateCheckbox and Settings.CreateSlider and Settings.RegisterAddOnCategory) then
        return
    end
    local category = Settings.RegisterVerticalLayoutCategory("HonorBound")
    local types = Settings.VarType or {Boolean = "boolean", Number = "number"}
    local function Setting(key, kind, name, default, get, set)
        return Settings.RegisterProxySetting(category, "HONORBOUND_" .. key:upper(), kind, name, default,
            get, function(value) set(value) changed(key) end)
    end
    local function Checkbox(key, name, default, get, set, tooltip)
        Settings.CreateCheckbox(category, Setting(key, types.Boolean, name, default, get, set), tooltip)
    end
    local function Slider(key, name, default, min, max, step, format, get, set, tooltip)
        local options = Settings.CreateSliderOptions(min, max, step)
        local labels = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
        if labels and options.SetLabelFormatter then options:SetLabelFormatter(labels.Right, format) end
        Settings.CreateSlider(category, Setting(key, types.Number, name, default, get, set), options, tooltip)
    end

    Checkbox("autoflag", "Reflag with your action bar keys", true,
        function() return db.autoReflag ~= false end,
        function(value) db.autoReflag = value and true or false end,
        "While you're sworn and unflagged, your next action bar key or click flags you again, then does what it normally does.")
    Checkbox("plates", "Crests on nameplates", true,
        function() return db.plates and true or false end,
        function(value) db.plates = value and true or false end,
        "Show the crest beside sworn players' names above their heads.")
    Checkbox("chat", "Crests in chat", true,
        function() return db.chatIcons ~= false end,
        function(value) db.chatIcons = value and true or false end,
        "Show the crest beside sworn players' names in chat.")
    Checkbox("macroSave", "Save your pledge in a character macro", true,
        function() return char.macroSave ~= false end,
        function(value) A.SetMacroSave(value) end,
        "Your pledge follows this character to other computers. Uses one character macro slot. This character only.")
    Slider("scale", "Crest size", 1, 0.6, 2, 0.1,
        function(value) return ("%.1f"):format(value) end,
        function() return db.scale end,
        function(value) db.scale = math.floor(value * 10 + 0.5) / 10 end,
        "Size of the crest on your portrait and on your target and focus.")
    Slider("popupDelay", "Popup after a dungeon", POPUP_DEFAULT, POPUP_MIN, POPUP_MAX, 5, Seconds,
        function() return db.popupDelay end,
        function(value) db.popupDelay = math.floor(value + 0.5) end,
        "Leaving a dungeon or raid unflags you. This is how long your action bar keys get to flag you again before the popup asks as well. If you turn the flag off yourself, the popup asks at once.")
    Settings.RegisterAddOnCategory(category)
    return category
end
