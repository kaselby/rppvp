-- Chat only trusts and whispers our own faction:
-- the saved list is account-wide, so a Horde alt's knowledge mustn't give
-- an Alliance character an enemy crest or a whisper to the other faction.
units.player.faction = 'Alliance'
units.target, units.nameplate1 = nil, nil
local g = 'Player-70-AA1003'
players[g] = {name = 'Enemy Surname', realm = 'ClassicBetaPvE'} -- the base reports Orc
HonorBoundDB = {likely = {[g] = {name = 'Enemy-Surname', seen = time(), sworn = true}}}
event('PLAYER_LOGIN')
local args = {} args[12] = g
local shown = ChatFrameUtil.filter('CHAT_MSG_EMOTE', 'Enemy Surname-ClassicBetaPvE', unpack(args, 1, 12))
assert(not (shown and shown:find('Crest', 1, true)), "no saved crest for the other faction in chat")
sent = {}
event('CHAT_MSG_EMOTE', 'waves', 'Enemy Surname-ClassicBetaPvE', '', '', '', '', 0, 0, '', 0, 1, g)
advance(1)
for _, m in ipairs(sent) do assert(m.route ~= 'WHISPER', "no whisper to the other faction") end
-- Our own faction still gets both.
units.player.faction = 'Horde'
shown = ChatFrameUtil.filter('CHAT_MSG_EMOTE', 'Enemy Surname-ClassicBetaPvE', unpack(args, 1, 12))
assert(shown and shown:find('CrestHorde', 1, true), "same faction: the saved crest shows")
event('CHAT_MSG_EMOTE', 'waves', 'Enemy Surname-ClassicBetaPvE', '', '', '', '', 0, 0, '', 0, 1, g)
advance(1)
local asked = false
for _, m in ipairs(sent) do asked = asked or m.route == 'WHISPER' end
assert(asked, "and gets a whisper")
