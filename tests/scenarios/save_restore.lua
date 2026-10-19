-- Another computer: no local data; the macro holds the oath and verification.
macros[121] = {name = A.SAVE_NAME, perCharacter = true,
    body = A.EncodeSave(me, {level = 14, since = 1000, seen = 5000, untracked = 60, n = 5})}
event("PLAYER_LOGIN")
event("UPDATE_MACROS")
assert(HonorBoundCharDB.sworn == true and HonorBoundCharDB.pledgedSinceLevel == 14, "the oath comes back from the macro")
local v = HonorBoundCharDB.verify
assert(v and v.since == 1000 and v.seen == 5000 and v.untracked == 60, "and its verification")
assert(playedRequests == 1, "/played is asked for once the record is settled")
event("TIME_PLAYED_MSG", 5030, 600)
local said = table.concat(debugLines, "\n")
assert(said:find("Restored your oath from the HonorBound Save macro: pledged since level 14.", 1, true), said)
assert(not said:find("didn't see", 1, true), "no gap: the macro was up to date")
local count = 0 for _ in pairs(macros) do count = count + 1 end
assert(count == 1, "no second macro is made")
