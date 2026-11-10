-- OmniCast Forever: the bar itself. One fixed-size frame; the contents adapt:
--   cast / channel        -> full bar (+ swing strip underneath)
--   melee or ranged swing -> full bar, split into main/off-hand when dual wielding (+ GCD strip)
--   global cooldown only  -> full bar
local _, ns = ...
local C = ns.Compat

local Bar = ns:NewModule("Bar")

local TEXTURES = {
    Blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    Flat     = "Interface\\Buttons\\WHITE8X8",
    Raid     = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    Skill    = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}
Bar.TEXTURES = TEXTURES

-- "modern": Forever's own cast bar / swing timer art (atlases from the
-- exported Blizzard UI). The flat styles use a texture tinted with db.colors.
local STYLES = {
    modern = {
        inset = 2,      -- the frame atlas sits 2px outside the fill (Blizzard: -2,2 / 2,-2)
        iconGap = 5,    -- Blizzard floats the icon 5px left of the bar, unbordered
        atlas = true,
    },
    simple = {
        inset = 3,
        backdrop = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        },
    },
    minimal = {
        inset = 1,
        borderColor = { 0, 0, 0, 1 },
        backdrop = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        },
    },
}
STYLES.classic = STYLES.simple -- pre-0.3 name
Bar.STYLES = STYLES

-- lane.fill -> Forever atlas (modern style)
local FILL_ATLAS = {
    cast        = "ui-castingbar-filling-standard",
    success     = "ui-castingbar-full-standard",
    channel     = "ui-castingbar-filling-channel",
    channelDone = "ui-castingbar-full-channel",
    failed      = "ui-castingbar-interrupted",
    gcd         = "ui-castingbar-uninterruptable",
    mh          = "ui-swingtimerbar-filling-mainhand",
    oh          = "ui-swingtimerbar-filling-offhand",
    ranged      = "ui-swingtimerbar-filling-ranged",
}
local SPARK_ATLAS = {
    default = "ui-castingbar-pip",
    failed  = "ui-castingbar-pip-red",
    mh      = "ui-swingtimerbar-pip",
    oh      = "ui-swingtimerbar-pip",
    ranged  = "ui-swingtimerbar-pip",
}
local FRAME_ATLAS = { bg = "ui-castingbar-background", border = "ui-castingbar-frame" }

local function AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- True when the modern style is selected and every atlas it needs exists.
local function CheckAtlases()
    local missing = {}
    for _, t in ipairs({ FILL_ATLAS, SPARK_ATLAS, FRAME_ATLAS }) do
        for _, name in pairs(t) do
            if not AtlasExists(name) then missing[#missing + 1] = name end
        end
    end
    if #missing > 0 then
        ns:Log("modern style unavailable, missing atlases: %s", table.concat(missing, ", "))
        return false
    end
    local sizes = {}
    for fill, name in pairs(FILL_ATLAS) do
        local info = C_Texture.GetAtlasInfo(name)
        sizes[#sizes + 1] = string.format("%s %dx%d", fill, info.width, info.height)
    end
    table.sort(sizes)
    ns:Log("fill atlas sizes: %s", table.concat(sizes, ", "))
    return true
end

---------------------------------------------------------------------------
-- Clean scaling for the modern frame art.
-- The bar grows; the frame does not. Like native UI frames, the background
-- and frame art are nine-sliced: corners and edges are drawn at Blizzard's
-- native thickness (times the "frame thickness" setting) and only the middle
-- stretches. Blizzard draws the frame atlas 15px tall around an 11px fill
-- (2px frame), and the background 13px tall (1px), which sets the native size.
--
-- Slice margins come from the atlas's own sliceData when it has some.
-- Otherwise the left/right caps are square (rounded ends fit within the
-- height) and the vertical split is the centre row: the top and bottom halves
-- keep their shape, and the straight centre row stretches. That gives a pill
-- shape with straight sides at any height.
---------------------------------------------------------------------------
local NINE = { "TL", "T", "TR", "L", "C", "R", "BL", "B", "BR" }

local function NewNine(parent, layer, sub)
    local n = {}
    for _, k in ipairs(NINE) do n[k] = parent:CreateTexture(nil, layer, nil, sub) end
    return n
end

local loggedAtlas = {}
-- nativeH: the height (UI px) Blizzard draws this atlas at.
local function NineSetAtlas(n, atlas, nativeH)
    local info = C_Texture.GetAtlasInfo(atlas)
    local src = info and (info.file or info.filename)
    if not src then return false end
    local W, H = info.width, info.height
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local sd = info.sliceData
    local ml, mr, mt, mb
    if sd and ((sd.marginLeft or 0) > 0 or (sd.marginTop or 0) > 0) then
        ml, mr, mt, mb = sd.marginLeft, sd.marginRight, sd.marginTop, sd.marginBottom
    else
        local cap = math.min(H, W / 2 - 1)
        ml, mr = cap, cap
        mt, mb = H / 2 - 0.5, H / 2 - 0.5 -- 1 atlas px centre row stretches
    end
    local u0, u1, u2, u3 = l, l + (r - l) * ml / W, r - (r - l) * mr / W, r
    local v0, v1, v2, v3 = t, t + (b - t) * mt / H, b - (b - t) * mb / H, b
    for _, k in ipairs(NINE) do n[k]:SetTexture(src) end
    n.TL:SetTexCoord(u0, u1, v0, v1); n.T:SetTexCoord(u1, u2, v0, v1); n.TR:SetTexCoord(u2, u3, v0, v1)
    n.L:SetTexCoord(u0, u1, v1, v2);  n.C:SetTexCoord(u1, u2, v1, v2); n.R:SetTexCoord(u2, u3, v1, v2)
    n.BL:SetTexCoord(u0, u1, v2, v3); n.B:SetTexCoord(u1, u2, v2, v3); n.BR:SetTexCoord(u2, u3, v2, v3)
    n.px = nativeH / H -- UI px per atlas px at thickness 1
    n.ml, n.mr, n.mt, n.mb = ml, mr, mt, mb
    if not loggedAtlas[atlas] then
        loggedAtlas[atlas] = true
        ns:Log("atlas %s: %dx%d, slice %s", atlas, W, H,
            sd and string.format("L%s T%s R%s B%s", tostring(sd.marginLeft), tostring(sd.marginTop),
                tostring(sd.marginRight), tostring(sd.marginBottom)) or "none")
    end
    return true
end

-- Places the nine-slice around `region`, `out` px past it on every side.
-- `scale` is the frame thickness multiplier.
local function NineLayout(n, region, out, scale, totalW, totalH)
    local f = (n.px or 1) * scale
    local L, R = n.ml * f, n.mr * f
    local T, B = n.mt * f, n.mb * f
    if L + R > totalW then local k = totalW / (L + R); L, R = L * k, R * k end
    if T + B > totalH then local k = totalH / (T + B); T, B = T * k, B * k end
    for _, k in ipairs(NINE) do n[k]:ClearAllPoints() end
    n.TL:SetPoint("TOPLEFT", region, "TOPLEFT", -out, out);          n.TL:SetSize(L, T)
    n.TR:SetPoint("TOPRIGHT", region, "TOPRIGHT", out, out);         n.TR:SetSize(R, T)
    n.BL:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT", -out, -out);   n.BL:SetSize(L, B)
    n.BR:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", out, -out);  n.BR:SetSize(R, B)
    n.T:SetPoint("TOPLEFT", n.TL, "TOPRIGHT");       n.T:SetPoint("BOTTOMRIGHT", n.TR, "BOTTOMLEFT")
    n.B:SetPoint("TOPLEFT", n.BL, "TOPRIGHT");       n.B:SetPoint("BOTTOMRIGHT", n.BR, "BOTTOMLEFT")
    n.L:SetPoint("TOPLEFT", n.TL, "BOTTOMLEFT");     n.L:SetPoint("BOTTOMRIGHT", n.BL, "TOPRIGHT")
    n.R:SetPoint("TOPLEFT", n.TR, "BOTTOMLEFT");     n.R:SetPoint("BOTTOMRIGHT", n.BR, "TOPRIGHT")
    n.C:SetPoint("TOPLEFT", n.TL, "BOTTOMRIGHT");    n.C:SetPoint("BOTTOMRIGHT", n.BR, "TOPLEFT")
end

local function NineShown(n, shown)
    for _, k in ipairs(NINE) do n[k]:SetShown(shown) end
end

local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
local WHITE = { 1, 1, 1 }

local function FontPath()
    local path = GameFontHighlightSmall and GameFontHighlightSmall:GetFont()
    return path or STANDARD_TEXT_FONT
end

local function BarTexture()
    local name = ns.db.texture
    if TEXTURES[name] then return TEXTURES[name] end
    local lsm = C.LSM()
    local path = lsm and lsm:Fetch("statusbar", name, true)
    return path or TEXTURES.Blizzard
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
local function CreateLane(parent, isStrip)
    local sb = CreateFrame("StatusBar", nil, parent)
    sb.isStrip = isStrip
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)

    sb.bg = sb:CreateTexture(nil, "BACKGROUND")
    sb.bg:SetAllPoints()
    sb.bg:SetColorTexture(0, 0, 0, isStrip and 0.75 or 0.3)

    sb.lat = sb:CreateTexture(nil, "ARTWORK", nil, 3)
    sb.lat:SetColorTexture(1, 1, 1, 1)
    sb.queue = sb:CreateTexture(nil, "OVERLAY", nil, 1)
    sb.queue:SetColorTexture(1, 1, 1, 1)
    sb.queue:SetWidth(1)

    sb.spark = sb:CreateTexture(nil, "OVERLAY", nil, 2)
    sb.spark:SetTexture(SPARK)
    sb.spark:SetBlendMode("ADD")

    sb.ticks = {}

    if not isStrip then
        -- Pushback flash: brief tint over the whole lane.
        sb.flash = sb:CreateTexture(nil, "OVERLAY", nil, 3)
        sb.flash:SetAllPoints()
        sb.flash:SetColorTexture(1, 1, 1, 1)
        sb.flash:SetBlendMode("ADD")
        sb.flash:Hide()

        -- Armed next swing (Heroic Strike...): soft pulsing glow over the lane.
        sb.glow = sb:CreateTexture(nil, "OVERLAY", nil, 0)
        sb.glow:SetAllPoints()
        sb.glow:SetColorTexture(1, 1, 1, 1)
        sb.glow:SetBlendMode("ADD")
        sb.glow:Hide()

        local holder = CreateFrame("Frame", nil, sb)
        holder:SetAllPoints()
        holder:SetFrameLevel(sb:GetFrameLevel() + 3)
        -- [spell name ............ target  +0.4 1.2]
        sb.right = holder:CreateFontString(nil, "OVERLAY")
        sb.right:SetPoint("RIGHT", -3, 0)
        sb.right:SetJustifyH("RIGHT")
        sb.target = holder:CreateFontString(nil, "OVERLAY")
        sb.target:SetJustifyH("RIGHT")
        sb.target:SetWordWrap(false)
        sb.left = holder:CreateFontString(nil, "OVERLAY")
        sb.left:SetJustifyH("LEFT")
        sb.left:SetWordWrap(false)
        for _, fs in ipairs({ sb.left, sb.right, sb.target }) do
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 1)
        end
    end
    sb:Hide()
    return sb
end

function Bar:Create()
    local f = CreateFrame("Frame", "OmniCastForeverBar", UIParent, "BackdropTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end

    f.iconBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.iconBg:SetColorTexture(0, 0, 0, 0.5)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon:SetAllPoints(f.iconBg)

    -- The lane area: everything right of the icon. Lanes and the modern
    -- frame art are anchored to it.
    f.area = CreateFrame("Frame", nil, f)

    f.lanes = { CreateLane(f), CreateLane(f) }
    f.strip = CreateLane(f, true)
    f.strip:SetFrameLevel(f.lanes[1]:GetFrameLevel() + 5)

    -- Modern style: Forever's cast bar background + frame around the lane area.
    f.mBg = NewNine(f, "BACKGROUND", 2)
    local bf = CreateFrame("Frame", nil, f)
    bf:SetAllPoints(f.area)
    bf:SetFrameLevel(f.strip:GetFrameLevel() + 2)
    f.mBorder = NewNine(bf, "OVERLAY", 0)

    -- Queued spell: icon at the right end of the first lane (the queue-window
    -- end of the bar), above the fill and text, below the frame art.
    local q = CreateFrame("Frame", nil, f)
    q:SetFrameLevel(f.strip:GetFrameLevel() + 1)
    q.border = q:CreateTexture(nil, "BACKGROUND")
    q.border:SetAllPoints()
    q.border:SetColorTexture(0, 0, 0, 0.9)
    q.icon = q:CreateTexture(nil, "ARTWORK")
    q.icon:SetPoint("TOPLEFT", 1, -1)
    q.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    q.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    q:Hide()
    f.queued = q

    -- Mover overlay (unlocked / Edit Mode)
    local m = CreateFrame("Frame", nil, f)
    m:SetAllPoints()
    m:SetFrameLevel(f:GetFrameLevel() + 20)
    m.tex = m:CreateTexture(nil, "OVERLAY")
    m.tex:SetAllPoints()
    m.tex:SetColorTexture(0.25, 0.6, 1, 0.35)
    m.text = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.text:SetPoint("BOTTOM", m, "TOP", 0, 3)
    m.text:SetText("OmniCast Forever - drag to move")
    m:Hide()
    f.mover = m

    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Bar:SavePosition()
    end)

    f.alpha = 0
    f:SetAlpha(0)
    self.frame = f
end

-- Positions are stored per Edit Mode layout (like native frames), with
-- db.point/x/y as the fallback for layouts that haven't placed the bar yet.
function Bar:GetPosition()
    local key = ns.EditMode and ns.EditMode.LayoutKey and ns.EditMode:LayoutKey()
    local p = key and ns.db.layoutPositions[key]
    if p then return p.point, p.x, p.y end
    return ns.db.point or "CENTER", ns.db.x or 0, ns.db.y or 0
end

function Bar:ApplyPosition()
    local f = self.frame
    local point, x, y = self:GetPosition()
    f:ClearAllPoints()
    f:SetPoint(point, UIParent, point, x, y)
end

function Bar:SavePosition()
    local f = self.frame
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = math.floor(cx * scale - ux + 0.5)
    local y = math.floor(cy * scale - uy + 0.5)
    ns.db.point, ns.db.x, ns.db.y = "CENTER", x, y
    local key = ns.EditMode and ns.EditMode.LayoutKey and ns.EditMode:LayoutKey()
    if key then ns.db.layoutPositions[key] = { point = "CENTER", x = x, y = y } end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    if ns.EditMode and ns.EditMode.active then ns.EditMode:MarkDirty() end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function SetFont(fs, size)
    if fs then fs:SetFont(FontPath(), size, "") end
end

---------------------------------------------------------------------------
-- Text priority: [spell name ..... target  time]
-- Target-first: the target keeps its full width, the spell name truncates.
-- Name-first:   the spell name keeps its width, the target fills what's left
--               (and hides when there's no room). "auto" = name-first when the
--               icon is hidden, since the name is then the only thing saying
--               what you're casting.
-- The target may be a secret string, so it is never measured; only the
-- (always readable) spell name is.
---------------------------------------------------------------------------
local function NameFirst()
    local p = ns.db.textPriority
    if p == "name" then return true end
    if p == "target" then return false end
    return not (Bar.frame and Bar.frame.iconShown) -- effective, after size clamping
end

local function AnchorText(sb, nameFirst)
    sb.nameFirst = nameFirst
    sb.left:ClearAllPoints()
    sb.target:ClearAllPoints()
    if nameFirst then
        sb.left:SetPoint("LEFT", 4, 0)
        sb.target:SetPoint("LEFT", sb.left, "RIGHT", 6, 0)
        sb.target:SetPoint("RIGHT", sb.right, "LEFT", -6, 0)
    else
        sb.target:SetPoint("RIGHT", sb.right, "LEFT", -6, 0)
        sb.left:SetPoint("LEFT", 4, 0)
        sb.left:SetPoint("RIGHT", sb.target, "LEFT", -4, 0)
    end
end

-- Name-first sizing; re-run when the name or the time text changes width.
local function FitText(sb)
    if not sb.nameFirst then return end
    local w = sb:GetWidth()
    if not w or w <= 0 then return end
    local avail = w - 4 - 3 - sb.right:GetStringWidth() - 6
    local fs = sb.left
    local nameW = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    if nameW + 30 > avail then
        -- Not enough room for both: the name gets all of it, target hides.
        fs:SetWidth(math.max(1, avail))
        sb.target:SetShown(false)
    else
        fs:SetWidth(nameW + 1)
        sb.target:SetShown(sb.textOK == true)
    end
end
Bar.FitText = FitText

function Bar:Layout(mode)
    local f, db = self.frame, ns.db
    local style = Bar.style
    local inset = style.inset
    local k = 1 -- frame thickness: 1 = Blizzard native
    if Bar.modern then
        -- The bar grows, the frame doesn't: Blizzard's frame sits 2px outside
        -- the fill at native size, times the frame thickness setting.
        k = db.frameScale or 1
        inset = math.max(1, math.floor(2 * k + 0.5))
    end
    -- Every allowed combination must leave a drawable fill. The frame gives
    -- way first: at most it may take the bar down to a 4px fill.
    local maxInset = math.max(1, math.floor((db.height - 4) / 2))
    if inset > maxInset then
        inset = maxInset
        if Bar.modern then k = inset / 2 end
    end
    local ch = math.max(2, db.height - inset * 2)
    local left = inset

    -- The icon gives way next: drop it if it would squeeze the bar itself
    -- below MIN_AREA_W.
    local MIN_AREA_W = 40
    local iconW = Bar.modern and (db.height + math.floor((style.iconGap or 1) * k + 0.5)) or (ch + 1)
    local showIcon = db.showIcon and (db.width - inset * 2 - iconW) >= MIN_AREA_W
    f.iconShown = showIcon

    f.icon:SetShown(showIcon)
    f.iconBg:SetShown(showIcon and not Bar.modern)
    if showIcon then
        f.iconBg:ClearAllPoints()
        if Bar.modern then
            -- Full-height icon, floating left of the bar like Blizzard's.
            f.iconBg:SetPoint("TOPLEFT", 0, 0)
            f.iconBg:SetSize(db.height, db.height)
            left = db.height + math.floor((style.iconGap or 1) * k + 0.5) + inset
        else
            f.iconBg:SetPoint("TOPLEFT", inset, -inset)
            f.iconBg:SetSize(ch, ch)
            left = inset + ch + 1
        end
    end

    local area = f.area
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", left, -inset)
    area:SetPoint("BOTTOMRIGHT", -inset, inset)
    if Bar.modern then
        local areaW = math.max(1, db.width - left - inset)
        local bgOut = math.max(1, math.floor(k + 0.5))
        NineLayout(f.mBg, area, bgOut, k, areaW + bgOut * 2, ch + bgOut * 2)
        NineLayout(f.mBorder, area, inset, k, areaW + inset * 2, db.height)
    end

    local l1, l2 = f.lanes[1], f.lanes[2]
    l1:ClearAllPoints()
    l2:ClearAllPoints()
    local laneH
    if mode == "dual" then
        local top = math.floor((ch - 1) / 2 + 0.5)
        local bottom = ch - 1 - top
        l1:SetPoint("TOPLEFT", area, "TOPLEFT")
        l1:SetPoint("TOPRIGHT", area, "TOPRIGHT")
        l1:SetHeight(top)
        l2:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT")
        l2:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
        l2:SetHeight(bottom)
        laneH = bottom
    else
        l1:SetAllPoints(area)
        laneH = ch
    end

    local fontSize = math.min(db.fontSize, math.max(6, laneH - 1))
    local textOK = laneH >= 7
    for i, sb in ipairs(f.lanes) do
        SetFont(sb.left, fontSize)
        SetFont(sb.right, fontSize)
        SetFont(sb.target, fontSize)
        sb.textOK = textOK
        sb.left:SetShown(textOK)
        sb.right:SetShown(textOK)
        sb.target:SetShown(textOK)
        AnchorText(sb, NameFirst())
        local tc = db.colors.target
        sb.target:SetTextColor(tc[1], tc[2], tc[3])
        local h = (i == 1) and (mode == "dual" and ch - 1 - laneH or ch) or laneH
        if Bar.modern then
            -- Blizzard pip: 8x20 on an 11px fill, i.e. native width, poking
            -- 4.5px past each edge. Keep that at any height.
            sb.spark:SetSize(math.max(3, math.floor(8 * k + 0.5)), h + math.floor(9 * k + 0.5))
        else
            sb.spark:SetSize(math.max(8, math.floor(h * 0.9)), h * 2.2)
        end
    end

    -- Queued icon: square, the height of the first lane, at its right end.
    local qh = (mode == "dual") and (ch - 1 - laneH) or ch
    f.queued:ClearAllPoints()
    f.queued:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, 0)
    f.queued:SetSize(qh, qh)
    f.queuedW = qh
    f.queuedSpell = false -- re-apply the queued anchor after relayout

    local strip = f.strip
    strip:ClearAllPoints()
    strip:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT")
    strip:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT")
    strip:SetHeight(math.min(db.stripHeight, math.max(1, math.floor(ch / 3))))
    if Bar.modern then
        strip.spark:SetSize(math.max(2, math.floor(4 * k + 0.5)), strip:GetHeight() + math.floor(4 * k + 0.5))
    else
        strip.spark:SetSize(6, strip:GetHeight() * 3)
    end

    f.mode = mode
end

function Bar:ApplySettings()
    local f, db = self.frame, ns.db
    if not f then return end
    local style = STYLES[db.style] or STYLES.modern
    if style.atlas and Bar.atlasOK == nil then Bar.atlasOK = CheckAtlases() end
    if style.atlas and not Bar.atlasOK then style = STYLES.simple end -- fallback
    Bar.style = style
    Bar.modern = style.atlas == true

    f:SetSize(db.width, db.height)
    self:ApplyPosition()

    if Bar.modern then
        f:SetBackdrop(nil)
        NineShown(f.mBg, NineSetAtlas(f.mBg, FRAME_ATLAS.bg, 13))
        NineShown(f.mBorder, NineSetAtlas(f.mBorder, FRAME_ATLAS.border, 15))
    else
        NineShown(f.mBg, false)
        NineShown(f.mBorder, false)
        f:SetBackdrop(style.backdrop)
        local bg, border = db.colors.background, style.borderColor or db.colors.border
        f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    end
    -- Full lanes sit on the modern background art; flat styles need their own.
    f.lanes[1].bg:SetShown(not Bar.modern)
    f.lanes[2].bg:SetShown(not Bar.modern)

    -- Fill textures are chosen per lane in ApplyStatic; force a re-pick.
    for _, sb in ipairs({ f.lanes[1], f.lanes[2], f.strip }) do sb.fillKey = nil end

    f.mode = nil -- force relayout
    Bar.gen = (Bar.gen or 0) + 1 -- redraw every lane's static parts
    self:UpdateMover()
    ns:Wake()
end

-- Outside Edit Mode, /oc unlock shows a simple drag handle. In Edit Mode the
-- EditMode module's native-style selection overlay takes over.
function Bar:UpdateMover()
    local f = self.frame
    local unlocked = (not ns.db.locked) and not self.editMode
    f:EnableMouse(unlocked)
    f.mover:SetShown(unlocked)
end

---------------------------------------------------------------------------
-- Rendering
--
-- Per frame only progress-dependent things are touched (fill, spark, time
-- text, pushback flash). Everything else is "static" for a lane and redrawn
-- only when the lane object, its `serial`, or the settings generation change.
-- Lane producers bump `lane.serial` whenever label/target/colour/icon change.
---------------------------------------------------------------------------
Bar.gen = 0 -- bumped by ApplySettings

local function SetTextCached(fs, key, text)
    if fs[key] ~= text then
        fs[key] = text
        fs:SetText(text)
        return true
    end
    return false
end

local function ApplyStatic(sb, lane)
    local db = ns.db
    sb.lane, sb.serial, sb.gen = lane, lane.serial, Bar.gen
    -- Fill: Forever atlas for the lane's type (modern), or the chosen flat
    -- texture tinted with the lane colour.
    local fill = lane.fill or "cast"
    local key, spark
    if Bar.modern then
        key = FILL_ATLAS[fill] or FILL_ATLAS.cast
        spark = SPARK_ATLAS[fill] or SPARK_ATLAS.default
    else
        key = BarTexture()
    end
    if sb.fillKey ~= key then
        sb.fillKey = key
        sb:SetStatusBarTexture(key)
        local t = sb:GetStatusBarTexture()
        if t then t:SetDrawLayer("ARTWORK", 1) end
        if spark then
            sb.spark:SetAtlas(spark)
            sb.spark:SetBlendMode("BLEND")
        else
            sb.spark:SetTexture(SPARK)
            sb.spark:SetBlendMode("ADD")
        end
    end
    if Bar.modern then
        sb:SetStatusBarColor(1, 1, 1)
    else
        local c = lane.color or WHITE
        sb:SetStatusBarColor(c[1], c[2], c[3])
    end
    if sb.left then
        SetTextCached(sb.left, "_t", db.showSpellName and (lane.label or "") or "")
        -- Target may be a secret string: never compare it, just hand it to SetText.
        sb.target:SetText((db.showTarget and lane.target) or "")
        sb.right._t = nil
        FitText(sb)
    end
    sb.markerDur, sb.markerW = nil, nil -- force marker rebuild
end

local function HideMarkers(sb)
    sb.lat:Hide()
    sb.queue:Hide()
    for i = 1, #sb.ticks do sb.ticks[i]:Hide() end
end

-- Latency zone, queue marker and channel ticks depend only on the lane's
-- duration and the bar width, so they are rebuilt only when those change.
local function UpdateMarkers(sb, lane, dur, w)
    if sb.markerDur == dur and sb.markerW == w then return end
    sb.markerDur, sb.markerW = dur, w
    local db = ns.db
    HideMarkers(sb)
    if sb.isStrip or not dur or dur <= 0 then return end

    if db.showLatency and lane.latency then
        local side = lane.reverse and "LEFT" or "RIGHT"
        sb.lat:ClearAllPoints()
        sb.lat:SetPoint("TOP" .. side)
        sb.lat:SetPoint("BOTTOM" .. side)
        local lc = db.colors.latency
        sb.lat:SetVertexColor(lc[1], lc[2], lc[3], lc[4] or 0.5)
        sb.lat:SetWidth(math.max(1, math.min(lane.latency / dur, 1) * w))
        sb.lat:Show()
    end

    -- Spell queue window: from this line on, the next cast can be pressed.
    if db.showQueueWindow and lane.queue and dur > lane.queue then
        local x = (dur - lane.queue) / dur * w
        local qc = db.colors.queue
        sb.queue:ClearAllPoints()
        sb.queue:SetPoint("TOPLEFT", sb, "TOPLEFT", x, 0)
        sb.queue:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", x, 0)
        sb.queue:SetVertexColor(qc[1], qc[2], qc[3], qc[4] or 0.7)
        sb.queue:Show()
    end

    -- Channel ticks at real tick times from the channel start, so they stay
    -- correct when pushback cuts the channel short.
    local interval = lane.tickInterval or (lane.ticks and dur / lane.ticks)
    if db.showTicks and interval and interval > 0 then
        local n, e = 0, interval
        while e < dur - 0.05 and n < 30 do
            n = n + 1
            local t = sb.ticks[n]
            if not t then
                t = sb:CreateTexture(nil, "OVERLAY", nil, 1)
                t:SetColorTexture(1, 1, 1, 0.75)
                t:SetWidth(1)
                sb.ticks[n] = t
            end
            local frac = e / dur
            local x = (lane.reverse and (1 - frac) or frac) * w
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", sb, "TOPLEFT", x, 0)
            t:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", x, 0)
            t:Show()
            e = e + interval
        end
    end
end

local function RenderLane(sb, lane, now)
    local db = ns.db
    if not sb:IsShown() then sb:Show() end
    if sb.lane ~= lane or sb.serial ~= lane.serial or sb.gen ~= Bar.gen then
        ApplyStatic(sb, lane)
    end
    local alpha = lane.alpha or 1
    if sb.a ~= alpha then sb.a = alpha; sb:SetAlpha(alpha) end

    local active = lane.state == "active" and lane.start and lane.finish
    local value, remaining, dur
    if active then
        dur = lane.finish - lane.start
        local p = dur > 0 and (now - lane.start) / dur or 1
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        value = lane.reverse and (1 - p) or p
        remaining = lane.finish - now
        if remaining < 0 then remaining = 0 end
    else
        value = lane.value or 1
    end

    -- Secret timing (GCD in combat): the engine animates the fill from the
    -- duration object; our estimate only drives visibility and the markers.
    local timerDriven = false
    if lane.durationObject and sb.SetTimerDuration then
        if sb.timerObj ~= lane.durationObject then
            sb.timerObj = lane.durationObject
            local ok, err = pcall(sb.SetTimerDuration, sb, lane.durationObject, 0, 0)
            sb.timerOK = ok
            if not Bar.loggedTimer then
                Bar.loggedTimer = true
                ns:Log("SetTimerDuration from addon: %s %s", ok and "ok" or "FAILED", ok and "" or tostring(err))
            end
        end
        timerDriven = sb.timerOK
    elseif sb.timerObj then
        sb.timerObj = nil
        sb:SetMinMaxValues(0, 1)
    end
    if timerDriven then
        remaining = nil -- real remaining time is secret
    else
        sb:SetValue(value)
    end

    local w = sb:GetWidth()

    if db.showSpark and active and not timerDriven and value > 0 and value < 1 then
        sb.spark:SetPoint("CENTER", sb, "LEFT", value * w, 0)
        if not sb.spark:IsShown() then sb.spark:Show() end
    elseif sb.spark:IsShown() then
        sb.spark:Hide()
    end

    if active then
        UpdateMarkers(sb, lane, dur, w)
    elseif sb.markerDur ~= false then
        sb.markerDur, sb.markerW = false, nil
        HideMarkers(sb)
    end

    if sb.left then
        -- Pushback: flash on each hit, running total next to the time.
        local push = db.showPushback and active
        if push and lane.pushAt and now - lane.pushAt < 0.3 then
            local pc = db.colors.pushback
            sb.flash:SetVertexColor(pc[1], pc[2], pc[3], 0.6 * (1 - (now - lane.pushAt) / 0.3))
            sb.flash:Show()
        elseif sb.flash:IsShown() then
            sb.flash:Hide()
        end

        if lane.armed then
            local gc = db.colors.nextSwing
            local pulse = 0.5 + 0.5 * math.sin(now * 5.2) -- ~1.2s cycle
            sb.glow:SetVertexColor(gc[1], gc[2], gc[3], 0.10 + 0.14 * pulse)
            if not sb.glow:IsShown() then sb.glow:Show() end
        elseif sb.glow:IsShown() then
            sb.glow:Hide()
        end

        local r = lane.rightText
        if not r and db.showTime and remaining then r = string.format("%.1f", remaining) end
        if push and lane.delay and math.abs(lane.delay) >= 0.05 then
            local pc = db.colors.pushback
            r = string.format("|cff%02x%02x%02x%+.1f|r %s", pc[1] * 255, pc[2] * 255, pc[3] * 255, lane.delay, r or "")
        end
        if SetTextCached(sb.right, "_t", r or "") then FitText(sb) end
    end
end

local function ClearLane(sb)
    sb.lane = nil
    sb:Hide()
end

local view = { main = {} }
local swingOut = {}
local placeholder = { kind = "placeholder", fill = "cast", state = "hold", value = 1, label = "OmniCast Forever", rightText = "/oc lock", alpha = 0.7 }

function Bar:BuildView(now)
    local main = view.main
    wipe(main)
    view.strip = nil
    view.queued = nil
    if ns.TestMode.active then
        ns.TestMode:BuildView(now, view)
    else
        local cast = ns.Cast:GetLane(now)
        local nSwing = ns.Swing:GetLanes(now, swingOut)
        local gcd = ns.Cast:GetGCDLane(now)
        if cast then
            main[1] = cast
            if nSwing > 0 then view.strip = swingOut[1] end
        elseif nSwing > 0 then
            for i = 1, nSwing do main[i] = swingOut[i] end
            view.strip = gcd
        elseif gcd then
            main[1] = gcd
        end
    end
    if not ns.db.showStrip then view.strip = nil end
    if not ns.TestMode.active and ns.db.showQueued then view.queued = ns.Cast:GetQueued(now) end
    if #main == 0 and ((not ns.db.locked) or self.editMode) then
        placeholder.color = ns.db.colors.cast
        main[1] = placeholder
    end
    return view
end

function Bar:SetIcon(icon)
    local f = self.frame
    -- Icons are file IDs/paths; skip the comparison if one is ever secret.
    if C.Readable(icon) and f.iconCur == icon and f.iconSet then return end
    f.iconCur, f.iconSet = C.Readable(icon) and icon or nil, true
    f.icon:SetTexture(icon)
    f.icon:SetShown(icon ~= nil)
end

-- Shows/hides the queued spell icon; the first lane's time text moves left
-- of it so nothing overlaps.
function Bar:SetQueued(q)
    local f = self.frame
    local icon = q and q.icon
    if f.queuedSpell == q and f.queuedIcon == icon then return end
    f.queuedSpell, f.queuedIcon = q, icon
    local sb = f.lanes[1]
    if q then
        f.queued.icon:SetTexture(icon or 134400) -- question mark if unknown
        f.queued:Show()
        sb.right:SetPoint("RIGHT", -(f.queuedW or 0) - 4, 0)
    else
        f.queued:Hide()
        sb.right:SetPoint("RIGHT", -3, 0)
    end
    FitText(sb)
end

-- When idle the update loop sleeps; any game event (or ns:Wake) restarts it.
-- New activity always arrives through an event, so nothing is missed.
function Bar:Update(elapsed)
    local f = self.frame
    if self.sleeping then
        if not ns.awake then return end
        self.sleeping = false
    end
    ns.awake = false

    local now = GetTime()
    local v = self:BuildView(now)
    local main = v.main
    local n = #main

    if n > 0 then
        f.cleared = false
        local mode = n >= 2 and "dual" or "single"
        if f.mode ~= mode then self:Layout(mode) end
        RenderLane(f.lanes[1], main[1], now)
        if n >= 2 then RenderLane(f.lanes[2], main[2], now) elseif f.lanes[2].lane then ClearLane(f.lanes[2]) end
        if v.strip then RenderLane(f.strip, v.strip, now) elseif f.strip.lane then ClearLane(f.strip) end
        self:SetQueued(v.queued)
        if f.iconShown then self:SetIcon(main[1].icon) end
    end

    -- Fade in/out; the last frame stays drawn while fading.
    local target = (n > 0) and 1 or ns.db.idleAlpha
    local a = f.alpha + (target - f.alpha) * math.min(1, elapsed * 12)
    if math.abs(target - a) < 0.01 then a = target end
    if a ~= f.alpha then
        f.alpha = a
        f:SetAlpha(a)
    end

    -- Idle and fully faded: clear stale content (visible when idle opacity
    -- is above 0) and go to sleep.
    if n == 0 and a == target then
        if not f.cleared then
            f.cleared = true
            ClearLane(f.lanes[1]); ClearLane(f.lanes[2]); ClearLane(f.strip)
            self:SetQueued(nil)
            self:SetIcon(nil)
        end
        self.sleeping = true
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Bar:Enable()
    self:Create()
    self:ApplySettings()

    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, elapsed)
        ns.SafeCall(Bar.Update, Bar, elapsed)
    end)

end
