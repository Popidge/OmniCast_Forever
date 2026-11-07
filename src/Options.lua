-- OmniCast Forever: settings panel (Esc > Options > AddOns > OmniCast Forever).
-- Built on the retail Settings API; if any part of it is missing on this client
-- the panel is skipped and everything stays reachable through /oc.
local ADDON, ns = ...
local C = ns.Compat

local Options = ns:NewModule("Options")

local function VarType(v)
    if Settings.VarType then
        if type(v) == "boolean" then return Settings.VarType.Boolean end
        if type(v) == "number" then return Settings.VarType.Number end
        return Settings.VarType.String
    end
    return type(v)
end

local function Build()
    local category, layout = Settings.RegisterVerticalLayoutCategory(ns.title)
    local db, defaults = ns.db, ns.defaults

    local function Register(key, label)
        local setting = Settings.RegisterAddOnSetting(category, "OmniCastForever_" .. key, key, db,
            VarType(defaults[key]), label, defaults[key])
        setting:SetValueChangedCallback(function() ns:ApplySettings() end)
        return setting
    end

    local function Header(text)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
        end
    end

    local function Check(key, label, tip)
        Settings.CreateCheckbox(category, Register(key, label), tip)
    end

    local function Slider(key, label, min, max, step, tip, fmt)
        local opts = Settings.CreateSliderOptions(min, max, step)
        if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
            opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt)
        end
        Settings.CreateSlider(category, Register(key, label), opts, tip)
    end

    local function Dropdown(key, label, values, tip)
        local function GetOptions()
            local c = Settings.CreateControlTextContainer()
            for _, v in ipairs(values()) do c:Add(v[1], v[2]) end
            return c:GetData()
        end
        Settings.CreateDropdown(category, Register(key, label), GetOptions, tip)
    end

    local function Button(label, text, fn, tip)
        if layout and CreateSettingsButtonInitializer then
            layout:AddInitializer(CreateSettingsButtonInitializer(label, text, fn, tip, true))
        end
    end

    Header("Position & size")
    Button("Move the bar", "Unlock / Lock", function()
        ns.db.locked = not ns.db.locked
        ns:ApplySettings()
    end, "Show a drag handle on the bar. It is also draggable while Edit Mode is open.")
    Button("Preview", "Play demo", function() ns.TestMode:Start() end,
        "Plays a 16 second demo: cast, GCD, channel, ranged shot, dual-wield swings.")
    Slider("width", "Width", 80, 600, 1, "Bar width in UI units.", function(v) return string.format("%d", v) end)
    Slider("height", "Height", 8, 60, 1, "Bar height in UI units. Dual wield splits this between both hands.",
        function(v) return string.format("%d", v) end)
    Button("Position", "Reset position", function() ns:ResetPosition() end)

    Header("Appearance")
    Dropdown("style", "Border style", function()
        return {
            { "modern", "Modern (Forever cast bar art)" },
            { "simple", "Simple (tooltip border)" },
            { "minimal", "Minimal (1px)" },
        }
    end, "Modern uses Forever's own cast bar and swing timer art. Colour and texture settings apply to Simple and Minimal.")
    Slider("frameScale", "Frame thickness", 0.5, 3, 0.25,
        "Modern style: thickness of the frame and spark. 1 = the same as Blizzard's own cast bar, at any bar size.",
        function(v) return string.format("%.2fx", v) end)
    Dropdown("texture", "Bar texture", function()
        local list = {}
        for name in pairs(ns.Bar.TEXTURES) do list[#list + 1] = { name, name } end
        local lsm = C.LSM()
        if lsm then
            for _, name in ipairs(lsm:List("statusbar")) do
                if not ns.Bar.TEXTURES[name] then list[#list + 1] = { name, name } end
            end
        end
        table.sort(list, function(a, b) return a[2] < b[2] end)
        return list
    end, "Includes textures shared by other addons through LibSharedMedia.")
    Slider("fontSize", "Font size", 7, 20, 1, nil, function(v) return string.format("%d", v) end)
    Check("showIcon", "Show icon")
    Check("showSpellName", "Show spell / hand name")
    Dropdown("textPriority", "Text priority", function()
        return {
            { "auto", "Auto (spell name first when icon is hidden)" },
            { "name", "Spell name first" },
            { "target", "Target first" },
        }
    end, "When the spell name and target don't both fit, which one keeps its full width.")
    Check("showTime", "Show time remaining")
    Check("showSpark", "Show spark")
    Slider("idleAlpha", "Opacity when idle", 0, 1, 0.05,
        "0 hides the bar completely when you are not casting or attacking.",
        function(v) return string.format("%d%%", v * 100) end)

    Header("Casting")
    Check("showLatency", "Latency zone", "Red section at the end of a cast: your network delay.")
    Check("showQueueWindow", "Spell queue marker",
        "Line showing when you can press your next spell (SpellQueueWindow).")
    Check("showTicks", "Channel ticks")
    Check("showQueued", "Queued spell",
        "When you press your next spell during a cast or the GCD, show its icon at the end of the bar until it goes off.")
    Check("showPushback", "Pushback",
        "When damage delays your cast (or cuts a channel short): flash the bar and show the total delay next to the time.")
    Check("showTarget", "Spell target", "Show who you're casting at, on the right of the bar.")
    Check("showGCD", "Global cooldown")

    Header("Swing timers")
    Check("showMelee", "Melee swings")
    Check("showRanged", "Ranged / wand shots")
    Dropdown("dualLayout", "Dual wield", function()
        return { { "split", "Split bar (main + off hand)" }, { "main", "Main hand only" } }
    end)
    Check("showStrip", "Secondary strip",
        "Thin strip showing your swing under a cast, or the GCD under your swings.")
    Slider("stripHeight", "Strip height", 2, 12, 1, nil, function(v) return string.format("%d", v) end)
    Check("predictSwings", "Predict swings",
        "Keep the melee timer running from weapon speed when the game sends no swing event.")

    Header("Blizzard UI")
    Check("hideBlizzardCastbar", "Hide Blizzard cast bar", "Turning this off takes effect after /reload.")
    Check("hideBlizzardSwing", "Hide Blizzard swing timer")

    Settings.RegisterAddOnCategory(category)
    Options.category = category
end

function Options:Enable()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
        ns:Log("Settings API missing; options panel disabled")
        return
    end
    local ok, err = pcall(Build)
    if not ok then
        ns:Log("options panel failed: %s", tostring(err))
    end
end

function Options:Open()
    if self.category and Settings.OpenToCategory then
        Settings.OpenToCategory(self.category:GetID())
    else
        SlashCmdList.OMNICASTFOREVER("help")
    end
end
