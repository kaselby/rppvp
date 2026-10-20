-- /honor simfull: saves act as if the macros were full, to try the dialog.
setup()
event("TIME_PLAYED_MSG", 36000, 600)
advance(2)
SlashCmdList.HONORBOUND("simfull on")
local dialog = HonorBoundMacrosFull
assert(dialog and dialog.shown, "simfull on: the macros-full dialog at once")
dialog.retry.scripts.OnClick()
assert(dialog.shown, "Retry still fails")
SlashCmdList.HONORBOUND("simfull off")
dialog.retry.scripts.OnClick()
assert(not dialog.shown and A.ReadSave(me), "simfull off: Retry saves")
