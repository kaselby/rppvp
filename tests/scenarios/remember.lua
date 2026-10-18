-- 0.4.7: a sworn player heard directly (party, guild, realm channel) is
-- remembered, so their crest is back at once after a relog.
setup()
local mate = "Player-70-AAA555"
group = true
units.target = {guid = mate, flagged = true, faction = "Horde", name = "Mate", realm = "Home"}
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(mate, true), "PARTY", "Mate Surname")
event("CHAT_MSG_ADDON", A.PREFIX, A.EncodePledge(mate, 14), "PARTY", "Mate Surname")
event("PLAYER_TARGET_CHANGED")
assert(targetBadge().shown, "heard over party: crest")
local saved = HonorBoundDB.likely[mate]
assert(saved and saved.sworn and saved.level == 14 and saved.name == "Mate-Surname", "and remembered, with a whisperable name")
local unsworn = "Player-70-AAA556"
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(unsworn, false), "CHANNEL", "Plain-Home")
assert(HonorBoundDB.likely[unsworn] == nil, "unsworn players aren't added")
-- Relog: addon state is new, saved variables stay.
A = {}
assert(loadfile("HonorBound/Core.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Pledge.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Chat.lua"))("HonorBound", A)
frames, tasks, tickers = {}, {}, {}
PlayerFrame.HonorBoundWidget, TargetFrame.HonorBoundWidget, FocusFrame.HonorBoundWidget = nil, nil, nil
assert(loadfile("HonorBound/HonorBound.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Options.lua"))("HonorBound", A)
events, prompt = frames[1], HonorBoundPrompt
event("PLAYER_LOGIN")
assert(targetBadge().shown, "after a relog: crest at once, before they announce again")
units.target.flagged = false
event("PLAYER_TARGET_CHANGED")
assert(not targetBadge().shown, "the saved status still needs the live flag")
print("remember: ok")
