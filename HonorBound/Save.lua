-- The pledge and its verification, saved in a character macro: macros live on
-- the server, so the record follows the character to any computer.
--
-- l = pledged-since level (0 = not sworn, so a break is saved too), s, p, u =
-- the verify record's since, seen and untracked, n = write counter, b = server
-- time the oathbreaker mark ends (0 = none; HB3 saves had no b), h = a hash
-- of it all bound to the character's GUID. That stops hand edits and copies
-- to another character, not a determined cheater: the formula ships with the
-- addon.
local _, A = ...

A.SAVE_NAME = "HonorBound Save" -- macro names are at most 16 characters
local SAVE_ICON = 134400        -- the question mark icon
local WARNING = "#HonorBound save data. Do not edit or delete this macro:"
    .. " a changed line is ignored and your pledge may be lost."

-- Two 32-bit string hashes, kept below 2^53 so every client agrees.
local function Hash(text)
    local a, b = 5381, 0
    for i = 1, #text do
        local c = text:byte(i)
        a = (a * 33 + c) % 4294967296
        b = (c + b * 65599) % 4294967296
    end
    return ("%08X%08X"):format(a, b)
end
-- Hashed twice so a small change anywhere scrambles the whole result.
local function Seal(guid, fields)
    local inner = Hash(fields .. "|" .. tostring(guid) .. "|HonorBound|3")
    return Hash(inner .. "|" .. tostring(guid) .. "|" .. fields)
end
local function Fields(r, format)
    local fields = ("l=%d;s=%d;p=%d;u=%d;n=%d"):format(r.level, math.floor(r.since), math.floor(r.seen),
        math.floor(r.untracked), r.n)
    if format == "HB3" then return fields end
    return fields .. (";b=%d"):format(math.floor(r.broken or 0))
end

-- record: {level, since, seen, untracked, n, broken}
function A.EncodeSave(guid, record)
    local fields = Fields(record)
    return WARNING .. "\n#HB4 " .. fields .. ";h=" .. Seal(guid, fields)
end
-- The record, or nil and why: "missing" or "altered".
function A.DecodeSave(guid, body)
    if type(body) ~= "string" then return nil, "missing" end
    local format, l, s, p, u, n, b, h = body:match("#(HB4) l=(%d+);s=(%d+);p=(%d+);u=(%d+);n=(%d+);b=(%d+);h=(%x+)")
    if not format then
        format, l, s, p, u, n, h = body:match("#(HB3) l=(%d+);s=(%d+);p=(%d+);u=(%d+);n=(%d+);h=(%x+)")
    end
    if not format then return nil, ((body:find("#HB4", 1, true) or body:find("#HB3", 1, true)) and "altered" or "missing") end
    local record = {level = tonumber(l), since = tonumber(s), seen = tonumber(p),
        untracked = tonumber(u), n = tonumber(n), broken = tonumber(b) or 0}
    if record.level > 60 or h:upper() ~= Seal(guid, Fields(record, format)) then return nil, "altered" end
    return record
end

-- Only a character macro counts: an account one is shared by every character.
-- Character indexes come after all the account slots, so past the account
-- count is a character macro. (MAX_ACCOUNT_MACROS lives in the macro UI, which
-- may not be loaded.)
local function Index()
    if not (GetMacroIndexByName and GetNumMacros) then return end
    local index = GetMacroIndexByName(A.SAVE_NAME)
    local account = GetNumMacros()
    if type(index) == "number" and index > 0 and index > (account or 0) then return index end
end
function A.ReadSave(guid)
    local index = Index()
    if not index then return nil, "missing" end
    local _, _, body = GetMacroInfo(index)
    return A.DecodeSave(guid, body)
end
-- true, or false and why: "combat" (try again later), "full", "unsupported".
function A.WriteSave(guid, record)
    if not (CreateMacro and EditMacro and GetMacroIndexByName) then return false, "unsupported" end
    if InCombatLockdown() then return false, "combat" end
    local body = A.EncodeSave(guid, record)
    local index = Index()
    if index then
        local _, _, current = GetMacroInfo(index)
        if current ~= body then EditMacro(index, A.SAVE_NAME, SAVE_ICON, body) end
        return true
    end
    -- Forever has more character slots than MAX_CHARACTER_MACROS may say:
    -- ask the game to make one, and call it full only if it didn't.
    local _, before = GetNumMacros()
    local ok, made = pcall(CreateMacro, A.SAVE_NAME, SAVE_ICON, body, true)
    if ok and type(made) == "number" and made > 0 then return true end
    local _, after = GetNumMacros()
    if (after or 0) > (before or 0) then return true end
    return false, (before or 0) > 0 and "full" or "unsupported"
end
