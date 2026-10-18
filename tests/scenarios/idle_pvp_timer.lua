-- From Sol's 0.4.4 review.
setup()
SlashCmdList.HONORBOUND("autoflag off")
moving=false
setFlag(false)
-- A real /pvp starts the built-in five-minute flag cooldown.
for seconds=A.GRACE,1,-1 do
    timer=seconds*1000
    advance(1)
end
timer=nil
advance(1)
print("Sworn after AFK through PvP timer", HonorBoundCharDB.sworn)
assert(HonorBoundCharDB.sworn, "away protection should also pause grace while PvP timer runs")
