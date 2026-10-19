-- Swearing starts a verified record once /played is known; it tracks the session.
local shown = 0
ChatFrame_DisplayTimePlayed = function() shown = shown + 1 end
setup()
assert(HonorBoundCharDB.verify == nil, "no record until /played is known")
assert(playedRequests == 1, "/played is asked for once after login")
event("TIME_PLAYED_MSG", 36000, 600)
ChatFrame_DisplayTimePlayed()
assert(shown == 0, "our own /played request isn't printed in chat")
local record = HonorBoundCharDB.verify
assert(record and record.since == 36000 and record.untracked == 0, "verification starts at the pledge")
advance(100)
assert(math.abs(record.seen - 36100) <= 1, "the record follows the session (" .. record.seen .. ")")
advance(2)
ChatFrame_DisplayTimePlayed()
assert(shown == 1, "typing /played yourself still prints")
debugLines = {}
SlashCmdList.HONORBOUND("")
local said = table.concat(debugLines, "\n")
assert(said:find("Verified", 1, true) and said:find("missed 0 s of your play since the pledge (2 h 00 min allowed)", 1, true), said)
SlashCmdList.HONORBOUND("renounce confirm")
assert(HonorBoundCharDB.verify == nil, "breaking the oath clears the record")
