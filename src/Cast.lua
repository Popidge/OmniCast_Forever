-- OmniCast Forever: player casts, channels and the global cooldown.
local _, ns = ...
local C = ns.Compat

local Cast = ns:NewModule("Cast")

local HOLD_SUCCESS = 0.3
local HOLD_FAILED = 0.8
local DEFAULT_GCD = 1.5

Cast.cur = nil     -- active cast/channel lane
Cast.hold = nil    -- finished/interrupted lane shown briefly
Cast.gcdLength = DEFAULT_GCD -- this character's GCD (learned per class; see GCDLength)
Cast.loggedPush, Cast.loggedTarget = 0, 0

local lastSpell = {} -- last successful instant: name, icon, time
local gcd = {}       -- start, finish, estimated
Cast.gcdState = gcd

-- Reused lane tables. `serial` changes whenever a lane's label/colour/target
-- change, so the bar knows when to redraw its static parts.
local castLane = { kind = "cast" }
local holdLane = { kind = "hold" }
local gcdLane = { kind = "gcd" }
local serial = 0
local function NextSerial() serial = serial + 1; return serial end

-- Cast identity: true/false when both GUIDs are readable, nil when unknown
-- (then callers fall back to state-based checks).
local function SameCast(a, b)
    if a == nil or b == nil or not C.Readable(a, b) then return nil end
    return a == b
end

---------------------------------------------------------------------------
-- Latency
-- Forever predicts casts client-side: UNIT_SPELLCAST_START fires in the same
-- frame as UNIT_SPELLCAST_SENT (confirmed in the log), so the round trip
-- can't be measured from events. Use the client's network latency instead.
---------------------------------------------------------------------------
local function GCDRunning(now)
    return gcd.finish ~= nil and gcd.finish > now
end

local function ResolveLatency()
    return C.WorldLatency()
end

---------------------------------------------------------------------------
-- Spell targets
-- UNIT_SPELLCAST_SENT(unit, targetName, castGUID, spellID) is the only place
-- the target name appears. It can be secret in combat; FontString:SetText
-- accepts secret strings from addon code, so it is passed through untouched.
---------------------------------------------------------------------------
-- Bounded: entries expire after TARGET_TTL and are pruned on every send, so
-- instant-only play can't grow it. Nothing is stored while targets are off.
local TARGET_TTL = 3
local sentTargets = {} -- castGUID -> target name
local sentTimes = {}   -- castGUID -> GetTime() of the send
local lastSent = {}    -- spellID, target, time

local function PruneTargets(now)
    for guid, t in pairs(sentTimes) do
        if now - t > TARGET_TTL then
            sentTimes[guid], sentTargets[guid] = nil, nil
        end
    end
end

local function OnSent(_, _, target, castGUID, spellID)
    if not ns.db.showTarget then return end
    local now = GetTime()
    PruneTargets(now)
    lastSent.spellID = C.Readable(spellID) and spellID or nil
    lastSent.target, lastSent.time = target, now
    if castGUID and C.Readable(castGUID) then
        sentTargets[castGUID], sentTimes[castGUID] = target, now
    end
end

local function ResolveTarget(castGUID, spellID)
    if not ns.db.showTarget then return nil end
    local target
    local guidKnown = castGUID and C.Readable(castGUID)
    if guidKnown and sentTimes[castGUID] then
        target = sentTargets[castGUID]
        sentTargets[castGUID], sentTimes[castGUID] = nil, nil
    elseif lastSent.time and GetTime() - lastSent.time < 2 and (spellID == nil or lastSent.spellID == spellID) then
        target = lastSent.target
    end
    if Cast.loggedTarget < 8 then
        Cast.loggedTarget = Cast.loggedTarget + 1
        ns:Log("cast target: %s", target == nil and "none" or (C.Readable(target) and string.format("%q", target) or "<secret>"))
    end
    if target == nil then return nil end
    if C.Readable(target) then
        -- Hide empty and self targets (self-buffs, Life Tap...).
        if target == "" or target == UnitName("player") then return nil end
    end
    return target
end

---------------------------------------------------------------------------
-- Casts & channels
---------------------------------------------------------------------------
function Cast:Begin(kind, castGUID, spellID)
    local info = C.GetCast(kind)
    if not info then return end
    local l = castLane
    wipe(l)
    l.serial = NextSerial()
    l.began = GetTime() -- client time this cast started (for queue filtering)
    l.kind = kind
    l.fill = kind -- "cast" | "channel"
    l.state = "active"
    l.castGUID = (castGUID and C.Readable(castGUID) and castGUID) or info.castGUID
    l.spellID = spellID or info.spellID
    if l.spellID then self:ClearQueued(l.spellID) end -- the queued spell started
    if self.queued and self.queued.repeat_ then self:ClearQueued() end -- a different spell started instead
    l.label = info.text or info.name or ""
    l.name = info.name
    l.icon = info.icon
    l.reverse = (kind == "channel")
    l.color = ns.db.colors[kind]
    l.alpha = 1
    l.target = ResolveTarget(castGUID or info.castGUID, spellID or info.spellID)
    if info.secret then
        -- Not expected for the player's own casts; logged so we find out if it happens.
        ns:Log("secret %s timing for %s", kind, tostring(info.name))
        l.state = "hold"
        l.value = 1
    else
        l.start, l.finish = info.start, info.finish
        l.baseFinish = info.finish
        l.delay = 0
        local dur = l.finish - l.start
        l.latency = ResolveLatency()
        if kind == "cast" then l.queue = C.SpellQueueWindow() end
        if kind == "channel" then
            local interval = ns.Data:ChannelInterval(info.name)
            if interval and dur > 0 then l.tickInterval = interval end
        end
    end
    self.cur = l
    self.hold = nil
end

-- Pushback: casts are delayed (finish moves later), channels are cut short
-- (finish moves earlier). lane.delay is signed: +delay for casts, -lost for channels.
function Cast:Refresh(kind)
    if not self.cur or self.cur.kind ~= kind then return self:Begin(kind) end
    local info = C.GetCast(kind)
    if not info or info.secret then return end
    local l = self.cur
    local oldFinish = l.finish
    l.start, l.finish = info.start, info.finish
    if kind == "cast" then
        l.delay = info.delay or (l.finish - l.baseFinish)
    else
        l.delay = l.finish - l.baseFinish
    end
    if oldFinish and math.abs(l.finish - oldFinish) > 0.01 then
        l.pushAt = GetTime()
        if Cast.loggedPush < 10 then
            Cast.loggedPush = Cast.loggedPush + 1
            ns:Log("pushback %s: finish %+.2fs, total %+.2fs (api delay %s)", kind, l.finish - oldFinish, l.delay, tostring(info.delay))
        end
    end
end

local function StillCasting()
    return (UnitCastingInfo("player") or UnitChannelInfo("player")) ~= nil
end

-- Ends the current cast. `castGUID` (optional) is the event's cast; a
-- mismatch means the event belongs to another cast and is ignored. A failure
-- can also convert a just-finished "success" flash of the same cast.
function Cast:End(result, castGUID)
    local cur = self.cur
    local src
    if cur and SameCast(castGUID, cur.castGUID) ~= false then
        src = cur
    elseif result ~= "success" and self.hold and self.hold.result == "success"
        and SameCast(castGUID, self.hold.castGUID) ~= false then
        src = self.hold
    end
    if not src then return end
    local srcKind = src.kind
    local h = holdLane
    h.serial = NextSerial()
    h.castGUID = src.castGUID
    h.label = src.label
    h.icon = src.icon
    h.kind = "hold"
    h.state = "hold"
    h.reverse = false
    h.latency, h.queue, h.ticks, h.tickInterval, h.target = nil, nil, nil, nil, src.target
    h.delay, h.pushAt = nil, nil
    h.result = result
    h.alpha = 1
    h.rightText = nil
    local now = GetTime()
    h.began = now
    if result == "success" then
        h.color = (srcKind == "channel") and ns.db.colors.channel or ns.db.colors.success
        h.fill = (srcKind == "channel") and "channelDone" or "success"
        h.value = (srcKind == "channel") and 0 or 1
        h.until_ = now + HOLD_SUCCESS
        if srcKind == "cast" then ns.Swing:OnCastCompleted() end
    else
        h.color = ns.db.colors.failed
        h.fill = "failed"
        h.value = 1
        h.until_ = now + HOLD_FAILED
        h.label = (result == "interrupted") and (INTERRUPTED or "Interrupted") or (FAILED or "Failed")
    end
    if src == cur then self.cur = nil end
    self.hold = h
end

---------------------------------------------------------------------------
-- Global cooldown
-- Forever has no GCD spell (61304 doesn't exist), and spell cooldown timing is
-- secret in combat. What *is* readable (confirmed in the log):
--   * SPELL_UPDATE_COOLDOWN(spellID, base, category, startRecoveryCategory):
--     category 133 = triggers the GCD. It fires on key press (even when the
--     spell is only queued) and for pet spells, so it's used to LEARN which
--     spells trigger the GCD, never to time it.
--   * Player spell IDs in UNIT_SPELLCAST_START / _SUCCEEDED.
-- So the GCD starts when one of *your* GCD spells actually fires: cast start
-- for hard casts, success for instants. Out of combat the exact time is read
-- from the spell's own cooldown (and the GCD length learned); in combat the
-- learned length is used, and the fill animates from the spell's duration
-- object when it has no cooldown of its own.
---------------------------------------------------------------------------
local GCD_CATEGORY = 133
local GCD_NONE, GCD_ONLY, GCD_PLUS_CD = 0, 1, 2
local pending -- instant whose GCD status was unknown when it succeeded
local logged = { cd = 0, succ = 0, gcd = 0 }

-- GCD length: learned per spell (exact, out of combat), else per class, else
-- the class default. Classic GCDs aren't affected by haste; rogues (and cat
-- form, learned per spell) use 1.0s.
local CLASS_GCD = { ROGUE = 1.0 }
local playerClass

local function GCDLength(spellID)
    return (spellID and ns.db.spellGCD[spellID]) or Cast.gcdLength
end

local function LearnGCD(spellID, dur)
    if ns.db.spellGCD[spellID] ~= dur then
        ns:Log("GCD length learned: spell %s %.2fs", tostring(spellID), dur)
    end
    ns.db.spellGCD[spellID] = dur
    if playerClass then ns.db.gcdLengths[playerClass] = dur end
    Cast.gcdLength = dur
end

local function SpellGCDType(spellID)
    return ns.db.gcdSpells[spellID]
end

-- Exact GCD for a spell if its cooldown is readable (out of combat).
local function ReadSpellGCD(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, start, dur = pcall(function()
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then return info.startTime, info.duration end
    end)
    if ok and start and dur and C.Readable(start, dur) and dur >= 0.75 and dur <= 1.5 then
        return start, dur
    end
end

local function DurationObject(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local ok, obj = pcall(C_Spell.GetSpellCooldownDuration, spellID, false)
    if ok and obj and not C.IsSecret(obj) then return obj end
end

local function StartGCD(spellID, at, source)
    local start, dur = ReadSpellGCD(spellID)
    if start then
        gcd.start, gcd.finish, gcd.estimated, gcd.obj = start, start + dur, false, nil
        LearnGCD(spellID, dur)
    else
        gcd.start, gcd.finish, gcd.estimated = at, at + GCDLength(spellID), true
        gcd.obj = (SpellGCDType(spellID) == GCD_ONLY) and DurationObject(spellID) or nil
    end
    gcd.source = source
    gcd.spell = spellID
    if logged.gcd < 20 then
        logged.gcd = logged.gcd + 1
        ns:Log("GCD from %s spell %s: %s %.2fs (duration object %s)", source, tostring(spellID),
            start and "exact" or "estimated", gcd.finish - gcd.start, tostring(gcd.obj ~= nil))
    end
end

local function OnCooldownUpdate(_, spellID, baseSpellID, category, startRecoveryCategory)
    if logged.cd < 10 and spellID ~= nil then
        logged.cd = logged.cd + 1
        ns:Log("SPELL_UPDATE_COOLDOWN(%s)", C.ShowArgs(spellID, baseSpellID, category, startRecoveryCategory))
    end
    if spellID == nil or not C.Readable(spellID, category, startRecoveryCategory) then return end
    local t
    if startRecoveryCategory == GCD_CATEGORY then
        t = (category == nil or category == 0) and GCD_ONLY or GCD_PLUS_CD
    else
        t = GCD_NONE
    end
    ns.db.gcdSpells[spellID] = t
    if baseSpellID and C.Readable(baseSpellID) then ns.db.gcdSpells[baseSpellID] = t end
    -- The cooldown lands just after SUCCEEDED: upgrade an estimate to exact
    -- (and learn the GCD length) when it's readable, i.e. out of combat.
    if gcd.estimated and gcd.spell == spellID and gcd.start and GetTime() - gcd.start < 0.2 then
        local start, dur = ReadSpellGCD(spellID)
        if start then
            gcd.start, gcd.finish, gcd.estimated, gcd.obj = start, start + dur, false, nil
            LearnGCD(spellID, dur)
        end
    end
    -- The instant fired a moment before we knew it triggers the GCD.
    if pending and pending.id == spellID and GetTime() - pending.time < 0.2 then
        if t ~= GCD_NONE then StartGCD(spellID, pending.time, pending.source) end
        pending = nil
    end
end

-- Hard cast started: its GCD starts now (mostly hidden behind the cast).
function Cast:OnHardCastStart(spellID)
    if not spellID then return end
    local t = SpellGCDType(spellID)
    if t == nil then
        -- Not learned yet (e.g. Opening, Herbalism): let the cooldown event decide.
        pending = { id = spellID, time = GetTime(), source = "cast-start" }
    elseif t ~= GCD_NONE then
        StartGCD(spellID, GetTime(), "cast-start")
    end
end

local function OnSucceeded(_, _, castGUID, spellID)
    local now = GetTime()
    -- SUCCEEDED fires before STOP: the current hard cast finishing, unless the
    -- GUIDs prove this success belongs to a different spell.
    local cur = Cast.cur
    local isHardCast = cur ~= nil and cur.kind == "cast" and SameCast(castGUID, cur.castGUID) ~= false
    if isHardCast then cur.succeeded = true end
    local readable = C.Readable(spellID)
    local name = readable and C.GetSpellName(spellID) or nil
    local isRanged = name ~= nil and ns.Data:IsRanged(spellID, name)
    if logged.succ < 10 then
        logged.succ = logged.succ + 1
        ns:Log("SUCCEEDED spell=%s name=%s hardcast=%s", C.Show(spellID), tostring(name), tostring(isHardCast))
    end
    if isHardCast or isRanged then return end
    lastSpell.name, lastSpell.icon, lastSpell.time = name, name and C.GetSpellIcon(spellID) or nil, now

    if readable then
        local t = SpellGCDType(spellID)
        if t == nil then
            pending = { id = spellID, time = now, source = "succeeded" } -- decided by the cooldown event
        elseif t ~= GCD_NONE then
            StartGCD(spellID, now, "succeeded")
        end
    elseif not ns.Swing.rangedOn then
        -- Spell ID hidden: assume a GCD (not while wanding/Auto Shot, where every shot succeeds).
        gcd.start, gcd.finish, gcd.estimated, gcd.obj, gcd.source = now, now + Cast.gcdLength, true, nil, "unknown"
    end
end

-- On-next-swing abilities (Heroic Strike...) "succeed" with the swing itself
-- and have no GCD; drop a guessed GCD that landed on the same instant.
function Cast:OnMeleeSwing(now)
    if gcd.estimated and gcd.source == "unknown" and gcd.start and math.abs(now - gcd.start) < 0.1 then
        gcd.finish = nil
    end
end

---------------------------------------------------------------------------
-- Queued spell
-- Pressing a spell during a cast/channel or the GCD (inside the spell queue
-- window) queues it. C_Spell.IsCurrentSpell() is true for a spell that is
-- "being cast or queued to be cast" (it is what lights action buttons), and
-- CURRENT_SPELL_CAST_CHANGED fires when the queue changes. The press itself
-- names the candidate: SPELL_UPDATE_COOLDOWN fires on the key press (log-
-- confirmed; it also fires for pet spells, which IsCurrentSpell rules out).
-- UNIT_SPELLCAST_SENT is no use here: on Forever it fires when the queued
-- spell actually goes off, not on the press.
---------------------------------------------------------------------------
Cast.queued = nil -- { id, name, icon, time }
local candidate = {}
local AUTO_ATTACK = { [6603] = true } -- Auto Attack is "current" while meleeing
local loggedQueue = 0

local function Busy(now)
    return Cast.cur ~= nil or GCDRunning(now)
end

local function IsCurrent(spellID)
    if not (C_Spell and C_Spell.IsCurrentSpell) then return false end
    local ok, cur = pcall(C_Spell.IsCurrentSpell, spellID)
    return ok and C.Readable(cur) and cur == true
end

local function LogQueue(fmt, ...)
    if loggedQueue < 30 then
        loggedQueue = loggedQueue + 1
        ns:Log("queue: " .. fmt, ...)
    end
end

function Cast:ClearQueued(spellID)
    if candidate.id and (spellID == nil or candidate.id == spellID) then candidate.id = nil end
    local q = self.queued
    if q and (spellID == nil or q.id == spellID) then
        self.queued = nil
        ns:Wake()
    end
end

function Cast:CheckQueued(source)
    local now = GetTime()
    local q = self.queued
    -- A repeat of the current cast can't be validated with IsCurrentSpell
    -- (the current cast already makes it "current"); it clears when it starts,
    -- fails, or the safety timeout in GetQueued expires.
    if q and not q.repeat_ and not IsCurrent(q.id) then
        LogQueue("cleared %s (%s)", tostring(q.name), source)
        self:ClearQueued()
    end
    -- Never "queue" the spell that is being cast right now (IsCurrentSpell
    -- is true for it too); repeats are handled in OnPress.
    local castingIt = Cast.cur and Cast.cur.spellID == candidate.id
    if not self.queued and candidate.id and not castingIt and now - candidate.time < 0.6
        and Busy(now) and IsCurrent(candidate.id) then
        local id = candidate.id
        self.queued = { id = id, name = C.GetSpellName(id), icon = C.GetSpellIcon(id), time = now }
        candidate.id = nil
        LogQueue("queued %s (%s) %.2fs before %s ends", tostring(self.queued.name), source,
            (Cast.cur and Cast.cur.finish or gcd.finish or now) - now, Cast.cur and "cast" or "GCD")
        ns:Wake()
    end
end

-- A key press: remember the spell as a queue candidate when we're busy.
local function OnPress(spellID, source, castGUID)
    if not spellID or not C.Readable(spellID) or AUTO_ATTACK[spellID] then return end
    if ns.Data:IsRanged(spellID, C.GetSpellName(spellID)) then return end
    local now = GetTime()
    if not Busy(now) then return end
    local cur = Cast.cur
    if cur and cur.spellID == spellID then
        -- Same spell as the current cast. The game only accepts that press
        -- inside the spell queue window (earlier it is key spam: "Another
        -- action is in progress"), and the press fires SPELL_UPDATE_COOLDOWN
        -- for the spell (log: ~0.16s before the end). The same event also
        -- fires at the cast's start (outside the window) and right after it
        -- succeeds (cur.succeeded), so both are excluded.
        if source ~= "cooldown" then return end
        if cur.kind ~= "cast" or not cur.finish or cur.succeeded then return end
        -- The cast's own start fires this event too. Casts no longer than the
        -- queue window (e.g. talented 0.4s Corruption) would otherwise look
        -- like a repeat press, so ignore the cast's first moment.
        if cur.began and now - cur.began < 0.1 then return end
        local left = cur.finish - now
        if left > C.SpellQueueWindow() or left < 0.03 then return end
        if Cast.queued and Cast.queued.id == spellID then return end
        Cast.queued = { id = spellID, name = C.GetSpellName(spellID), icon = C.GetSpellIcon(spellID),
            time = now, repeat_ = true, behind = cur.castGUID }
        LogQueue("queued repeat %s (%s) %.2fs before cast ends", tostring(Cast.queued.name), source, cur.finish - now)
        ns:Wake()
        return
    end
    if cur and cur.spellID == spellID then return end
    candidate.id, candidate.time = spellID, now
    Cast:CheckQueued(source)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Cast:Enable()
    local P = "player"
    local _, class = UnitClass("player")
    playerClass = class
    self.gcdLength = ns.db.gcdLengths[class] or CLASS_GCD[class] or DEFAULT_GCD
    ns.db.gcdLength = nil -- pre-0.2.1 account-wide value; now per class/spell

    -- SENT fires just before START (same frame) and carries the target name.
    ns:On("UNIT_SPELLCAST_SENT", OnSent, P)
    ns:On("UNIT_SPELLCAST_START", function(_, _, castGUID, spellID)
        Cast:Begin("cast", castGUID, C.Readable(spellID) and spellID or nil)
        if C.Readable(spellID) then Cast:OnHardCastStart(spellID) end
    end, P)
    ns:On("UNIT_SPELLCAST_DELAYED", function() Cast:Refresh("cast") end, P)
    ns:On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, castGUID, spellID)
        Cast:Begin("channel", castGUID, C.Readable(spellID) and spellID or nil)
    end, P)
    ns:On("UNIT_SPELLCAST_CHANNEL_UPDATE", function() Cast:Refresh("channel") end, P)
    -- Stop/interrupt/fail carry the cast GUID; Cast:End ignores events for a
    -- different cast (e.g. a late stop arriving after a new cast began).
    ns:On("UNIT_SPELLCAST_STOP", function(_, _, castGUID)
        if Cast.cur and Cast.cur.kind == "cast" then Cast:End("success", castGUID) end
    end, P)
    ns:On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, _, castGUID, _, interruptedBy)
        if not (Cast.cur and Cast.cur.kind == "channel") then return end
        local interrupted = interruptedBy ~= nil and C.Readable(interruptedBy)
        Cast:End(interrupted and "interrupted" or "success", castGUID)
    end, P)
    -- INTERRUPTED/FAILED also fire for key-spam during a cast (another GUID).
    -- Trust a GUID match; otherwise only act if nothing is casting any more.
    local function IsCurrent(castGUID)
        return SameCast(castGUID, Cast.cur and Cast.cur.castGUID) == true
    end
    ns:On("UNIT_SPELLCAST_INTERRUPTED", function(_, _, castGUID)
        if IsCurrent(castGUID) or not StillCasting() then Cast:End("interrupted", castGUID) end
    end, P)
    ns:On("UNIT_SPELLCAST_FAILED", function(_, _, castGUID)
        if IsCurrent(castGUID) or (Cast.cur and not StillCasting()) then Cast:End("failed", castGUID) end
    end, P)
    ns:On("UNIT_SPELLCAST_SUCCEEDED", OnSucceeded, P)
    ns:On("SPELL_UPDATE_COOLDOWN", OnCooldownUpdate)

    -- Queued spell
    ns:On("SPELL_UPDATE_COOLDOWN", function(_, spellID) OnPress(spellID, "cooldown") end)
    ns:On("CURRENT_SPELL_CAST_CHANGED", function(_, cancelled)
        Cast:CheckQueued(cancelled and "cancelled" or "changed")
    end)
    -- The queued spell going off ends its "queued" state.
    ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, castGUID, spellID)
        if not C.Readable(spellID) then return end
        local q = Cast.queued
        -- A repeat stays queued through the success of the cast it waits
        -- behind; any other spell going off means the repeat didn't happen.
        if q and q.repeat_ then
            if SameCast(castGUID, q.behind) ~= false and q.id == spellID then return end
            Cast:ClearQueued()
            return
        end
        Cast:ClearQueued(spellID)
    end, P)
    -- A rejected press of the queued spell (e.g. out of range) ends it.
    ns:On("UNIT_SPELLCAST_FAILED", function(_, _, castGUID, spellID)
        local q = Cast.queued
        if q and C.Readable(spellID) and q.id == spellID and SameCast(castGUID, Cast.cur and Cast.cur.castGUID) ~= true then
            Cast:ClearQueued(spellID)
        end
    end, P)
    ns:On("PLAYER_DEAD", function() Cast:ClearQueued() end)
    ns:On("PLAYER_ENTERING_WORLD", function()
        Cast.cur, Cast.hold = nil, nil
        if UnitChannelInfo("player") then Cast:Begin("channel")
        elseif UnitCastingInfo("player") then Cast:Begin("cast") end
    end)
end

---------------------------------------------------------------------------
-- Lanes for the bar
---------------------------------------------------------------------------
-- Active cast/channel, or the brief finished/interrupted flash.
function Cast:GetLane(now)
    local cur = self.cur
    if cur then
        if cur.finish and now > cur.finish + 0.5 and not StillCasting() then
            self.cur = nil -- missed the stop event (e.g. loading screen)
        else
            return cur
        end
    end
    local h = self.hold
    if h then
        -- A GCD that started after the cast ended (chained instant) takes over at once.
        local gcdTookOver = h.result == "success" and GCDRunning(now) and gcd.start >= h.began - 0.05
        if now < h.until_ and not gcdTookOver then
            h.alpha = math.min(1, (h.until_ - now) / 0.2 + 0.2)
            return h
        end
        self.hold = nil
    end
end

-- The queued spell, if still valid. Safety: never outlive the cast/GCD it
-- was queued behind by more than a moment.
function Cast:GetQueued(now)
    local q = self.queued
    if q and not Busy(now - 0.5) then
        self.queued = nil
        return nil
    end
    return q
end

function Cast:GetGCDLane(now)
    if not ns.db.showGCD or not GCDRunning(now) then return nil end
    local l = gcdLane
    l.state = "active"
    l.start, l.finish = gcd.start, gcd.finish
    local recent = lastSpell.time and lastSpell.time >= gcd.start - 0.3
    local label = recent and lastSpell.name or "Global Cooldown"
    if l.label ~= label or l.gcdStart ~= gcd.start then
        l.serial = NextSerial()
        l.gcdStart = gcd.start
    end
    l.label = label
    l.icon = recent and lastSpell.icon or nil
    l.color = ns.db.colors.gcd
    l.fill = "gcd"
    l.reverse = false
    l.alpha = 1
    l.queue = C.SpellQueueWindow()
    l.durationObject = gcd.estimated and gcd.obj or nil
    return l
end
