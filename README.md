# OmniCast Forever

One fixed-size bar for everything your character is doing in **WoW Forever**: casts, channels, the global cooldown, and melee/ranged swing timers. It switches between them on its own.

> Status: **v0.x private beta** while it's tested in live play. Not published yet.

## What it shows

| You are… | The bar shows |
|---|---|
| Hard-casting | Cast progress, a red **latency** zone, a **spell-queue** marker. A thin strip underneath shows your swing timer. |
| Channelling | A draining bar with **tick marks** (Arcane Missiles, Drain Life, Mind Flay, Blizzard, …) and a swing strip |
| On the GCD after an instant | GCD progress, labelled with the spell you just used |
| Shooting (Auto Shot, wand, throw) | Ranged swing timer |
| Meleeing, one weapon | Main-hand swing timer, with the GCD as a strip |
| Meleeing, dual wield | The bar **splits** into main hand and off hand, with the GCD as a strip |

Blizzard's own cast bar and swing timer are hidden while OmniCast is enabled. Both can be toggled in settings.

## Commands

```
/oc              settings panel (Esc > Options > AddOns > OmniCast Forever)
/oc unlock|lock  move the bar (also draggable while Edit Mode is open)
/oc test         16s demo: cast → GCD → channel → ranged → dual wield
/oc width 250    /oc height 24
/oc reset        reset position      /oc resetall   reset all settings
/oc probe        client capability report (saved to the log too)
/oc debug        echo the event log to chat
```

## Development

```
src/            addon source (the TOC is the version source of truth)
build.ps1       packages src/ → ./OmniCast_Forever + dist/OmniCast_Forever-v<ver>.zip
tools/          Lua 5.1 syntax/global-leak check (node + luaparse)
docs/           WoW Forever API notes and findings
```

```powershell
./build.ps1                # check + package
./build.ps1 -Bump patch    # bump version, then package
./build.ps1 -Install       # also copy into D:\Battlenet\World of Warcraft\_forever_\Interface\AddOns
```

After packaging, copy the `OmniCast_Forever` folder into `_forever_\Interface\AddOns`. Restart the client the first time; after that, `/reload` is enough.
