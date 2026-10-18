-- From Sol's 0.4.4 review.
setup()
local far = "Player-99-ABC001"
units.mouseover={guid=far, flagged=true, faction="Horde",name="Far",realm="Away"}
event("UPDATE_MOUSEOVER_UNIT")
advance(1)
-- Crossed probes: their WQ has their old oath. They renounce before their
-- queued WR to our probe is sent, so WR carries the newer status.
addon("WQ|1|"..far.."|1|20|0.4.4", "Far-Away")
addon("WR|1|"..far.."|0|0|0.4.4", "Far-Away")
sent={}
advance(15)
print("Latest directly learned oath", tostring(HonorBoundDB.likely[far].sworn))
dump("F|")
for _,m in ipairs(sent) do assert(not m.message:find("|Far%-Away|1|"), "must not publish superseded sworn status") end
