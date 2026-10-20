-- Our dungeon keeps crests for players near us (in it with us), not for
-- party members outside.
setup()
inGuild = false
group = true
local g = 'Player-70-AA1006'
units.party1 = {guid = g, flagged = false, faction = 'Horde', name = 'Outside', realm = 'Surname', far = true}
PartyFrame = {MemberFrame1 = object('PartyMemberFrame1')}
PartyFrame.MemberFrame1.unit = 'party1'
PartyFrame.MemberFrame1.GetUnit = function() return 'party1' end
event('CHAT_MSG_ADDON', A.PREFIX, A.Encode(g, true), 'PARTY', 'Outside-Surname')
instance = true
event('PLAYER_ENTERING_WORLD')
assert(not PartyFrame.MemberFrame1.HonorBoundWidget.shown, "a party member outside, unflagged: no crest from our dungeon")
units.party1.far = nil -- they come in and reach us
event('PLAYER_ENTERING_WORLD')
assert(PartyFrame.MemberFrame1.HonorBoundWidget.shown, "next to us inside: the crest is back")
