-- Swearing saves; the record is rewritten every 2 minutes; breaking saves
-- "not sworn" (never deletes); combat waits.
setup()
event("TIME_PLAYED_MSG", 36000, 600)
advance(1)
local m = macros[121]
local saved = A.ReadSave(me)
assert(m and m.name == A.SAVE_NAME and m.perCharacter and saved and saved.level == 20, "swearing makes a character macro")
assert(m.body:find("^#HonorBound save data%. Do not edit or delete this macro"), "with the warning comment first")
assert(#m.body <= 255, "within the macro size limit (" .. #m.body .. ")")
for line in m.body:gmatch("[^\n]+") do assert(line:sub(1, 1) == "#", "every line is a comment: " .. line) end
local firstSeen = A.ReadSave(me).seen
advance(121)
assert(A.ReadSave(me).seen >= firstSeen + 110, "the record is rewritten every 2 minutes")
combat = true
SlashCmdList.HONORBOUND("renounce confirm")
advance(3)
assert(A.ReadSave(me).level == 20, "no macro edits in combat")
combat = false
advance(1)
assert(A.ReadSave(me).level == 0, "after combat the break is saved, macro kept")
