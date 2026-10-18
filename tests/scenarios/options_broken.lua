-- A Settings API that doesn't behave as expected costs the page, not the addon.
Settings = {
    RegisterVerticalLayoutCategory = function() return {} end,
    RegisterProxySetting = function() error("unexpected signature") end,
    CreateCheckbox = function() end, CreateSlider = function() end,
    CreateSliderOptions = function() return {} end, RegisterAddOnCategory = function() end,
}
setup()
assert(#tickers == 1, "login finished: the 1 s ticker runs")
assert(HonorBoundCharDB.sworn and playerBadge().shown, "and the oath and crest work")
local said = false
for _, line in ipairs(debugLines) do said = said or line:find("settings page", 1, true) ~= nil end
assert(said, "the player is told the page is missing")
SlashCmdList.HONORBOUND("options")
print("options_broken: ok")
