-- Pledge verification: was HonorBound running for all the play since the
-- pledge? /played is counted by Blizzard's servers and keeps going while the
-- addon is off, so play the addon didn't see shows up as a gap between the
-- /played it last saved and the /played at the next login. Disabling the
-- addon, unflagging, reflagging and re-enabling can't hide that.
--
-- Gaps also happen innocently (a crash or Alt-F4 loses the end of a session,
-- another computer without the addon), so some untracked time is allowed:
-- the larger of VERIFY_MIN seconds or VERIFY_SHARE of the play since the
-- pledge. Going over breaks the oath.
local _, A = ...

A.VERIFY_MIN = 2 * 3600   -- at least two hours untracked allowed
A.VERIFY_SHARE = 0.02     -- or 2% of the play since the pledge, if larger
A.VERIFY_IGNORE = 120     -- gaps this short are login timing, not play

-- Untracked time allowed so far.
function A.VerifyAllowance(record, played)
    return math.max(A.VERIFY_MIN, A.VERIFY_SHARE * math.max(0, played - record.since))
end

-- A fresh record at the pledge: since = /played then, seen = /played as
-- last recorded by the addon, untracked = time it didn't see.
function A.NewVerify(played)
    return {since = played, seen = played, untracked = 0}
end

-- At login, with the server's /played: count the play the record missed.
-- Returns the gap counted (0 if ignored) and whether the untracked total is
-- now over the allowance. The record is updated in place.
function A.AssessVerify(record, played)
    local gap = played - record.seen
    record.seen = math.max(record.seen, played)
    if gap <= A.VERIFY_IGNORE then return 0, false end
    record.untracked = record.untracked + gap
    return gap, record.untracked > A.VerifyAllowance(record, played)
end

-- "2 h 05 min", "12 min", "45 s".
function A.Duration(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then return seconds .. " s" end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return minutes .. " min" end
    return ("%d h %02d min"):format(math.floor(minutes / 60), minutes % 60)
end
