-- Forever has more character macro slots than Classic: 18 in use isn't full.
for i = 1, MAX_CHARACTER_MACROS do macros[120 + i] = {name = "Other" .. i, body = "/dance", perCharacter = true} end
-- An account macro too, so character indexes aren't the only ones.
macros[1] = {name = "Mount", body = "/cast Horse"}
setup()
event("TIME_PLAYED_MSG", 36000, 600)
advance(2)
assert(not (HonorBoundMacrosFull and HonorBoundMacrosFull.shown), "no macros-full dialog with free Forever slots")
assert(A.ReadSave(me) and A.ReadSave(me).level == 20, "the save went into a character slot past 18")
