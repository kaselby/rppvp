-- A new grace period must not inherit an earlier one's away pause.
setup()
SlashCmdList.HONORBOUND("autoflag off")
setFlag(false)
advance(240)
moving = false
advance(60)
event("PLAYER_LOGOUT")
setFlag(true)
instance = true
setFlag(false)
advance(60)
instance = false
event("PLAYER_ENTERING_WORLD")
event("PLAYER_LOGOUT")
moving = true
advance(31)
assert(HonorBoundCharDB.sworn, "new grace should not inherit previous idle freeze")
