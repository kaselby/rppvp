-- Back after an hour of play HonorBound didn't see: counted, still verified.
HonorBoundCharDB = {sworn = true, pledgedSinceLevel = 10, verify = {since = 0, seen = 36000, untracked = 0, verified = true}}
event("PLAYER_LOGIN")
advance(6)
event("TIME_PLAYED_MSG", 36000 + 3600, 600)
local record = HonorBoundCharDB.verify
assert(record.untracked == 3600 and record.verified, "one hour counted, still within 2 h")
local said = table.concat(debugLines, "\n")
assert(said:find("didn't see 1 h 00 min of your play time since your last session", 1, true)
    and said:find("Untracked so far: 1 h 00 min of 2 h 00 min allowed.", 1, true), said)
-- Only the first /played of a session is assessed.
event("TIME_PLAYED_MSG", 36000 + 7200, 600)
assert(record.untracked == 3600, "a later /played (typed) isn't counted again")
