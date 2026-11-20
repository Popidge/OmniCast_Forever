-- OmniCast Forever: core namespace, saved settings, event routing, logging, slash commands.
local ADDON, ns = ...

ns.title = "OmniCast Forever"
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.version = (GetMeta and GetMeta(ADDON, "Version")) or "dev"

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
ns.defaults = {
    -- geometry (UI units; the bar never resizes itself)
    width = 250,
    height = 24,
    point = "CENTER",
    x = 0,
    y = -220,
    locked = true,

    -- look
    style = "modern",
    frameScale = 1,             -- modern style frame/spark thickness (1 = Blizzard native)           -- modern (Forever art) | simple | minimal
    texture = "Blizzard",
    fontSize = 11,
    showIcon = true,
    textPriority = "auto",      -- auto | name | target: which text truncates first
    showSpellName = true,
    showTime = true,
    showSpark = true,
    idleAlpha = 0,              -- 0 = fully hidden when nothing is happening

    -- cast features
    showLatency = true,
    showQueueWindow = true,
    showTicks = true,
    showQueued = true,          -- icon of the spell queued behind the current cast/GCD
    showPushback = true,        -- delay text + flash when damage pushes the cast back
    showTarget = false,         -- spell target name on casts/channels
    showAutoShotWindow = true,  -- Auto Shot wind-up zone + "Stop to shoot" while moving holds the shot
    showNextSwing = true,       -- glow + name while Heroic Strike/Cleave/... waits for the swing

    -- what to track
    showGCD = true,
    showMelee = true,
    showRanged = true,
    showStrip = true,           -- thin secondary strip (swing under a cast, GCD under swings)
    stripHeight = 4,
    dualLayout = "split",       -- split = stacked main/off hand | main = main hand only
    predictSwings = true,       -- fall back to weapon-speed prediction when no swing event arrives

    -- Blizzard UI
    hideBlizzardCastbar = true,
    hideBlizzardSwing = true,

    colors = {
        cast        = { 1.00, 0.70, 0.00 },
        channel     = { 0.00, 1.00, 0.00 },
        success     = { 0.00, 1.00, 0.00 },
        failed      = { 1.00, 0.00, 0.00 },
        gcd         = { 0.65, 0.65, 0.70 },
        mainhand    = { 0.95, 0.60, 0.15 },
        offhand     = { 0.85, 0.35, 0.25 },
        ranged      = { 0.45, 0.75, 1.00 },
        latency     = { 1.00, 0.10, 0.10, 0.50 },
        windup      = { 1.00, 0.85, 0.30, 0.45 },
        pushback    = { 1.00, 0.25, 0.25 },
        nextSwing   = { 1.00, 0.82, 0.30 },
        target      = { 0.85, 0.85, 0.85 },
        queue       = { 1.00, 1.00, 1.00, 0.70 },
        border      = { 0.75, 0.75, 0.75, 1.00 },
        background  = { 0.00, 0.00, 0.00, 0.60 },
    },

    debug = false,

    -- learned in play: spellID -> 0 no GCD | 1 GCD only | 2 GCD + own cooldown
    layoutPositions = {},       -- Edit Mode layout key -> { point, x, y }

    gcdSpells = {},
    spellGCD = {},              -- spellID -> GCD seconds (exact, learned out of combat)
    gcdLengths = {},            -- class -> GCD seconds
}

local function MergeDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            MergeDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function CopyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
    return c
end
ns.CopyTable = CopyTable

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
ns.modules = {}
function ns:NewModule(name)
    local m = { name = name }
    ns[name] = m
    table.insert(ns.modules, m)
    return m
end

local function CallModules(method)
    for _, m in ipairs(ns.modules) do
        if m[method] then ns.SafeCall(m[method], m) end
    end
end

---------------------------------------------------------------------------
-- Logging (persisted to SavedVariables so play sessions can be reviewed later)
---------------------------------------------------------------------------
local MAX_LOG = 1500
local preLog = {}

function ns:Log(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    local line = string.format("%.3f %s", GetTime(), msg)
    local store = OmniCastForeverLog and OmniCastForeverLog.entries or preLog
    store[#store + 1] = line
    if #store > MAX_LOG then table.remove(store, 1) end
    if ns.db and ns.db.debug then
        print("|cff66ccffOmniCast|r " .. msg)
    end
end

-- Per-type log caps keep a session's log readable. Modules register a reset
-- here so the caps restart on entering an instance or a boss encounter.
ns.logResets = {}
function ns:OnLogReset(fn)
    ns.logResets[#ns.logResets + 1] = fn
end
function ns:ResetLogBudgets()
    for _, fn in ipairs(ns.logResets) do pcall(fn) end
end

function ns:Print(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print("|cff66ccffOmniCast:|r " .. (ok and msg or tostring(fmt)))
end

local reportedErrors = {}
function ns.SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        err = tostring(err)
        if not reportedErrors[err] then
            reportedErrors[err] = true
            ns:Log("ERROR %s", err)
            geterrorhandler()(err)
        end
    end
    return ok
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

local function EventIsValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event)
    end
    return true
end
ns.EventIsValid = EventIsValid

-- Register a handler; unit-filtered when `unit` is given. Returns false if the
-- client does not know the event (it is logged, never thrown).
function ns:On(event, fn, unit)
    local list = handlers[event]
    if not list then
        if not EventIsValid(event) then
            ns:Log("event not available on this client: %s", event)
            return false
        end
        local ok
        if unit then
            ok = pcall(eventFrame.RegisterUnitEvent, eventFrame, event, unit)
        else
            ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
        if not ok then
            ns:Log("event registration failed: %s", event)
            return false
        end
        list = {}
        handlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

-- The bar's update loop sleeps while idle; events and ns:Wake() restart it.
ns.awake = true
function ns:Wake()
    ns.awake = true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    ns.awake = true
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        ns.SafeCall(list[i], event, ...)
    end
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end

    OmniCastForeverDB = OmniCastForeverDB or {}
    MergeDefaults(OmniCastForeverDB, ns.defaults)
    ns.db = OmniCastForeverDB
    -- v0.3: "classic" (tooltip border) was the old default; move everyone to
    -- the new Forever-art default once. It stays available as "simple".
    if not ns.db.styleMigrated then
        if ns.db.style == "classic" then ns.db.style = "modern" end
        ns.db.styleMigrated = true
    end

    OmniCastForeverLog = OmniCastForeverLog or {}
    OmniCastForeverLog.entries = OmniCastForeverLog.entries or {}
    for _, line in ipairs(preLog) do
        table.insert(OmniCastForeverLog.entries, line)
    end
    wipe(preLog)

    CallModules("Init")
end)

ns:On("PLAYER_LOGIN", function()
    local _, build, _, interface = GetBuildInfo()
    local _, class = UnitClass("player")
    ns:Log("=== session start: v%s build %s interface %s %s L%d ===",
        ns.version, tostring(build), tostring(interface), tostring(class), UnitLevel("player") or 0)
    CallModules("Enable")
end)

-- Called whenever a setting changes.
function ns:ApplySettings()
    CallModules("ApplySettings")
end

function ns:ResetPosition()
    local d = ns.defaults
    ns.db.point, ns.db.x, ns.db.y = d.point, d.x, d.y
    local key = ns.EditMode and ns.EditMode.LayoutKey and ns.EditMode:LayoutKey()
    if key then ns.db.layoutPositions[key] = nil end
    if ns.EditMode and ns.EditMode.active then ns.EditMode:MarkDirty() end
    ns:ApplySettings()
end

function ns:ResetAll()
    wipe(OmniCastForeverDB)
    MergeDefaults(OmniCastForeverDB, ns.defaults)
    ns:ApplySettings()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
    "/oc - open settings",
    "/oc unlock | lock - move the bar (also shown in Edit Mode)",
    "/oc test - play a demo sequence (cast, GCD, channel, ranged, dual-wield)",
    "/oc width <n> | height <n> - set bar size",
    "/oc reset - reset position   /oc resetall - reset every setting",
    "/oc probe - print client capability report (also saved to the log)",
    "/oc debug - toggle event logging to chat   /oc clearlog - clear saved log",
}

SLASH_OMNICASTFOREVER1 = "/oc"
SLASH_OMNICASTFOREVER2 = "/omnicast"
local function HandleSlash(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "" then
        if ns.Options and ns.Options.Open then ns.Options:Open() else for _, l in ipairs(HELP) do ns:Print(l) end end
    elseif cmd == "unlock" or cmd == "move" then
        ns.db.locked = false; ns:ApplySettings()
        ns:Print("unlocked - drag the bar, then /oc lock")
    elseif cmd == "lock" then
        ns.db.locked = true; ns:ApplySettings()
        ns:Print("locked")
    elseif cmd == "test" then
        ns.TestMode:Toggle()
    elseif (cmd == "width" or cmd == "height") and tonumber(arg) then
        local v = math.floor(tonumber(arg) + 0.5)
        if cmd == "width" then ns.db.width = math.max(60, math.min(800, v)) else ns.db.height = math.max(6, math.min(80, v)) end
        ns:ApplySettings()
        ns:Print("size %dx%d", ns.db.width, ns.db.height)
    elseif cmd == "reset" then
        ns:ResetPosition(); ns:Print("position reset")
    elseif cmd == "resetall" then
        ns:ResetAll(); ns:Print("all settings reset")
    elseif cmd == "probe" then
        ns.Debug:Probe()
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print("debug logging to chat %s", ns.db.debug and "ON" or "off")
    elseif cmd == "clearlog" then
        wipe(OmniCastForeverLog.entries); ns:Print("log cleared")
    elseif cmd == "version" then
        ns:Print("v%s", ns.version)
    else
        for _, l in ipairs(HELP) do ns:Print(l) end
    end
end

SlashCmdList.OMNICASTFOREVER = function(msg)
    ns.SafeCall(HandleSlash, msg)
end
