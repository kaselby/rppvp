-- No free character macro slot: say so once, keep the pledge locally.
for i = 1, MAX_CHARACTER_MACROS do macros[120 + i] = {name = "Other" .. i, body = "/dance", perCharacter = true} end
setup()
event("TIME_PLAYED_MSG", 36000, 600)
advance(320)
assert(HonorBoundCharDB.sworn, "still sworn locally")
local _, n = table.concat(debugLines, "\n"):gsub("No free character macro slot for the HonorBound Save macro", "")
assert(n == 1, "said once (" .. n .. ")")
