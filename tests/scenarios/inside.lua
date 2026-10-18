-- 0.4.6: a party member inside a dungeon keeps their crest for the ones
-- outside, from their own "I" message.
setup()
local mate = "Player-70-AAA777"
group = true
local function party(message) event("CHAT_MSG_ADDON", A.PREFIX, message, "PARTY", "Mate-Home") end
party(A.Encode(mate, true))
units.target = {guid = mate, flagged = false, faction = "Horde", name = "Mate", realm = "Home"}
event("PLAYER_TARGET_CHANGED")
assert(not targetBadge().shown, "outside, an unflagged sworn mate has no crest")
party(A.EncodeInside(mate, true))
assert(targetBadge().shown, "their word that they're inside brings it back")
party(A.EncodeInside(mate, false))
assert(not targetBadge().shown, "and their word that they've left takes it away")
party(A.EncodeInside(mate, true))
advance(149) party(A.Encode(mate, true)) event("PLAYER_TARGET_CHANGED")
assert(targetBadge().shown, "the word holds a while")
advance(2) party(A.Encode(mate, true)) event("PLAYER_TARGET_CHANGED")
assert(not targetBadge().shown, "and lapses without a fresh one")
event("CHAT_MSG_ADDON", A.PREFIX, A.EncodeInside(mate, true), "CHANNEL", "Mate-Home")
event("PLAYER_TARGET_CHANGED")
assert(not targetBadge().shown, "only a group member's word counts")
assert(A.DecodeInside(A.Encode(mate, true)) == nil and A.Decode(A.EncodeInside(mate, true)) == nil
    and A.DecodePledge(A.EncodeInside(mate, true)) == nil, "I is its own kind: S and P readers ignore it")

-- Our side: we tell the group while we're inside, and once when we leave.
local function insides(route)
    local found = {}
    for _, m in ipairs(sent) do
        if m.message:find("^I|") and (not route or m.route == route) then found[#found + 1] = m.message end
    end
    return found
end
advance(70)
assert(#insides() == 0, "outside, nothing about instances goes out")
sent = {}
instance = true
event("PLAYER_ENTERING_WORLD")
setFlag(false)
assert(#insides("PARTY") >= 1 and insides("PARTY")[1] == "I|1|" .. me .. "|1|" .. A.VERSION, "entering: the party hears we're inside")
assert(#insides("CHANNEL") == 0, "the realm channel doesn't")
sent = {}
advance(61)
assert(#insides("PARTY") >= 1, "and again with each announcement while inside")
sent = {}
instance = false
event("PLAYER_ENTERING_WORLD")
assert(#insides("PARTY") == 1 and insides("PARTY")[1]:find("|0|"), "leaving: one message saying we're out")
advance(70)
assert(#insides() == 1, "then nothing more")
print("inside: ok")
