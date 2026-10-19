-- A Settings API that doesn't behave as expected costs the page, not the addon.
Settings = {
    RegisterVerticalLayoutCategory = function() return {} end,
    RegisterProxySetting = function() error("unexpected signature") end,
    CreateCheckbox = function() end, CreateSlider = function() end,
    CreateSliderOptions = function() return {} end, RegisterAddOnCategory = function() end,
}
setup()
assert(#tickers > 0, "login finished: the ticker runs")
assert(HonorBoundCharDB.sworn and playerBadge().shown, "and the oath and crest work")
SlashCmdList.HONORBOUND("options")
print("options_broken: ok")
