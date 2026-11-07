-- OmniCast Forever: /oc probe - what this client actually supports.
-- Output goes to chat and to the saved log (WTF\Account\<acct>\SavedVariables\OmniCast_Forever.lua).
local _, ns = ...
local C = ns.Compat

local Debug = ns:NewModule("Debug")

local function Out(fmt, ...)
    local msg = string.format(fmt, ...)
    print("|cff66ccffOC|r " .. msg)
    ns:Log("probe: %s", msg)
end

local function Has(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return false end
        v = v[part]
    end
    return v ~= nil
end

function Debug:Probe()
    -- Never let one bad line hide the rest of the report.
    if not ns.SafeCall(Debug.ProbeLines, Debug) then
        Out("probe stopped early - error saved to the log")
    end
end

function Debug:ProbeLines()
    local _, build, _, interface = GetBuildInfo()
    Out("v%s | build %s | interface %s | project %s", ns.version, tostring(build), tostring(interface), tostring(WOW_PROJECT_ID))
    Out("in combat: %s | secret restrictions: %s", tostring(InCombatLockdown()),
        Has("C_Secrets.HasSecretRestrictions") and C.Show(select(2, pcall(C_Secrets.HasSecretRestrictions))) or "n/a")

    -- Swing timer API
    local enum = Enum and Enum.PlayerSwingType
    if type(enum) == "table" then
        local parts = {}
        for k, v in pairs(enum) do parts[#parts + 1] = k .. "=" .. tostring(v) end
        Out("Enum.PlayerSwingType: %s", table.concat(parts, " "))
    else
        Out("Enum.PlayerSwingType: missing")
    end
    for _, ev in ipairs({ "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_ENTER_COMBAT",
        "START_AUTOREPEAT_SPELL", "UNIT_SPELLCAST_SENT", "COMBAT_LOG_EVENT_UNFILTERED" }) do
        Out("event %s: %s", ev, ns.EventIsValid(ev) and "valid" or "INVALID")
    end
    local S = ns.Swing
    Out("PLAYER_SWING seen %d (melee native: %s, ranged native: %s) last: %s",
        S.swingEvents, tostring(S.nativeMelee), tostring(S.nativeRanged), tostring(S.lastSwingPayload))
    Out("range payload last: %s | in range mh=%s ranged=%s", tostring(S.lastRangePayload),
        tostring(S.inRange.mh), tostring(S.inRange.ranged))
    local mh, oh = C.MeleeSpeeds()
    Out("speeds mh=%s oh=%s ranged=%s | auto-attack=%s autorepeat=%s",
        tostring(mh), tostring(oh), tostring(C.RangedSpeed()), tostring(S.meleeOn), tostring(S.rangedOn))
    Out("CVar showSwingTimer=%s SpellQueueWindow=%s", tostring(GetCVar("showSwingTimer")), tostring(GetCVar("SpellQueueWindow")))

    -- Cast / GCD
    local counts = { [0] = 0, 0, 0 }
    for _, t in pairs(ns.db.gcdSpells) do counts[t] = (counts[t] or 0) + 1 end
    local g = ns.Cast.gcdState
    Out("GCD length %.2fs (%s) | learned spells: %d GCD-only, %d GCD+cooldown, %d off-GCD | world latency %.0fms",
        ns.Cast.gcdLength, ns.db.gcdLengths[select(2, UnitClass("player"))] and "learned" or "default", counts[1], counts[2], counts[0], C.WorldLatency() * 1000)
    Out("last GCD: source=%s estimated=%s duration object=%s", tostring(g.source), tostring(g.estimated), tostring(g.obj ~= nil))
    if C_Secrets then
        local function Q(fn, ...)
            if not fn then return "n/a" end
            local ok, v = pcall(fn, ...)
            return ok and C.Show(v) or "error"
        end
        Out("secret now? GCD cooldown=%s player casts=%s player stats=%s",
            Q(C_Secrets.ShouldSpellCooldownBeSecret, 61304),
            Q(C_Secrets.ShouldUnitSpellCastBeSecret, "player", 686), -- Shadow Bolt
            Q(C_Secrets.ShouldUnitStatsBeSecret, "player"))
    end

    -- Blizzard frames
    local names = {}
    for n in pairs(ns.Blizzard.castbars) do names[#names + 1] = n end
    Out("Blizzard castbars: %s", #names > 0 and table.concat(names, ", ") or "none found")
    ns.Blizzard:FindSwingFrames()
    names = {}
    for n in pairs(ns.Blizzard.swingFrames) do names[#names + 1] = n end
    Out("Blizzard swing frames: %s", #names > 0 and table.concat(names, ", ") or "none found")
    Out("probe saved to log - /reload or log out to write it to disk")
end
