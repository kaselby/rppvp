-- Played on the other computer since: its macro is newer than this copy, so
-- that session isn't counted as a gap here.
HonorBoundCharDB = {sworn = true, pledgedSinceLevel = 14, saveSeq = 3, verify = {since = 1000, seen = 4000, untracked = 0}}
macros[121] = {name = A.SAVE_NAME, perCharacter = true,
    body = A.EncodeSave(me, {level = 14, since = 1000, seen = 5000, untracked = 0, n = 5})}
event("PLAYER_LOGIN")
event("UPDATE_MACROS")
event("TIME_PLAYED_MSG", 5030, 600)
assert(HonorBoundCharDB.verify.seen >= 5030 and HonorBoundCharDB.verify.untracked == 0, "the newer macro wins")
assert(not table.concat(debugLines, "\n"):find("didn't see", 1, true), "and the other computer's session isn't a gap")
assert(HonorBoundCharDB.saveSeq == 5, "this computer takes the macro's counter")
