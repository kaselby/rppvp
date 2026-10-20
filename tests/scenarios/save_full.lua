-- No free character macro slot: a dialog like the pledge prompt asks for one
-- to be cleared; Retry saves once there's room. Full means all of
-- Forever's slots, not Classic's 18.
for i = 1, CHARACTER_SLOTS do macros[120 + i] = {name = "Other" .. i, body = "/dance", perCharacter = true} end
setup()
event("TIME_PLAYED_MSG", 36000, 600)
advance(2)
assert(HonorBoundCharDB.sworn, "still sworn locally")
local dialog = HonorBoundMacrosFull
assert(dialog and dialog.shown, "swearing with full macros shows the dialog")
dialog.retry.scripts.OnClick()
assert(dialog.shown, "Retry with the macros still full keeps the dialog up")
macros[121] = nil -- the player deletes one
dialog.retry.scripts.OnClick()
assert(not dialog.shown and A.ReadSave(me) and A.ReadSave(me).level == 20, "Retry saves once there's room")
assert(table.concat(debugLines, "\n"):find("Your pledge is saved in the HonorBound Save macro.", 1, true), "and says so")

-- Not now: after a confirmation, macro saving is off for this character and
-- the dialog stops coming back; /honor save turns it on again.
macros[121] = {name = "Other1", body = "/dance", perCharacter = true} -- full again, save gone
dialog.retry.scripts.OnClick()
assert(dialog.shown, "full again")
dialog.later.scripts.OnClick()
local confirm = StaticPopupDialogs[shownPopup]
assert(not dialog.shown and confirm, "Not now asks to confirm")
confirm.OnCancel(nil, nil, "clicked")
assert(dialog.shown and HonorBoundCharDB.macroSave ~= false, "Cancel goes back to the dialog")
dialog.later.scripts.OnClick()
StaticPopupDialogs[shownPopup].OnAccept()
assert(HonorBoundCharDB.macroSave == false and not dialog.shown, "confirmed: macro saving off")
advance(A.SAVE_EVERY + 10)
assert(not dialog.shown, "and the dialog doesn't come back")
macros[121] = nil
SlashCmdList.HONORBOUND("save")
assert(HonorBoundCharDB.macroSave ~= false and A.ReadSave(me), "/honor save turns it back on and saves")
