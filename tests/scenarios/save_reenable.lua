-- Macro saving was off here while another computer kept saving: turning it
-- back on reads the macro before writing, so the newer copy isn't lost.
HonorBoundCharDB = {sworn = true, pledgedSinceLevel = 20, saveSeq = 1, macroSave = false}
local body = A.EncodeSave(me, {level = 14, since = 1000, seen = 5000, untracked = 0, n = 5})
macros[121] = {name = A.SAVE_NAME, perCharacter = true, body = body}
event("PLAYER_LOGIN")
event("UPDATE_MACROS")
assert(HonorBoundCharDB.pledgedSinceLevel == 20 and macros[121].body == body, "off: the macro is left alone")
SlashCmdList.HONORBOUND("save")
assert(HonorBoundCharDB.pledgedSinceLevel == 14 and A.ReadSave(me).level == 14, "on again: the newer macro wins")
