-- Someone edited a number by hand: the hash no longer matches.
HonorBoundCharDB = {sworn = true, pledgedSinceLevel = 10, saveSeq = 2, verify = {since = 0, seen = 100, untracked = 4000}}
local edited = A.EncodeSave(me, {level = 10, since = 0, seen = 100, untracked = 4000, n = 9}):gsub("u=4000;", "u=0;")
macros[121] = {name = A.SAVE_NAME, perCharacter = true, body = edited}
assert(A.DecodeSave(me, edited) == nil and select(2, A.DecodeSave(me, edited)) == "altered", "an edited line is rejected")
assert(A.DecodeSave("Player-70-0FFFFF", A.EncodeSave(me, {level = 10, since = 0, seen = 0, untracked = 0, n = 1})) == nil,
    "a macro copied to another character is rejected")
event("PLAYER_LOGIN")
event("UPDATE_MACROS")
advance(1)
assert(HonorBoundCharDB.verify.untracked == 4000, "this computer's record stands")
assert(table.concat(debugLines, "\n"):find("was edited, so it was ignored and rewritten from this computer", 1, true), "and says so")
local saved = A.ReadSave(me)
assert(saved and saved.untracked == 4000, "the macro is rewritten correctly")
-- Neighbouring values must not give neighbouring hashes.
local function differ(a, b) local n = 0 for i = 1, #a do if a:sub(i, i) ~= b:sub(i, i) then n = n + 1 end end return n end
local d = differ(A.SaveSeal(me, "l=10;s=0;p=100;u=4000;n=9"), A.SaveSeal(me, "l=10;s=0;p=100;u=4001;n=9"))
assert(d >= 10, "a one-second change scrambles the hash (" .. d .. " of 16 differ)")
