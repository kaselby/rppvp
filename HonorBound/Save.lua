-- The pledge and its verification, saved in a character macro. Macros are
-- stored on Blizzard's servers, unlike addon data, so the record follows the
-- character to any computer, and the verification counts play on all of them.
--
-- One line: l = pledged-since level (0 = not sworn: a break is saved too, so
-- another computer can't bring it back), s = /played at the pledge, p =
-- /played as last seen by HonorBound, u = untracked play, n = write counter
-- (the higher of the macro's and this computer's wins at login), h = a hash
-- of all of it bound to the character's GUID. Hand edits, or a macro copied
-- to another character, don't check out. The formula ships with the addon,
-- so it stops casual edits, not a determined cheater.
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
local function Fields(r)
    return ("l=%d;s=%d;p=%d;u=%d;n=%d"):format(r.level, math.floor(r.since), math.floor(r.seen),
        math.floor(r.untracked), r.n)
end
A.SaveSeal = Seal

-- record: {level, since, seen, untracked, n}
function A.EncodeSave(guid, record)
    local fields = Fields(record)
    return WARNING .. "\n#HB3 " .. fields .. ";h=" .. Seal(guid, fields)
end
-- The record, or nil and why: "missing" or "altered".
function A.DecodeSave(guid, body)
    if type(body) ~= "string" then return nil, "missing" end
    local l, s, p, u, n, h = body:match("#HB3 l=(%d+);s=(%d+);p=(%d+);u=(%d+);n=(%d+);h=(%x+)")
    if not l then return nil, (body:find("#HB3", 1, true) and "altered" or "missing") end
    local record = {level = tonumber(l), since = tonumber(s), seen = tonumber(p),
        untracked = tonumber(u), n = tonumber(n)}
    if record.level > 60 or h:upper() ~= Seal(guid, Fields(record)) then return nil, "altered" end
    return record
end

-- Only character macros count: an account-wide macro of the same name would
-- be shared with every character.
local function Index()
    if not GetMacroIndexByName then return end
    local index = GetMacroIndexByName(A.SAVE_NAME)
    if type(index) == "number" and index > (MAX_ACCOUNT_MACROS or 120) then return index end
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
    local _, perCharacter = GetNumMacros()
    if (perCharacter or 0) >= (MAX_CHARACTER_MACROS or 18) then return false, "full" end
    if CreateMacro(A.SAVE_NAME, SAVE_ICON, body, true) then return true end
    return false, "unsupported"
end
