-- A new computer, sworn on another: swearing before the macro is read must
-- not overwrite it, and the macro's older level comes back.
local body = A.EncodeSave(me, {level = 12, since = 1000, seen = 5000, untracked = 0, n = 50})
macros[121] = {name = A.SAVE_NAME, perCharacter = true, body = body}
event("PLAYER_LOGIN")
assert(not prompt.shown, "no welcome before the macro is read")
SlashCmdList.HONORBOUND("swear")
advance(5)
assert(macros[121].body == body, "swearing early doesn't overwrite the macro")
advance(6) -- the 10 s fallback reads it
assert(HonorBoundCharDB.sworn and HonorBoundCharDB.pledgedSinceLevel == 12, "the macro's oath and level win")
assert(not prompt.shown, "and no welcome follows")
