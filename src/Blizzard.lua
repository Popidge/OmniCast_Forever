-- OmniCast Forever: hide the default player cast bar and native swing timer.
local _, ns = ...

local Blizzard = ns:NewModule("Blizzard")
Blizzard.castbars = {}
Blizzard.swingFrames = {}

local CASTBAR_NAMES = { "PlayerCastingBarFrame", "CastingBarFrame", "OverlayPlayerCastingBarFrame" }

local hooked = {}
local function Suppress(frame, settingKey)
    if not frame or hooked[frame] then
        if frame and ns.db[settingKey] then frame:Hide() end
        return
    end
    hooked[frame] = settingKey
    frame:HookScript("OnShow", function(self)
        if ns.db[hooked[self]] then self:Hide() end
    end)
    if ns.db[settingKey] then frame:Hide() end
end

function Blizzard:HideCastbars()
    for _, name in ipairs(CASTBAR_NAMES) do
        local f = _G[name]
        if type(f) == "table" and f.Hide then
            if not self.castbars[name] then
                self.castbars[name] = f
                ns:Log("found Blizzard castbar: %s", name)
            end
            if ns.db.hideBlizzardCastbar then
                pcall(f.UnregisterAllEvents, f) -- stops it reacting to casts at all
            end
            Suppress(f, "hideBlizzardCastbar")
        end
    end
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
end
