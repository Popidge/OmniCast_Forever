-- OmniCast Forever: scripted demo so the bar can be checked out of combat.
-- Sequence: cast (pushback, repeat queued) -> second cast (next spell queued)
--           -> success flash -> GCD -> channel (ticks, swing strip)
--           -> ranged shot -> dual-wield swings with a GCD strip.
local _, ns = ...
local C = ns.Compat

local T = ns:NewModule("TestMode")
T.active = false

local t0
local DURATION = 18.5
local lanes = {}
local demoQueued = {}

local function Lane(key)
    local l = lanes[key]
    if not l then l = { kind = "test" }; lanes[key] = l end
    l.latency, l.queue, l.ticks, l.rightText, l.value, l.reverse = nil, nil, nil, nil, nil, false
    l.tickInterval, l.target, l.delay, l.pushAt = nil, nil, nil, nil
    l.alpha = 1
    return l
end

local function Timed(l, startOffset, dur)
    l.state = "active"
    l.start = t0 + startOffset
    l.finish = l.start + dur
    return l
end

-- Repeating swing that started at `base` seconds into the script.
local function Looping(l, t, base, speed)
    local k = math.floor((t - base) / speed)
    return Timed(l, base + k * speed, speed)
end

local function Spell(l, id, fallback)
    l.label = C.GetSpellName(id) or fallback
    l.icon = C.GetSpellIcon(id)
    return l
end

function T:Start()
    self.active = true
    t0 = GetTime()
    ns:Wake()
    ns:Print("demo playing (%.0fs) - /oc test again to stop", DURATION)
end

function T:Stop()
    self.active = false
end

function T:Toggle()
    if self.active then self:Stop() else self:Start() end
end

function T:BuildView(now, view)
    local t = now - t0
    if t >= DURATION then self:Stop() return end
    local colors, main = ns.db.colors, view.main
    local qw = C.SpellQueueWindow()

    local function Queue(id, fallback)
        demoQueued.name, demoQueued.icon = C.GetSpellName(id) or fallback, C.GetSpellIcon(id)
        view.queued = demoQueued
    end

    if t < 2.4 then
        -- Frostbolt #1: 2.0s cast, hit at 0.9s for 0.4s of pushback, then a
        -- second Frostbolt pressed inside the queue window (a repeat queue).
        local l = Spell(Timed(Lane("cast"), 0, 2.0), 116, "Frostbolt")
        l.color, l.fill = colors.cast, "cast"
        l.latency, l.queue, l.target = 0.12, qw, "Training Dummy"
        if t >= 0.9 then
            l.finish, l.delay, l.pushAt = l.finish + 0.4, 0.4, t0 + 0.9
        end
        if t >= 2.4 - qw + 0.05 then Queue(116, "Frostbolt") end
        main[1] = l
    elseif t < 4.4 then
        -- Frostbolt #2 starts straight away (it was queued); Fire Blast queued at the end.
        local l = Spell(Timed(Lane("cast2"), 2.4, 2.0), 116, "Frostbolt")
        l.color, l.fill = colors.cast, "cast"
        l.latency, l.queue, l.target = 0.12, qw, "Training Dummy"
        if t >= 4.4 - qw + 0.05 then Queue(2136, "Fire Blast") end
        main[1] = l
    elseif t < 4.7 then
        local l = Spell(Lane("hold"), 116, "Frostbolt")
        l.state, l.value, l.color, l.fill = "hold", 1, colors.success, "success"
        l.alpha = math.min(1, (4.7 - t) / 0.2 + 0.2)
        main[1] = l
    elseif t < 6.2 then
        local l = Spell(Timed(Lane("gcd"), 4.7, 1.5), 2136, "Fire Blast")
        l.color, l.fill = colors.gcd, "gcd"
        main[1] = l
    elseif t < 9.2 then
        local l = Spell(Timed(Lane("channel"), 6.2, 3.0), 5143, "Arcane Missiles")
        l.color, l.reverse, l.tickInterval, l.latency, l.fill = colors.channel, true, 1, 0.12, "channel"
        l.target = "Training Dummy"
        main[1] = l
        local s = Looping(Lane("strip"), t, 6.2, 2.4)
        s.color, s.fill = colors.mainhand, "mh"
        view.strip = s
    elseif t < 12.0 then
        local l = Spell(Timed(Lane("ranged"), 9.2, 2.8), 75, "Auto Shot")
        l.color, l.fill = colors.ranged, "ranged"
        l.icon = C.SlotIcon(18) or l.icon
        main[1] = l
    else
        local mh = Looping(Lane("mh"), t, 12.0, 2.6)
        mh.label, mh.color, mh.icon, mh.fill = SWING_TIMER_MAIN_HAND or "Main Hand", colors.mainhand, C.SlotIcon(16), "mh"
        local oh = Looping(Lane("oh"), t, 12.2, 1.9)
        oh.label, oh.color, oh.fill = SWING_TIMER_OFF_HAND or "Off Hand", colors.offhand, "oh"
        main[1], main[2] = mh, oh
        if t >= 13.2 and t < 14.2 then
            local g = Spell(Timed(Lane("gcdstrip"), 13.2, 1.0), 1752, "Sinister Strike")
            g.color, g.fill = colors.gcd, "gcd"
            view.strip = g
        end
    end
end
