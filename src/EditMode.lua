-- OmniCast Forever: Edit Mode integration.
--
-- The bar behaves like a native Edit Mode frame: Blizzard's selection
-- highlight, click to select, live snapping (frames, screen, grid), arrow-key
-- nudging, a settings dialog, and a position per Edit Mode layout.
--
-- Taint safety: we READ Edit Mode state (registered frames, grid lines, snap
-- toggle, active layout) and only post-hook Blizzard functions. We never
-- write to Edit Mode tables. Writing into EditModeMagnetismManager would
-- taint Blizzard's Edit Mode code and cause blocked actions.
-- Exceptions, both built by Blizzard to be called from addon code:
--   * EditModeManagerFrame:ClearSelectedSystem(): runs through a secure
--     delegate out of combat (CreateSecureDelegate).
--   * EditModeManagerFrame:SetHasActiveChanges(true): "Clear taint off of the
--     value passed in"; enables Save / Revert for our pending changes.
local _, ns = ...

local EM = ns:NewModule("EditMode")
EM.active = false
EM.selected = false

local HIGHLIGHT_KIT = "editmode-actionbar-highlight"
local SELECTED_KIT = "editmode-actionbar-selected"

-- Copy of Blizzard's EditModeSystemSelectionLayout (EditModeSystemTemplates.lua),
-- which is file-local there and so not reachable from addons.
local SELECTION_LAYOUT = {
    ["TopRightCorner"]    = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
    ["TopLeftCorner"]     = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
    ["BottomLeftCorner"]  = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
    ["BottomRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
    ["TopEdge"]    = { atlas = "_%s-NineSlice-EdgeTop" },
    ["BottomEdge"] = { atlas = "_%s-NineSlice-EdgeBottom" },
    ["LeftEdge"]   = { atlas = "!%s-NineSlice-EdgeLeft" },
    ["RightEdge"]  = { atlas = "!%s-NineSlice-EdgeRight" },
    ["Center"]     = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}

local function EditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive
        and EditModeManagerFrame:IsEditModeActive() == true
end

-- Key for the active Edit Mode layout ("<type>:<name>"), or nil.
function EM:LayoutKey()
    if not (EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo) then return nil end
    local ok, info = pcall(EditModeManagerFrame.GetActiveLayoutInfo, EditModeManagerFrame)
    if ok and type(info) == "table" and type(info.layoutName) == "string" then
        return tostring(info.layoutType or 0) .. ":" .. info.layoutName
    end
end

---------------------------------------------------------------------------
-- Snapping (mirrors EditModeMagnetismManager's rules, read-only)
---------------------------------------------------------------------------
local function SnapEnabled()
    return EditModeManagerFrame and EditModeManagerFrame.IsSnapEnabled and EditModeManagerFrame:IsSnapEnabled()
end

-- Rect of any frame in UIParent coordinates.
local function RectInUIParent(frame)
    local l, b, w, h = frame:GetRect()
    if not l then return nil end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, w * s, h * s
end

-- left/bottom/w/h of our frame (UIParent space) -> snapped left/bottom.
local function Snap(left, bottom, w, h)
    local mm = EditModeMagnetismManager
    local range = ((mm and mm.magnetismRange) or 8) / UIParent:GetEffectiveScale()
    local right, top = left + w, bottom + h
    local cx, cy = left + w / 2, bottom + h / 2
    local bestX, bestY, lineX, lineY

    local function TryX(target, ours)
        local d = target - ours
        if math.abs(d) <= range and (not bestX or math.abs(d) < math.abs(bestX)) then bestX, lineX = d, target end
    end
    local function TryY(target, ours)
        local d = target - ours
        if math.abs(d) <= range and (not bestY or math.abs(d) < math.abs(bestY)) then bestY, lineY = d, target end
    end

    -- Screen edges and centre.
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    TryX(0, left); TryX(uw, right); TryX(uw / 2, cx)
    TryY(0, bottom); TryY(uh, top); TryY(uh / 2, cy)

    -- Other Edit Mode frames: sit beside/above/below, or align edges/centres
    -- with frames that are close on the other axis.
    local ours = ns.Bar.frame
    if mm and type(mm.magneticFrames) == "table" then
        for frame in pairs(mm.magneticFrames) do
            if frame ~= ours then
                local ok, fl, fb, fw, fh = pcall(function()
                    if not frame:IsVisible() then return nil end
                    return RectInUIParent(frame)
                end)
                if ok and fl then
                    local fr, ft = fl + fw, fb + fh
                    local nearV = fb <= top + range * 4 and ft >= bottom - range * 4
                    local nearH = fl <= right + range * 4 and fr >= left - range * 4
                    if nearV then
                        TryX(fr, left); TryX(fl, right)                        -- beside
                        TryX(fl, left); TryX(fr, right); TryX(fl + fw / 2, cx) -- aligned
                    end
                    if nearH then
                        TryY(ft, bottom); TryY(fb, top)                        -- above / below
                        TryY(fb, bottom); TryY(ft, top); TryY(fb + fh / 2, cy)
                    end
                end
            end
        end
    end

    -- Grid lines (only registered while the Edit Mode grid is shown).
    local grid = mm and mm.magneticGridLines
    if type(grid) == "table" then
        for _, x in pairs(grid.vertical or {}) do TryX(x, left); TryX(x, right); TryX(x, cx) end
        for _, y in pairs(grid.horizontal or {}) do TryY(y, bottom); TryY(y, top); TryY(y, cy) end
    end

    return left + (bestX or 0), bottom + (bestY or 0), lineX, lineY
end

---------------------------------------------------------------------------
-- Snap preview lines (our own, like Blizzard's red magnetism lines)
---------------------------------------------------------------------------
local lines
local function CreateLines()
    lines = CreateFrame("Frame", nil, UIParent)
    lines:SetAllPoints(UIParent)
    lines:SetFrameStrata("HIGH")
    lines.v = lines:CreateLine(nil, "OVERLAY")
    lines.h = lines:CreateLine(nil, "OVERLAY")
    for _, l in ipairs({ lines.v, lines.h }) do
        l:SetColorTexture(1, 0, 0, 1)
        l:SetThickness(1.5)
        l:Hide()
    end
end

local function ShowLines(x, y)
    if not lines then return end
    if x then
        lines.v:SetStartPoint("BOTTOMLEFT", lines, x, 0)
        lines.v:SetEndPoint("TOPLEFT", lines, x, 0)
        lines.v:Show()
    else
        lines.v:Hide()
    end
    if y then
        lines.h:SetStartPoint("BOTTOMLEFT", lines, 0, y)
        lines.h:SetEndPoint("BOTTOMRIGHT", lines, 0, y)
        lines.h:Show()
    else
        lines.h:Hide()
    end
end

---------------------------------------------------------------------------
-- Selection overlay
---------------------------------------------------------------------------
local sel, dialog
local drag

local function ApplyKit(kit)
    if sel.kit == kit then return end
    sel.kit = kit
    local ok = NineSliceUtil and pcall(NineSliceUtil.ApplyLayout, sel, SELECTION_LAYOUT, kit)
    if not ok and not EM.loggedKit then
        EM.loggedKit = true
        ns:Log("Edit Mode selection art unavailable; using a plain highlight")
    end
    sel.fallback:SetShown(not ok)
    if not ok then
        if kit == SELECTED_KIT then sel.fallback:SetColorTexture(1, 0.82, 0, 0.35)
        else sel.fallback:SetColorTexture(0.25, 0.6, 1, 0.35) end
    end
end

local function SetPositionBottomLeft(left, bottom)
    local f = ns.Bar.frame
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

local function CursorUI()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

local function OnDragUpdate()
    if not drag then return end
    local f = ns.Bar.frame
    local x, y = CursorUI()
    local left, bottom = x + drag.dx, y + drag.dy
    local lx, ly
    if SnapEnabled() then
        left, bottom, lx, ly = Snap(left, bottom, f:GetWidth(), f:GetHeight())
    end
    ShowLines(lx, ly)
    SetPositionBottomLeft(left, bottom)
end

local function StartDrag()
    if InCombatLockdown() then return end
    local f = ns.Bar.frame
    local l, b = RectInUIParent(f)
    if not l then return end
    local x, y = CursorUI()
    drag = { dx = l - x, dy = b - y }
    sel:SetScript("OnUpdate", OnDragUpdate)
end

local function StopDrag()
    if not drag then return end
    drag = nil
    sel:SetScript("OnUpdate", nil)
    ShowLines(nil, nil)
    ns.Bar:SavePosition()
end

local function Nudge(dx, dy)
    local l, b = RectInUIParent(ns.Bar.frame)
    if not l then return end
    SetPositionBottomLeft(l + dx, b + dy)
    ns.Bar:SavePosition()
end

function EM:Select()
    if self.selected then return end
    -- Deselect any Blizzard frame so only one thing is selected and arrow
    -- keys reach us. Safe out of combat (secure delegate, see header).
    if not InCombatLockdown() and EditModeManagerFrame.ClearSelectedSystem then
        self.clearing = true
        pcall(EditModeManagerFrame.ClearSelectedSystem, EditModeManagerFrame)
        self.clearing = false
    end
    self.selected = true
    ApplyKit(SELECTED_KIT)
    if not InCombatLockdown() then sel:EnableKeyboard(true) end
    self:ShowDialog()
end

function EM:Deselect()
    if not self.selected then return end
    self.selected = false
    ApplyKit(HIGHLIGHT_KIT)
    if not InCombatLockdown() then sel:EnableKeyboard(false) end
    if dialog then dialog:Hide() end
end

local function CreateSelection()
    local f = ns.Bar.frame
    sel = CreateFrame("Frame", nil, f)
    sel:SetAllPoints(f)
    sel:SetFrameStrata("MEDIUM")
    sel:SetFrameLevel(f:GetFrameLevel() + 40)
    sel:EnableMouse(true)
    sel:RegisterForDrag("LeftButton")
    sel.fallback = sel:CreateTexture(nil, "OVERLAY")
    sel.fallback:SetAllPoints()
    sel.fallback:Hide()

    sel:SetScript("OnMouseDown", function() EM:Select() end)
    sel:SetScript("OnDragStart", function() EM:Select(); StartDrag() end)
    sel:SetScript("OnDragStop", StopDrag)
    sel:SetScript("OnHide", StopDrag)
    sel:SetScript("OnKeyDown", function(self, key)
        local step = IsShiftKeyDown() and 10 or 1
        local moves = { UP = { 0, step }, DOWN = { 0, -step }, LEFT = { -step, 0 }, RIGHT = { step, 0 } }
        local m = moves[key]
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(m == nil) end
        if m then Nudge(m[1], m[2]) end
    end)
    sel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.title)
        GameTooltip:AddLine("Click to select, drag to move, arrow keys to nudge.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sel:Hide()
    ApplyKit(HIGHLIGHT_KIT)
end

---------------------------------------------------------------------------
-- Settings dialog (Edit Mode style)
---------------------------------------------------------------------------
local SLIDERS = {
    { key = "width",      label = "Width",           min = 80,  max = 600, step = 1,    fmt = "%d" },
    { key = "height",     label = "Height",          min = 8,   max = 60,  step = 1,    fmt = "%d" },
    { key = "frameScale", label = "Frame Thickness", min = 0.5, max = 3,   step = 0.25, fmt = "%.2fx" },
}

local function CreateDialog()
    dialog = CreateFrame("Frame", "OmniCastForeverEditModeDialog", UIParent)
    -- Same geometry as Blizzard's EditModeSystemSettingsDialog: 343px rows
    -- (100 label, 5 gap, 200 slider + value), 20px padding, stacked buttons.
    dialog:SetSize(383, 45 + #SLIDERS * 32 + 12 + 2 * 26 + 2 + 20)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(200)
    dialog:SetClampedToScreen(true)
    dialog:SetMovable(true)
    dialog:EnableMouse(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

    local ok, border = pcall(CreateFrame, "Frame", nil, dialog, "DialogBorderTranslucentTemplate")
    if ok and border then
        border:SetAllPoints()
    else
        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.8)
    end

    local title = dialog:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText(ns.title)

    local close = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() EM:Deselect() end)

    dialog.sliders = {}
    for i, def in ipairs(SLIDERS) do
        local row = CreateFrame("Frame", nil, dialog)
        row:SetSize(343, 32)
        row:SetPoint("TOPLEFT", 20, -45 - (i - 1) * 32)
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
        label:SetSize(100, 32)
        label:SetJustifyH("LEFT")
        label:SetPoint("LEFT")
        label:SetText(def.label)
        local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
        slider:SetSize(200, 32)
        slider:SetPoint("LEFT", label, "RIGHT", 5, 0)
        slider.def = def
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            if dialog.initializing then return end
            if def.step >= 1 then value = math.floor(value + 0.5) end
            ns.db[def.key] = value
            ns:ApplySettings()
            EM:MarkDirty()
        end, slider)
        dialog.sliders[i] = slider
    end

    local reset = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    reset:SetSize(343, 26)
    reset:SetPoint("TOPLEFT", 20, -45 - #SLIDERS * 32 - 12)
    reset:SetText(HUD_EDIT_MODE_RESET_POSITION or "Reset Position")
    reset:SetScript("OnClick", function() ns:ResetPosition() end)

    local more = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    more:SetSize(343, 26)
    more:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -2)
    more:SetText("More Settings")
    more:SetScript("OnClick", function() if ns.Options then ns.Options:Open() end end)

    dialog:Hide()
end

function EM:ShowDialog()
    if not dialog then CreateDialog() end
    dialog.initializing = true
    for _, slider in ipairs(dialog.sliders) do
        local def = slider.def
        local formatters = {
            [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
                MinimalSliderWithSteppersMixin.Label.Right,
                function(v) return string.format(def.fmt, v) end),
        }
        slider:Init(ns.db[def.key] or def.min, def.min, def.max, math.floor((def.max - def.min) / def.step + 0.5), formatters)
    end
    dialog.initializing = false
    if not dialog.placed then
        dialog.placed = true
        dialog:ClearAllPoints()
        dialog:SetPoint("BOTTOM", ns.Bar.frame, "TOP", 0, 30)
    end
    dialog:Show()
end

---------------------------------------------------------------------------
-- Save / Revert, like native frames
-- Changes made in Edit Mode are pending: Save keeps them, Revert All Changes
-- (or leaving Edit Mode without saving, which Blizzard handles as a revert)
-- puts back what was there when Edit Mode opened.
---------------------------------------------------------------------------
local GEOMETRY = { "width", "height", "frameScale", "point", "x", "y" }

local function CopyGeometry()
    local t = {}
    for _, k in ipairs(GEOMETRY) do t[k] = ns.db[k] end
    t.layoutPositions = ns.CopyTable(ns.db.layoutPositions)
    return t
end

local function ApplyGeometry(t)
    for _, k in ipairs(GEOMETRY) do ns.db[k] = t[k] end
    wipe(ns.db.layoutPositions)
    for key, pos in pairs(t.layoutPositions) do ns.db.layoutPositions[key] = ns.CopyTable(pos) end
    ns:ApplySettings()
end

function EM:Snapshot()
    self.snap = CopyGeometry()
    self.dirty = false
end

function EM:MarkDirty()
    if not self.active then return end
    self.dirty = true
    if EditModeManagerFrame.SetHasActiveChanges then
        pcall(EditModeManagerFrame.SetHasActiveChanges, EditModeManagerFrame, true)
    end
end

local function OnRevert()
    if not (EM.dirty and EM.snap) then return end
    -- Keep the pending values for a moment: "Save" on a preset layout makes a
    -- new layout, and Blizzard reverts before creating it (see OnNewLayout).
    local key = EM:LayoutKey()
    EM.stash = { geometry = CopyGeometry(), pos = key and ns.db.layoutPositions[key] }
    C_Timer.After(0, function() EM.stash = nil end)
    ApplyGeometry(EM.snap)
    EM.dirty = false
    ns:Log("Edit Mode revert: restored OmniCast position/size")
    if dialog and dialog:IsShown() then EM:ShowDialog() end
end

-- A new layout was made from the current (unsaved) one: carry our pending
-- position/size into it, as Blizzard does for its own frames.
local function OnNewLayout()
    local st = EM.stash
    EM.stash = nil
    if not st then return end
    for _, k in ipairs(GEOMETRY) do ns.db[k] = st.geometry[k] end
    local key = EM:LayoutKey()
    if key and st.pos then ns.db.layoutPositions[key] = ns.CopyTable(st.pos) end
    ns:ApplySettings()
    EM:Snapshot()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function EM:OnEnter()
    self:Snapshot()
    self.active = true
    ns.Bar.editMode = true
    ns.Bar:UpdateMover()
    if sel then sel:Show() end
    ns:Wake()
end

function EM:OnExit()
    self.active = false
    self:Deselect()
    StopDrag()
    if sel then sel:Hide() end
    ns.Bar.editMode = false
    ns.Bar:UpdateMover()
    ns:Wake()
end

function EM:Enable()
    if not (EditModeManagerFrame and EventRegistry) then
        ns:Log("Edit Mode not available; using /oc unlock for moving")
        return
    end
    CreateSelection()
    CreateLines()

    EventRegistry:RegisterCallback("EditMode.Enter", function() EM:OnEnter() end, EM)
    EventRegistry:RegisterCallback("EditMode.Exit", function() EM:OnExit() end, EM)

    -- Post-hooks only (observe, never change Blizzard's state).
    hooksecurefunc(EditModeManagerFrame, "SelectSystem", function() EM:Deselect() end)
    hooksecurefunc(EditModeManagerFrame, "ClearSelectedSystem", function()
        if not EM.clearing then EM:Deselect() end -- ignore our own call from Select()
    end)
    -- Save / Revert
    EventRegistry:RegisterCallback("EditMode.SavedLayouts", function() EM:Snapshot() end, EM)
    if EditModeManagerFrame.RevertAllChanges then
        hooksecurefunc(EditModeManagerFrame, "RevertAllChanges", OnRevert)
    end
    if EditModeManagerFrame.MakeNewLayout then
        hooksecurefunc(EditModeManagerFrame, "MakeNewLayout", OnNewLayout)
    end
    if EditModeManagerFrame.CheckForSystemActiveChanges then
        -- Blizzard recomputes "has changes" from its own frames only; keep
        -- Save/Revert enabled while ours are pending.
        hooksecurefunc(EditModeManagerFrame, "CheckForSystemActiveChanges", function()
            if EM.dirty then pcall(EditModeManagerFrame.SetHasActiveChanges, EditModeManagerFrame, true) end
        end)
    end

    if EditModeManagerFrame.UpdateLayoutInfo then
        -- Layout switched/loaded: move to that layout's saved position.
        hooksecurefunc(EditModeManagerFrame, "UpdateLayoutInfo", function()
            if ns.Bar.frame then ns.Bar:ApplyPosition() end
        end)
    end
    ns.Bar:ApplyPosition()
    if EditModeActive() then self:OnEnter() end
end
