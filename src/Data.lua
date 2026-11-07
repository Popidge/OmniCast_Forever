-- OmniCast Forever: static spell data.
-- Spells are matched by *name* (resolved from the client, so it works in any
-- locale and for every rank). English names are a fallback while spell data loads.
local _, ns = ...
local C = ns.Compat

local Data = ns:NewModule("Data")

-- Channelled spells: seconds between ticks. Tick count = duration / interval.
local CHANNEL_INTERVAL = {
    [5143]  = { 1, "Arcane Missiles" },
    [689]   = { 1, "Drain Life" },
    [1120]  = { 3, "Drain Soul" },
    [5138]  = { 1, "Drain Mana" },
    [755]   = { 1, "Health Funnel" },
    [1949]  = { 1, "Hellfire" },
    [5740]  = { 2, "Rain of Fire" },
    [15407] = { 1, "Mind Flay" },
    [10]    = { 1, "Blizzard" },
    [12051] = { 2, "Evocation" },
    [740]   = { 2, "Tranquility" },
    [16914] = { 1, "Hurricane" },
    [1510]  = { 1, "Volley" },
    [746]   = { 1, "First Aid" },   -- bandages
}

-- Abilities that replace the next melee swing; their cast "succeeds" when the swing lands.
local ON_NEXT_SWING = {
    [78]   = "Heroic Strike",
    [845]  = "Cleave",
    [6807] = "Maul",
    [2973] = "Raptor Strike",
}

-- Ranged auto-attacks and shots that restart the ranged timer when they fire.
Data.RANGED_SPELLS = {
    [75]   = true, -- Auto Shot
    [5019] = true, -- Shoot (wand)
    [2480] = true, -- Shoot Bow
    [7918] = true, -- Shoot Gun
    [7919] = true, -- Shoot Crossbow
    [3018] = true, -- Shoot
    [2764] = true, -- Throw
}

Data.channelByName = {}
Data.nextSwingByName = {}
Data.rangedByName = {}

local function Build()
    local missing = 0
    for id, v in pairs(CHANNEL_INTERVAL) do
        Data.channelByName[v[2]] = v[1]
        local n = C.GetSpellName(id)
        if n then Data.channelByName[n] = v[1] else missing = missing + 1 end
    end
    for id, en in pairs(ON_NEXT_SWING) do
        Data.nextSwingByName[en] = true
        local n = C.GetSpellName(id)
        if n then Data.nextSwingByName[n] = true else missing = missing + 1 end
    end
    for id in pairs(Data.RANGED_SPELLS) do
        local n = C.GetSpellName(id)
        if n then Data.rangedByName[n] = true end
    end
    return missing
end

function Data:Init()
    Build()
end

function Data:Enable()
    if Build() > 0 then
        ns:On("SPELLS_CHANGED", function() Build() end)
    end
end

function Data:ChannelInterval(name)
    return name and Data.channelByName[name]
end

function Data:IsNextSwing(spellID, name)
    if spellID and ON_NEXT_SWING[spellID] then return true end
    return name ~= nil and Data.nextSwingByName[name] == true
end

function Data:IsRanged(spellID, name)
    if spellID and Data.RANGED_SPELLS[spellID] then return true end
    return name ~= nil and Data.rangedByName[name] == true
end
