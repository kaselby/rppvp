-- A whisper out to someone is answered by their status over the party: no
-- timeout, no false "no addon".
setup()
inGuild = false
local g = 'Player-70-AA1002'
units.target = {guid = g, flagged = true, faction = 'Horde', name = 'Group', realm = 'Member'}
event('PLAYER_TARGET_CHANGED')
advance(1)
event('CHAT_MSG_ADDON', A.PREFIX, A.Encode(g, false), 'PARTY', 'Group-Member')
advance(31)
assert(not HonorBoundDB.noAddon[g], "their party status answered our whisper: not marked as without the addon")
