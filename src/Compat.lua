-- OmniCast Forever: API shims and "secret value" guards.
-- WoW Forever runs on the retail (Midnight) engine: some values are "secret"
-- during combat restrictions and cannot be compared or used in arithmetic by
-- addon code. Everything here returns plain Lua values or nil.
local _, ns = ...

local C = {}
ns.Compat = C

local issecret = issecretvalue

function C.IsSecret(v)
    return v ~= nil and issecret ~= nil and issecret(v) == true
end

-- True when none of the given values are secret.
function C.Readable(...)
    if not issecret then return true end
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil and issecret(v) then return false end
    end
    return true
end

-- Plain printable form of anything (secrets never leak into string ops).
function C.Show(v)
    if C.IsSecret(v) then return "<secret>" end
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function C.ShowArgs(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = C.Show((select(i, ...))) end
    return table.concat(out, ", ")
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
function C.GetSpellName(id)
    if not id or C.IsSecret(id) then return nil end
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

function C.GetSpellIcon(id)
    if not id or C.IsSecret(id) then return nil end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end

---------------------------------------------------------------------------
-- Casting
---------------------------------------------------------------------------
-- Normalised cast info for the player. Returns a table (reused) or nil.
local castInfo = {}
function C.GetCast(kind)
    local name, text, icon, startMS, endMS, notInt, spellID, castGUID, delayMS, _
    if kind == "channel" then
        name, text, icon, startMS, endMS, _, notInt, spellID = UnitChannelInfo("player")
    else
        -- 11th return delayTimeMs: total pushback so far (never secret).
        name, text, icon, startMS, endMS, _, castGUID, notInt, spellID, _, delayMS = UnitCastingInfo("player")
    end
    if not name then return nil end
    wipe(castInfo)
    castInfo.kind = kind
    castInfo.secret = not C.Readable(startMS, endMS)
    castInfo.name = C.Readable(name) and name or nil
    castInfo.text = C.Readable(text) and text or nil
    castInfo.icon = icon
    if not castInfo.secret then
        castInfo.start = startMS / 1000
        castInfo.finish = endMS / 1000
    end
    castInfo.spellID = C.Readable(spellID) and spellID or nil
    castInfo.castGUID = C.Readable(castGUID) and castGUID or nil
    if type(delayMS) == "number" and C.Readable(delayMS) then castInfo.delay = delayMS / 1000 end
    return castInfo
end

-- Higher of home/world latency in seconds (casts can hit either server).
function C.WorldLatency()
    local _, _, home, world = GetNetStats()
    if not C.Readable(home, world) then return 0 end
    local ms = math.max(home or 0, world or 0)
    return ms / 1000
end

-- Spell queue window in seconds: the client's own value, else the CVar.
function C.SpellQueueWindow()
    if C_Spell and C_Spell.GetSpellQueueWindow then
        local ok, ms = pcall(C_Spell.GetSpellQueueWindow)
        if ok and type(ms) == "number" and C.Readable(ms) and ms > 0 then return ms / 1000 end
    end
    local v = tonumber(GetCVar and GetCVar("SpellQueueWindow"))
    return (v or 400) / 1000
end

---------------------------------------------------------------------------
-- Weapons
---------------------------------------------------------------------------
-- Main-hand and off-hand speed (oh is nil unless dual wielding).
function C.MeleeSpeeds()
    local ok, mh, oh = pcall(UnitAttackSpeed, "player")
    if not ok or not C.Readable(mh, oh) then return nil end
    if oh and oh <= 0 then oh = nil end
    return mh, oh
end

-- Forever's UnitAttackSpeed returns (mainHand, offHand, ranged).
-- Always returns exactly one value (nil when unknown).
function C.RangedSpeed()
    local ok, _, _, speed = pcall(UnitAttackSpeed, "player")
    if ok and speed ~= nil and C.Readable(speed) and speed > 0 then return speed end
    if UnitRangedDamage then
        ok, speed = pcall(UnitRangedDamage, "player")
        if ok and speed ~= nil and C.Readable(speed) and speed > 0 then return speed end
    end
    return nil
end

function C.SlotIcon(slot)
    local ok, tex = pcall(GetInventoryItemTexture, "player", slot)
    if ok then return tex end
end

-- Optional LibSharedMedia (many Forever addons embed it).
function C.LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end
