-- Renouncing while unflagged hands the borrowed keys back.
setup()
setFlag(false)
assert(borrowed() > 0, "unflagged: keys borrowed")
SlashCmdList.HONORBOUND("renounce confirm")
advance(5)
assert(borrowed() == 0, "renouncing must restore action keys")
