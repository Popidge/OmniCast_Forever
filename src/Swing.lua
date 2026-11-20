-- OmniCast Forever: melee (main/off hand) and ranged swing tracking.
--
-- WoW Forever blocks the combat log for addons, so classic-style swing timers
-- (SWING_DAMAGE from CLEU) are impossible. Sources used instead, best first:
--   1. PLAYER_SWING            - native Forever event (payload decoded at runtime)
--   2. UNIT_SPELLCAST_SUCCEEDED - Auto Shot / Shoot / Throw and on-next-swing abilities
--   3. Prediction              - weapon speed from UnitAttackSpeed / UnitRangedDamage
-- PLAYER_SWING payloads are logged so the decoding can be confirmed in play.
local _, ns = ...
local C = ns.Compat

local Swing = ns:NewModule("Swing")

local HANDS = { "mh", "oh", "ranged" }
local timers = { mh = {}, oh = {}, ranged = {} }
Swing.timers = timers
Swing.meleeOn = false     -- auto-attack toggled on
Swing.rangedOn = false    -- auto-repeat (Auto Shot / wand) on
Swing.nativeMelee = false -- PLAYER_SWING seen for melee this session
Swing.nativeRanged = false
Swing.inRange = { mh = true, ranged = true }
Swing.speed = {}          -- last known speeds (stay valid if a read becomes secret)
Swing.rangedLabel = nil
Swing.swingEvents = 0

-- Enum.PlayerSwingType value -> hand key
local SWING_TYPE = {}
local function BuildSwingTypes()
    local enum = Enum and Enum.PlayerSwingType
    if type(enum) == "table" then
        for k, v in pairs(enum) do
            local key = tostring(k):lower()
            if key:find("main") then SWING_TYPE[v] = "mh"
            elseif key:find("off") then SWING_TYPE[v] = "oh"
            elseif key:find("rang") then SWING_TYPE[v] = "ranged" end
        end
    end
    if next(SWING_TYPE) == nil then
        SWING_TYPE[0], SWING_TYPE[1], SWING_TYPE[2] = "mh", "oh", "ranged"
        ns:Log("Enum.PlayerSwingType missing; assuming 0=mh 1=oh 2=ranged")
    end
end
Swing.SWING_TYPE = SWING_TYPE

---------------------------------------------------------------------------
-- Speeds & timers
---------------------------------------------------------------------------
function Swing:RefreshSpeeds()
    local mh, oh = C.MeleeSpeeds()
    if mh then
        self.speed.mh = mh
        self.speed.oh = oh
    end
    local r = C.RangedSpeed()
    if r then self.speed.ranged = r end
    -- Speeds are secret in combat, so a mid-combat swap from dual wield to a
    -- two-hander (or a shield) would otherwise keep the old off-hand lane.
    self.offHandWeapon = C.OffHandIsWeapon()
    if self.offHandWeapon == false then
        self.speed.oh = nil
        self:Clear("oh")
    end
end

-- The equipped off hand decides when readable; the off-hand speed (from
-- UnitAttackSpeed or the first off-hand PLAYER_SWING) is the fallback.
function Swing:IsDualWield()
    if self.offHandWeapon ~= nil then return self.offHandWeapon end
    return self.speed.oh ~= nil
end

function Swing:Start(hand, predicted, when)
    local dur = self.speed[hand]
    if not dur then
        self:RefreshSpeeds()
        dur = self.speed[hand]
        if not dur then return end
    end
    local t = timers[hand]
    t.start = when or GetTime()
    t.dur = dur
    t.finish = t.start + dur
    t.predicted = predicted
    t.last = GetTime()
end

function Swing:Clear(hand)
    local t = timers[hand]
    t.start, t.finish, t.dur = nil, nil, nil
end

function Swing:Running(hand, now)
    local t = timers[hand]
    return t.finish ~= nil and now < t.finish
end

-- Keep elapsed fraction when weapon speed changes mid-swing (haste, flurry, ...).
local function Rescale(hand, newDur)
    local t = timers[hand]
    if not (t.finish and t.dur and newDur) or t.dur == newDur then return end
    local now = GetTime()
    if now >= t.finish then t.dur = newDur return end
    local p = (now - t.start) / t.dur
    t.start = now - p * newDur
    t.dur = newDur
    t.finish = t.start + newDur
end

---------------------------------------------------------------------------
-- Swing events
---------------------------------------------------------------------------
local loggedSwing, loggedRange = 0, 0
ns:OnLogReset(function() loggedSwing, loggedRange = 0, 0 end)

-- PLAYER_SWING(swingDuration, swingType) - confirmed from Blizzard_SwingTimer.
-- The duration is the real (hasted) swing time, so no stat read is needed.
local function OnPlayerSwing(_, duration, swingType)
    Swing.swingEvents = Swing.swingEvents + 1
    Swing.lastSwingPayload = C.ShowArgs(duration, swingType)
    if loggedSwing < 40 then
        loggedSwing = loggedSwing + 1
        ns:Log("PLAYER_SWING(%s)", Swing.lastSwingPayload)
    end
    if C.IsSecret(swingType) then return end
    local hand = SWING_TYPE[swingType]
    if not hand then return end
    if C.Readable(duration) and type(duration) == "number" and duration > 0 then
        Swing.speed[hand] = duration
    end
    if hand == "ranged" then
        Swing.nativeRanged = true
        Swing:ProbeShot(GetTime(), duration)
    else
        Swing.nativeMelee = true
        ns.Cast:OnMeleeSwing(GetTime())
        -- The armed ability went off with this swing, or fizzled (no rage).
        if hand == "mh" and Swing.armed then
            C_Timer.After(0, function() ns.SafeCall(Swing.CheckArmed, Swing, "main-hand swing") end)
        end
    end
    Swing:Start(hand, false)
end

-- PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange): only out of
-- range when a check was actually made (no target => checksRange false).
local function OnSwingRange(_, swingType, isInRange, checksRange)
    Swing.lastRangePayload = C.ShowArgs(swingType, isInRange, checksRange)
    if loggedRange < 20 then
        loggedRange = loggedRange + 1
        ns:Log("PLAYER_SWING_RANGE_UPDATE(%s)", Swing.lastRangePayload)
    end
    if not C.Readable(swingType, isInRange, checksRange) then return end
    local hand = SWING_TYPE[swingType]
    if hand == "oh" then hand = "mh" end
    if hand then Swing.inRange[hand] = not (checksRange and not isInRange) end
end

-- isInRange is nil when no check could be made; nil is never "out of range".
function Swing:QueryRange()
    if not (C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange) then return end
    for v, hand in pairs(SWING_TYPE) do
        if hand == "mh" or hand == "ranged" then
            local ok, r = pcall(C_SwingTimer.IsTargetWithinSwingRange, v)
            if ok and C.Readable(r) then self.inRange[hand] = (r ~= false) end
        end
    end
end

local AUTO_SHOT = 75
-- Auto Shot's last 0.5s is a wind-up: moving then interrupts the shot, and
-- it fires ~0.5s after you stop (confirmed in play, v0.6.3 probe).
local AUTO_SHOT_WINDUP = 0.5

local function IsAutoShot(spellID, name)
    return spellID == AUTO_SHOT or (name ~= nil and name == C.GetSpellName(AUTO_SHOT))
end

local function AutoShotActive()
    local ok, cur = pcall(C_Spell.IsCurrentSpell, AUTO_SHOT)
    return ok and C.Readable(cur) and cur == true
end

local function OnSpellSucceeded(_, _, _, spellID)
    if C.IsSecret(spellID) then return end
    local name = C.GetSpellName(spellID)
    local Data = ns.Data
    if Data:IsRanged(spellID, name) then
        Swing.rangedLabel = name
        Swing.autoShot = IsAutoShot(spellID, name)
        if not Swing.nativeRanged then Swing:Start("ranged", false) end
    elseif Data:IsNextSwing(spellID, name) and not Swing.nativeMelee then
        -- Heroic Strike & co. "succeed" on the swing itself: a free resync point.
        Swing:Start("mh", false)
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Swing:Init()
    BuildSwingTypes()
end

function Swing:Enable()
    self:RefreshSpeeds()

    if C_SwingTimer and C_SwingTimer.EnableRangeCheck then
        for v in pairs(SWING_TYPE) do pcall(C_SwingTimer.EnableRangeCheck, v, true) end
    end

    ns:On("PLAYER_SWING", OnPlayerSwing)
    self:EnableProbe()
    ns:On("PLAYER_SWING_RANGE_UPDATE", OnSwingRange)
    ns:On("UNIT_SPELLCAST_SUCCEEDED", OnSpellSucceeded, "player")

    ns:On("PLAYER_ENTER_COMBAT", function()
        Swing.meleeOn = true
        Swing:RefreshSpeeds()
        Swing:QueryRange()
        -- No native event yet: assume the opening swing happens now.
        if not Swing.nativeMelee and not Swing:Running("mh", GetTime()) and Swing.inRange.mh ~= false then
            Swing:Start("mh", true)
            if Swing:IsDualWield() then Swing:Start("oh", true) end
        end
    end)
    ns:On("PLAYER_LEAVE_COMBAT", function() Swing.meleeOn = false; Swing:CheckArmed("melee stopped") end)

    -- Armed next swing: re-check whenever the game's current/queued spell
    -- state may have changed, and after each main-hand swing.
    ns:On("CURRENT_SPELL_CAST_CHANGED", function() Swing:CheckArmed("changed") end)
    ns:On("ACTIONBAR_UPDATE_STATE", function() Swing:CheckArmed("action state") end)
    ns:On("SPELL_UPDATE_COOLDOWN", function(_, spellID)
        if C.Readable(spellID) and spellID and ns.Data:IsNextSwing(spellID, C.GetSpellName(spellID)) then
            Swing:CheckArmed("press")
        end
    end)
    ns:On("UNIT_SPELLCAST_SUCCEEDED", function(_, _, _, spellID)
        if C.Readable(spellID) and ns.Data:IsNextSwing(spellID, C.GetSpellName(spellID)) then
            Swing:CheckArmed("swing landed")
        end
    end, "player")
    ns:On("UNIT_SPELLCAST_FAILED", function() if Swing.armed then Swing:CheckArmed("failed") end end, "player")
    ns:On("START_AUTOREPEAT_SPELL", function()
        Swing.rangedOn = true; Swing:RefreshSpeeds()
        if AutoShotActive() then Swing.autoShot = true end
    end)
    ns:On("PLAYER_STARTED_MOVING", function() Swing.moving = true end)
    ns:On("PLAYER_STOPPED_MOVING", function() Swing.moving = false end)
    ns:On("STOP_AUTOREPEAT_SPELL", function() Swing.rangedOn = false end)

    ns:On("UNIT_ATTACK_SPEED", function()
        local mh, oh = C.MeleeSpeeds()
        if mh then
            Rescale("mh", mh); Rescale("oh", oh)
            Swing.speed.mh, Swing.speed.oh = mh, oh
        end
    end, "player")
    ns:On("UNIT_RANGEDDAMAGE", function()
        local r = C.RangedSpeed()
        if r then Rescale("ranged", r); Swing.speed.ranged = r end
    end, "player")
    ns:On("PLAYER_EQUIPMENT_CHANGED", function(_, slot)
        Swing:RefreshSpeeds(); Swing:RefreshIcons()
        if slot == 16 or slot == 17 then
            ns:Log("weapon slot %s changed: off-hand weapon=%s, dual wield=%s, in combat=%s",
                C.Show(slot), C.Show(Swing.offHandWeapon), tostring(Swing:IsDualWield()), tostring(InCombatLockdown()))
        end
    end)
    self:RefreshIcons()
    ns:On("PLAYER_TARGET_CHANGED", function() Swing:QueryRange() end)
    ns:On("PLAYER_DEAD", function()
        Swing.meleeOn, Swing.rangedOn = false, false
        Swing.armed = nil
        for _, h in ipairs(HANDS) do Swing:Clear(h) end
    end)
end

---------------------------------------------------------------------------
-- Armed next swing (Heroic Strike, Cleave, Maul, Raptor Strike)
---------------------------------------------------------------------------
-- These replace the next melee swing. While one waits for the swing the game
-- reports it as the current spell (the same check that lights its action
-- button); it ends when the swing lands, it is cancelled, or rage runs out.
Swing.armed = nil -- { name, icon }
local loggedArmed = 0
ns:OnLogReset(function() loggedArmed = 0 end)

local function IsCurrentName(name)
    if not (C_Spell and C_Spell.IsCurrentSpell) then return false end
    local ok, cur = pcall(C_Spell.IsCurrentSpell, name)
    return ok and C.Readable(cur) and cur == true
end

function Swing:CheckArmed(reason)
    local found
    for name in pairs(ns.Data:NextSwingNames()) do
        if IsCurrentName(name) then found = name break end
    end
    local was = self.armed and self.armed.name
    if found == was then return end
    if found then
        self.armed = { name = C.GetSpellName(found) or found, icon = C.GetSpellIcon(found) }
    else
        self.armed = nil
    end
    if loggedArmed < 30 then
        loggedArmed = loggedArmed + 1
        ns:Log("next swing: %s (%s)", found and ("armed " .. found) or ("cleared " .. tostring(was)), reason)
    end
    ns:Wake()
end

-- A completed hard cast (e.g. warrior Slam) restarts melee swings. Log
-- (v0.5.5, three Slams while dual wielding): no swings land during the cast;
-- the main hand swings one full speed after it ends, the off hand half its
-- speed after. PLAYER_SWING only fires on the swing itself, so without this
-- the bar would show "ready" until the next swing instead of the new timer.
function Swing:OnCastCompleted()
    if not self.meleeOn then return end
    local predicted = not self.nativeMelee
    local now = GetTime()
    self:Start("mh", predicted, now)
    if self:IsDualWield() then
        local t = timers.oh
        local dur = self.speed.oh
        if predicted or not dur then
            self:Start("oh", predicted, now)
        elseif not (t.finish and t.finish > now + dur / 2) then
            self:Start("oh", false, now + dur / 2 - dur)
        end
    end
end

---------------------------------------------------------------------------
-- Lanes for the bar
---------------------------------------------------------------------------
local lanes = {
    mh = { kind = "mh" },
    oh = { kind = "oh" },
    ranged = { kind = "ranged" },
}

local function Predict(now)
    if not ns.db.predictSwings or not Swing.meleeOn or Swing.nativeMelee then return end
    if Swing.inRange.mh == false then return end
    local t = timers.mh
    if t.finish and now >= t.finish then Swing:Start("mh", true, t.finish) end
    if Swing:IsDualWield() then
        t = timers.oh
        if t.finish and now >= t.finish then Swing:Start("oh", true, t.finish) end
    end
end

-- Weapon icons, cached (looked up on equip changes, not every frame).
local slotIcons = {}
function Swing:RefreshIcons()
    for _, slot in ipairs({ 16, 17, 18 }) do slotIcons[slot] = C.SlotIcon(slot) end
end

local function FillLane(lane, hand, now, label, colorKey, on, slot, iconOverride)
    local t = timers[hand]
    local colors = ns.db.colors
    local icon = iconOverride or slotIcons[slot]
    if lane.label ~= label or lane.icon ~= icon then
        lane.serial = (lane.serial or 0) + 1 -- static parts changed: bar redraws them
    end
    lane.label = label
    lane.fill = hand -- "mh" | "oh" | "ranged"
    lane.color = colors[colorKey]
    lane.icon = icon
    lane.reverse = false
    lane.latency, lane.queue, lane.ticks, lane.windup = nil, nil, nil, nil
    if t.finish and now < t.finish then
        lane.state = "active"
        lane.start, lane.finish = t.start, t.finish
        lane.alpha = t.predicted and 0.75 or 1
        lane.rightText = nil
    elseif on then
        lane.state = "ready"
        lane.start, lane.finish = nil, nil
        local outOfRange = Swing.inRange[hand == "ranged" and "ranged" or "mh"] == false
        lane.alpha = outOfRange and 0.35 or 0.6
        lane.rightText = outOfRange and "Out of range" or nil
    else
        return false
    end
    return true
end

-- Fills `out` (array) with 0-2 swing lanes. Returns the number of lanes.
function Swing:GetLanes(now, out)
    wipe(out)
    Predict(now)
    local db = self.db or ns.db

    local rangedLive = db.showRanged and (self.rangedOn or self:Running("ranged", now))
    local meleeLive = db.showMelee and (self.meleeOn or self:Running("mh", now) or self:Running("oh", now))
    if rangedLive and meleeLive then
        -- Whichever was used most recently wins.
        if (timers.ranged.last or 0) >= math.max(timers.mh.last or 0, timers.oh.last or 0) or self.rangedOn then
            meleeLive = false
        else
            rangedLive = false
        end
    end

    if rangedLive then
        if FillLane(lanes.ranged, "ranged", now, self.rangedLabel or SWING_TIMER_RANGED or "Ranged", "ranged", self.rangedOn, 18) then
            local l = lanes.ranged
            if not self.autoShot then
                -- Wand Shoot / Throw fire once per press. A press inside the
                -- spell queue window is held and fires as the timer ends
                -- (confirmed for wands, v0.7.1), so mark that window.
                l.queue = C.SpellQueueWindow()
            elseif db.showAutoShotWindow then
                -- Mark the wind-up; moving through it holds the shot until you stop.
                l.windup = AUTO_SHOT_WINDUP
                local inWindup = l.state == "ready" or (l.finish and l.finish - now <= AUTO_SHOT_WINDUP)
                if self.moving and self.rangedOn and inWindup and not l.rightText then
                    l.rightText = "Stop to shoot"
                end
            end
            out[1] = l
        end
    elseif meleeLive then
        -- An armed next-swing ability takes over the main-hand label and icon,
        -- and the bar glows (lane.armed) until the swing lands.
        local armed = db.showNextSwing and self.armed
        local mhLabel = armed and armed.name or SWING_TIMER_MAIN_HAND or "Main Hand"
        if FillLane(lanes.mh, "mh", now, mhLabel, "mainhand", self.meleeOn, 16, armed and armed.icon) then
            lanes.mh.armed = armed and true or nil
            out[#out + 1] = lanes.mh
        end
        if self:IsDualWield() and db.dualLayout == "split" then
            if FillLane(lanes.oh, "oh", now, SWING_TIMER_OFF_HAND or "Off Hand", "offhand", self.meleeOn, 17) then
                out[#out + 1] = lanes.oh
            end
        end
    end
    return #out
end

---------------------------------------------------------------------------
-- Ranged probe (diagnostic: wands, Throw): does moving delay or cancel
-- the shot near the end of the timer, as in Classic? Logs each shot's
-- interval against the ranged speed, and movement relative to the timer.
---------------------------------------------------------------------------
local probe = { budget = 0, moving = false, movedSince = false, lastStop = nil, lastShot = nil }
ns:OnLogReset(function() probe.budget = 0 end)

local function ProbeLog(fmt, ...)
    if probe.budget >= 120 then return end
    probe.budget = probe.budget + 1
    ns:Log("ranged probe: " .. fmt, ...)
end

local function ShotLeft(now)
    local t = timers.ranged
    if t.finish then return string.format("%.2fs left", t.finish - now) end
    return "no timer"
end

function Swing:ProbeShot(now, duration)
    local prev = probe.lastShot
    probe.lastShot = now
    if prev then
        local interval = now - prev
        local speed = (C.Readable(duration) and type(duration) == "number") and duration or self.speed.ranged
        if speed and interval < speed * 3 then
            ProbeLog("interval %.2fs (speed %.2f, %+.2f) moved=%s%s", interval, speed, interval - speed,
                tostring(probe.movedSince or probe.moving),
                probe.lastStop and string.format(", stopped %.2fs before shot", now - probe.lastStop) or "")
        end
    end
    probe.movedSince = probe.moving
    probe.lastStop = nil
end

local function OnMove(started)
    probe.moving = started
    if started then probe.movedSince = true else probe.lastStop = GetTime() end
    if Swing.rangedOn or Swing:Running("ranged", GetTime()) then
        ProbeLog("%s moving, %s", started and "started" or "stopped", ShotLeft(GetTime()))
    end
end

local function OnRangedCastEvent(event, _, _, spellID)
    if C.IsSecret(spellID) or not ns.Data:IsRanged(spellID, C.GetSpellName(spellID)) then return end
    ProbeLog("%s %s, %s, moving=%s", event, C.Show(C.GetSpellName(spellID)), ShotLeft(GetTime()), tostring(probe.moving))
end

function Swing:EnableProbe()
    ns:On("PLAYER_STARTED_MOVING", function() OnMove(true) end)
    ns:On("PLAYER_STOPPED_MOVING", function() OnMove(false) end)
    for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_SUCCEEDED" }) do
        ns:On(ev, OnRangedCastEvent, "player")
    end
    ns:On("START_AUTOREPEAT_SPELL", function() probe.lastShot = nil; ProbeLog("auto-repeat on (%s), moving=%s", Swing.autoShot and "Auto Shot" or "other", tostring(probe.moving)) end)
    ns:On("STOP_AUTOREPEAT_SPELL", function() ProbeLog("auto-repeat off, %s", ShotLeft(GetTime())) end)
end
