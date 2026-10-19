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
