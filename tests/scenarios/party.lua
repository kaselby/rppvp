-- 0.4.6: crests on Blizzard's party frames, in place of their PvP icon.
setup()
local mate = "Player-70-AAA888"
group = true
-- Like PartyFrame.MemberFrameN in 12.1.5: made when the party shows.
PartyFrame = object("PartyFrame")
local member = object("PartyMemberFrame1")
member.unit = "party1"
function member:GetUnit() return self.unit end
member.Portrait = object()
member.PartyMemberOverlay = {PVPIcon = object()}
function member.PartyMemberOverlay.PVPIcon:GetAtlas() return "ui-hud-unitframe-player-pvp-hordeicon" end
PartyFrame.MemberFrame1 = member
units.party1 = {guid = mate, flagged = true, faction = "Horde", name = "Mate", realm = "Home"}
local function party(message) event("CHAT_MSG_ADDON", A.PREFIX, message, "PARTY", "Mate-Home") end
event("GROUP_ROSTER_UPDATE")
local badge = member.HonorBoundWidget
assert(badge and not badge.shown, "a party frame gets a crest slot, empty until they're known")
party(A.Encode(mate, true))
assert(badge.shown and badge.crest.texturePath:find("CrestHorde"), "sworn and flagged: crest on their party frame")
assert(member.PartyMemberOverlay.PVPIcon.alpha == 0, "in place of the PvP icon")
assert(badge.point[2] == member.PartyMemberOverlay.PVPIcon, "anchored on the PvP icon")
assert(badge.scale == 0.75, "a little smaller than on the target frame")
units.party1.flagged = false
event("UNIT_FACTION", "party1")
assert(not badge.shown and member.PartyMemberOverlay.PVPIcon.alpha == 1, "unflagged: crest gone, icon back")
party(A.EncodeInside(mate, true))
assert(badge.shown, "inside a dungeon without us: crest stays on their party frame")
tooltipLines = {}
badge.scripts.OnEnter(badge)
assert(table.concat(tooltipLines, " "):find("HonorBound", 1, true), "hovering the crest explains it")
-- The frame now shows someone else (roster change).
units.party1 = {guid = "Player-70-AAA999", flagged = true, faction = "Horde", name = "Other", realm = "Home"}
event("GROUP_ROSTER_UPDATE")
assert(not badge.shown, "a new member doesn't inherit the old one's crest")
member.shown = false
event("GROUP_ROSTER_UPDATE")
assert(badge.unit == nil and not badge.shown, "hidden frame: no unit, no crest")
print("party: ok")
