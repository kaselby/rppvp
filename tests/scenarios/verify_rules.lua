-- The allowance rule and small gaps, straight from Verify.lua.
local r = A.NewVerify(0)
assert(A.VerifyAllowance(r, 3600) == 7200, "early on: the 2 h minimum")
assert(A.VerifyAllowance(r, 500 * 3600) == 10 * 3600, "after 500 h: 2% = 10 h")
r.seen = 500 * 3600 - 9 * 3600
local gap, over = A.AssessVerify(r, 500 * 3600)
assert(gap == 9 * 3600 and not over, "9 h untracked after 500 h of play is within 2%")
local small = A.NewVerify(1000)
gap = A.AssessVerify(small, 1000 + 120)
assert(gap == 0 and small.untracked == 0 and small.seen == 1120, "gaps of 2 min or less are ignored")
assert(A.Duration(45) == "45 s" and A.Duration(720) == "12 min" and A.Duration(7500) == "2 h 05 min", "durations read naturally")
local early = {since = 0, seen = 0, untracked = 0}
gap, over = A.AssessVerify(early, 3 * 3600)
assert(over, "3 h untracked early on is over the 2 h minimum")
