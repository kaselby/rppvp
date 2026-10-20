-- Over the allowance: the oath breaks, the save macro says so, and a new
-- oath starts a fresh record.
HonorBoundCharDB = {sworn = true, pledgedSinceLevel = 10, verify = {since = 0, seen = 36000, untracked = 5400}}
setFlag(true)
event("PLAYER_LOGIN")
event("UPDATE_MACROS")
event("TIME_PLAYED_MSG", 36000 + 3600, 600)
assert(HonorBoundCharDB.sworn == false and HonorBoundCharDB.verify == nil, "2 h 30 min untracked > 2 h: the oath breaks")
assert(table.concat(debugLines, "\n"):find("Oath broken: HonorBound missed 2 h 30 min of your play time, more than the 2 h 00 min allowed", 1, true),
    table.concat(debugLines, "\n"))
advance(1)
assert(A.ReadSave(me).level == 0, "and the save macro says not sworn")
SlashCmdList.HONORBOUND("swear")
assert(HonorBoundCharDB.verify and HonorBoundCharDB.verify.untracked == 0 and math.abs(HonorBoundCharDB.verify.since - (36000 + 3600)) <= 2,
    "a new oath starts a fresh record")
