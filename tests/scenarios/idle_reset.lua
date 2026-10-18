-- From Sol's 0.4.4 review.
setup()
SlashCmdList.HONORBOUND("autoflag off")
setFlag(false)
advance(240)
moving = false
advance(60)
event("PLAYER_LOGOUT")
print("First grace frozen at", HonorBoundCharDB.graceLeft)
setFlag(true)
instance = true
setFlag(false)
advance(60)
instance = false
event("PLAYER_ENTERING_WORLD")
event("PLAYER_LOGOUT")
print("New grace after dungeon", HonorBoundCharDB.graceLeft)
moving=true
advance(31)
print("Sworn 31 active seconds into the new grace", HonorBoundCharDB.sworn)
assert(HonorBoundCharDB.sworn, "new grace should not inherit previous idle freeze")
