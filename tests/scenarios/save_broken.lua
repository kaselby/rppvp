-- Broken on another computer: the newer macro says not sworn.
HonorBoundCharDB = {sworn = true, pledgedSinceLevel = 10, saveSeq = 3, verify = {since = 0, seen = 100, untracked = 0}}
macros[121] = {name = A.SAVE_NAME, perCharacter = true,
    body = A.EncodeSave(me, {level = 0, since = 0, seen = 0, untracked = 0, n = 5})}
event("PLAYER_LOGIN")
advance(11) -- no UPDATE_MACROS this time: the 10 s fallback reads it
assert(HonorBoundCharDB.sworn == false and HonorBoundCharDB.verify == nil, "the break carries over")
assert(table.concat(debugLines, "\n"):find("says your oath was broken on another computer", 1, true), "and says so")
assert(not playerBadge().shown, "no crest")
