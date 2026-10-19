-- A broken oath leaves an oathbreaker mark for a day of server time, kept in
-- both the saved variables and the save macro, so losing either one (an
-- uninstall that wipes WTF, a deleted macro) doesn't clear it. Others see it.
setup()
event("TIME_PLAYED_MSG", 36000, 600)
advance(2)
SlashCmdList.HONORBOUND("renounce confirm")
advance(2)
local mark = HonorBoundCharDB.brokenUntil
assert(A.BrokenLeft(mark), "renouncing leaves the mark")
assert(A.ReadSave(me).broken == mark, "the save macro holds it")

-- Saved variables wiped (addon removed with its WTF data), macro kept.
HonorBoundCharDB = nil
A.saveSynced = nil -- a fresh login reads the macro again
event("PLAYER_LOGIN")
event("UPDATE_MACROS")
assert(HonorBoundCharDB.brokenUntil == mark, "the mark comes back from the macro")
SlashCmdList.HONORBOUND("swear")
assert(not HonorBoundCharDB.sworn and not HonorBoundCharDB.joining, "still can't swear again")

-- Macro deleted, saved variables kept: the mark stays and is written back.
macros[121] = nil
A.saveSynced = nil
event("PLAYER_LOGIN")
event("UPDATE_MACROS")
advance(2)
assert(A.BrokenLeft(HonorBoundCharDB.brokenUntil), "the mark stays from the saved variables")
assert(A.ReadSave(me) and A.ReadSave(me).broken == mark, "and goes back into a new macro")

-- Another player's mark: heard in a whisper, shown on tooltip and nameplate,
-- remembered across a reload, cleared once they're heard sworn again.
local them = "Player-70-B10E"
players[them] = {name = "Snap", realm = "Home"}
units.nameplate1 = {guid = them, flagged = false, faction = "Horde", name = "Snap", realm = "Home"}
units.target = units.nameplate1
addon(A.EncodeBroken(them, GetServerTime() + 3600), "Snap-Home")
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(plate.UnitFrame.HonorBoundCrest.shown and plate.UnitFrame.HonorBoundCrest.texturePath:find("Broken", 1, true), "their nameplate shows the broken sword")
tooltipLines = {}
tooltipCallback(GameTooltip)
local lines = table.concat(tooltipLines, " / ")
assert(lines:find("Oathbreaker", 1, true) and lines:find("1 h 00 min", 1, true), lines)
event("PLAYER_LOGIN")
assert(A.BrokenFor("nameplate1"), "remembered across a reload")
-- Someone else can't mark them: the GUID must belong to the sender.
local third = "Player-70-0DD"
players[third] = {name = "Real", realm = "Home"}
addon(A.EncodeBroken(third, GetServerTime() + 3600), "Liar-Home")
assert(not (A.oathbroken[third]), "a mark for someone else's GUID is ignored")
assert(A.DecodeBroken(A.EncodeBroken(them, GetServerTime() + 3 * A.OATHBREAKER), GetServerTime()) == nil, "a mark longer than a day is refused")
addon("WR|1|" .. them .. "|1|10|0.7.5", "Snap-Home")
event("NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(not A.BrokenFor("nameplate1"), "heard sworn again: the mark is gone")
