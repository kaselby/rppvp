-- Pledge verification: was HonorBound running for all the play since the
-- pledge? The server's /played keeps counting while the addon is off, so
-- unseen play shows up as a gap between the /played last saved and the one at
-- the next login. Crashes and other computers make innocent gaps, so some
-- untracked time is allowed; going over breaks the oath.
local _, A = ...

A.VERIFY_MIN = 2 * 3600   -- at least two hours untracked allowed
A.VERIFY_SHARE = 0.02     -- or 2% of the play since the pledge, if larger
A.VERIFY_IGNORE = 120     -- gaps this short are login timing, not play

-- Untracked time allowed so far.
function A.VerifyAllowance(record, played)
    return math.max(A.VERIFY_MIN, A.VERIFY_SHARE * math.max(0, played - record.since))
end

-- since: /played at the pledge; seen: /played as last recorded by the addon;
-- untracked: play it didn't see.
function A.NewVerify(played)
    return {since = played, seen = played, untracked = 0}
end

-- At login: counts the play the record missed, in place. Returns the gap
-- counted (0 if ignored) and whether the untracked total is over the allowance.
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
