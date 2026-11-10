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
end

function Swing:IsDualWield()
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
    else
        Swing.nativeMelee = true
        ns.Cast:OnMeleeSwing(GetTime())
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

local function OnSpellSucceeded(_, _, _, spellID)
    if C.IsSecret(spellID) then return end
    local name = C.GetSpellName(spellID)
    local Data = ns.Data
    if Data:IsRanged(spellID, name) then
        Swing.rangedLabel = name
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
    ns:On("PLAYER_LEAVE_COMBAT", function() Swing.meleeOn = false end)
    ns:On("START_AUTOREPEAT_SPELL", function() Swing.rangedOn = true; Swing:RefreshSpeeds() end)
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
    ns:On("PLAYER_EQUIPMENT_CHANGED", function() Swing:RefreshSpeeds(); Swing:RefreshIcons() end)
    self:RefreshIcons()
    ns:On("PLAYER_TARGET_CHANGED", function() Swing:QueryRange() end)
    ns:On("PLAYER_DEAD", function()
        Swing.meleeOn, Swing.rangedOn = false, false
        for _, h in ipairs(HANDS) do Swing:Clear(h) end
    end)
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

local function FillLane(lane, hand, now, label, colorKey, on, slot)
    local t = timers[hand]
    local colors = ns.db.colors
    local icon = slotIcons[slot]
    if lane.label ~= label or lane.icon ~= icon then
        lane.serial = (lane.serial or 0) + 1 -- static parts changed: bar redraws them
    end
    lane.label = label
    lane.fill = hand -- "mh" | "oh" | "ranged"
    lane.color = colors[colorKey]
    lane.icon = icon
    lane.reverse = false
    lane.latency, lane.queue, lane.ticks = nil, nil, nil
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
            out[1] = lanes.ranged
        end
    elseif meleeLive then
        if FillLane(lanes.mh, "mh", now, SWING_TIMER_MAIN_HAND or "Main Hand", "mainhand", self.meleeOn, 16) then
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
