-- The break happened here but never reached the macro (combat, then a
-- reload): this computer's counter is higher, so the break stands.
HonorBoundCharDB = {sworn = false, saveSeq = 6}
macros[121] = {name = A.SAVE_NAME, perCharacter = true,
    body = A.EncodeSave(me, {level = 14, since = 1000, seen = 5000, untracked = 0, n = 5})}
event("PLAYER_LOGIN")
event("UPDATE_MACROS")
advance(1)
assert(HonorBoundCharDB.sworn == false, "the unsaved break isn't undone")
local saved = A.ReadSave(me)
assert(saved and saved.level == 0 and saved.n > 6, "and is written to the macro now")
