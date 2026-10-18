-- From Sol's 0.4.4 review.
setup()
setFlag(false)
print("Before renounce borrowed", borrowed())
SlashCmdList.HONORBOUND("renounce confirm")
advance(5)
print("After renounce sworn, borrowed, prompt", HonorBoundCharDB.sworn, borrowed(), prompt.shown)
assert(borrowed() == 0, "renouncing must restore action keys")
