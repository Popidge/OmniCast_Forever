-- OmniCast Forever: hide the default player cast bar and native swing timer.
--
-- Taint: PlayerCastingBarFrame and the SwingTimer*Frames are bottom-managed
-- frames. Calling Hide() on them from addon code runs their OnHide in our
-- (tainted) context, which re-lays out the bottom container that also holds
-- the protected action bars -> "blocked from an action" errors. So we never
-- Show/Hide them: they are made invisible with alpha 0 instead, which leaves
-- Blizzard's layout and show/hide logic untouched. In Edit Mode they keep
-- their normal alpha so they can still be seen and moved.
local _, ns = ...

local Blizzard = ns:NewModule("Blizzard")
Blizzard.castbars = {}
Blizzard.swingFrames = {}

local CASTBAR_NAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "OverlayPlayerCastingBarFrame" }

local function EditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive
        and EditModeManagerFrame:IsEditModeActive() == true
end

local hooked = {}  -- frame -> setting key
local applying = false

local function WantHidden(frame)
    return ns.db[hooked[frame]] and not EditModeActive()
end

local function ApplyAlpha(frame)
    if applying then return end
    local want = WantHidden(frame) and 0 or 1
    if frame:GetAlpha() ~= want then
        applying = true
        frame:SetAlpha(want)
        applying = false
    end
end

local function Suppress(frame, settingKey)
    if not hooked[frame] then
        hooked[frame] = settingKey
        -- Blizzard resets the alpha itself (e.g. after a vehicle/override bar);
        -- put ours back afterwards.
        hooksecurefunc(frame, "SetAlpha", function(self, a)
            if not applying and a ~= 0 and WantHidden(self) then ApplyAlpha(self) end
        end)
        frame:HookScript("OnShow", ApplyAlpha)
    end
    ApplyAlpha(frame)
end

function Blizzard:RefreshAlpha()
    for frame in pairs(hooked) do ApplyAlpha(frame) end
end

function Blizzard:HideCastbars()
    for _, name in ipairs(CASTBAR_NAMES) do
        local f = _G[name]
        if type(f) == "table" and f.SetAlpha then
            if not self.castbars[name] then
                self.castbars[name] = f
                ns:Log("found Blizzard castbar: %s", name)
            end
            if ns.db.hideBlizzardCastbar and not self.unregistered then
                pcall(f.UnregisterAllEvents, f) -- stops it reacting to casts at all
            end
            Suppress(f, "hideBlizzardCastbar")
        end
    end
    if ns.db.hideBlizzardCastbar then self.unregistered = true end
end

-- The Forever swing timer lives in Blizzard UI code we can't read directly,
-- so find its frames by name once they exist.
function Blizzard:FindSwingFrames()
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and not self.swingFrames[k] and k:find("SwingTimer")
            and not k:find("Option") and not k:find("Setting") and not k:find("EditMode") and not k:find("Check") then
            local ok, isFrame = pcall(function() return v:IsObjectType("Frame") end)
            if ok and isFrame then
                self.swingFrames[k] = v
                ns:Log("found Blizzard swing frame: %s", k)
            end
        end
    end
end

function Blizzard:HideSwing()
    self:FindSwingFrames()
    for _, f in pairs(self.swingFrames) do
        Suppress(f, "hideBlizzardSwing")
    end
end

function Blizzard:ApplySettings()
    if not self.enabled then return end
    self:HideCastbars()
    self:HideSwing()
    -- Turning hiding back off needs the frames to re-register their events.
    if (not ns.db.hideBlizzardCastbar and self.castbarWasHidden) then
        ns:Print("Blizzard cast bar will return after /reload")
    end
    self.castbarWasHidden = ns.db.hideBlizzardCastbar
end

function Blizzard:Enable()
    self.enabled = true
    self.castbarWasHidden = ns.db.hideBlizzardCastbar
    self:HideCastbars()
    self:HideSwing()
    ns:On("ADDON_LOADED", function(_, name)
        if type(name) == "string" and name:find("^Blizzard_") then
            Blizzard:HideCastbars()
            Blizzard:HideSwing()
        end
    end)
    ns:On("PLAYER_ENTERING_WORLD", function()
        Blizzard:HideCastbars()
        Blizzard:HideSwing()
    end)
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() Blizzard:RefreshAlpha() end, Blizzard)
        EventRegistry:RegisterCallback("EditMode.Exit", function() Blizzard:RefreshAlpha() end, Blizzard)
    end
end
