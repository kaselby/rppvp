-- A renounce heard directly must not come back from the saved status after a reload.
setup()
local far = "Player-99-ABC001"
addon("WQ|1|"..far.."|1|20|0.4.4", "Far-Away")
units.target = {guid=far, flagged=true, faction="Horde", name="Far", realm="Away"}
event("PLAYER_TARGET_CHANGED")
assert(targetBadge().shown, "initial confirmed oath")
group=true
event("CHAT_MSG_ADDON", A.PREFIX, A.Encode(far, false), "PARTY", "Far-Away")
event("CHAT_MSG_ADDON", A.PREFIX, A.EncodePledge(far, nil), "PARTY", "Far-Away")
assert(not targetBadge().shown, "renounced oath received directly over party")
group=false
-- Reload: addon state is new, saved variables stay.
A={}
assert(loadfile("HonorBound/Core.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Pledge.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Chat.lua"))("HonorBound", A)
frames,tasks,tickers={},{},{}
PlayerFrame.HonorBoundWidget,TargetFrame.HonorBoundWidget,FocusFrame.HonorBoundWidget=nil,nil,nil
assert(loadfile("HonorBound/HonorBound.lua"))("HonorBound", A)
assert(loadfile("HonorBound/Options.lua"))("HonorBound", A)
events,prompt=frames[1],HonorBoundPrompt
event("PLAYER_LOGIN")
assert(not targetBadge().shown, "must not resurrect an oath already known to be renounced")
