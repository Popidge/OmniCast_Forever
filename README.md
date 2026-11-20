# OmniCast Forever

**One bar for everything your character is doing** in WoW Forever: casts, channels, the global cooldown, melee swings and ranged shots. The bar switches between them on its own, so one glance tells you what you're doing and when you can act next.

> **Beta.** OmniCast is new and WoW Forever is still changing, so expect the occasional rough edge, especially after a Forever patch. It has been played through on a warlock, mage, warrior and hunter so far; rogue, druid, paladin, priest and shaman are less tested. Bug reports are very welcome. See [Reporting bugs](#reporting-bugs).

## What it shows

| You are… | The bar shows |
|---|---|
| Hard-casting | Cast progress, a red **latency** zone, the **spell-queue** point, and the **queued spell** icon once you press your next one. Pushback flashes the bar and shows the delay. Your swing timer runs as a thin strip underneath. |
| Holding a spell key (Forever's *Press and Hold Casting*) | The held spell in the queued slot, since it goes off next |
| Channelling | A draining bar with **tick marks** (Arcane Missiles, Drain Life, Mind Flay, Blizzard, …) |
| On the GCD after an instant | GCD progress, labelled with the spell you used |
| Meleeing | Your main-hand swing, with the GCD as a strip underneath |
| Dual wielding | The bar **splits** into main hand and off hand, and follows weapon swaps mid-combat |
| Heroic Strike, Cleave, Maul or Raptor Strike waiting for your swing | The main-hand bar glows and shows the ability |
| Shooting with Auto Shot | The shot timer, with the last 0.5s **wind-up** marked. Moving there holds the shot, and the bar says *Stop to shoot*. |
| Wanding | The first shot's wind-up, then each shot while you stand still. The bar disappears as soon as moving stops the wand. |
| Throwing, or shooting a bow/gun as a non-hunter | The weapon's cooldown after each shot |

It's always **one fixed-size bar**. It never spawns extra bars, and it scales cleanly to any size using Forever's own cast bar art. Blizzard's cast bar and swing timer are hidden while OmniCast is enabled (both can be turned back on in settings).

## Setup

- **Install** from CurseForge, or copy the `OmniCast_Forever` folder into `_forever_\Interface\AddOns`.
- **Move and resize** it in Edit Mode, like any Blizzard frame. It snaps to other frames and saves per Edit Mode layout. You can also use `/oc unlock`.
- **Settings:** Esc > Options > AddOns > OmniCast Forever, or `/oc`.
- **Try it out of combat:** `/oc test` plays a short demo of every mode.

## Commands

```
/oc              settings
/oc unlock|lock  move the bar without Edit Mode
/oc test         demo: cast → GCD → channel → ranged → dual wield
/oc width 250    /oc height 24
/oc reset        reset position      /oc resetall   reset all settings
/oc log          record events for a bug report (off by default)
/oc debug        also echo them to chat
/oc clearlog     clear the saved log
```

## Reporting bugs

Please include what you were doing, your class and level, and if you can, a log:

1. Type `/oc log` to start recording.
2. Play until the problem happens, then `/reload` (the log is written on reload or logout).
3. Send the file `_forever_\WTF\Account\<your account>\SavedVariables\OmniCast_Forever.lua`.
4. `/oc log` again turns recording off. The log is cleared at your next login.

The log only contains OmniCast's own events (spell names, timings, the target name of your casts). It holds no chat, account or character details beyond your class and level.

## Known limitations

- **Press-and-hold** detection works with Blizzard's action bars. Bars from other addons (Bartender, Dominos, ElvUI) bypass the key handler OmniCast watches.
- **Hunters:** Forever resets the ranged timer when you melee. OmniCast doesn't model that yet, so the ranged bar can be slightly off for the first shot after melee.
- **Text is English only.** Spells are detected by ID, so other client languages work, but OmniCast's own labels ("Stop to shoot", "Out of range") stay English.
- The combat log is blocked on Forever, so nothing that depends on it (such as who interrupted you) can be shown.

## Development

```
src/            addon source (the TOC is the version source of truth)
build.ps1       checks and packages src/ into ./OmniCast_Forever and dist/OmniCast_Forever-v<ver>.zip
tools/          Lua 5.1 syntax and global-leak check (node + luaparse)
docs/           WoW Forever API findings and the roadmap
```

```powershell
npm install                # once, for the Lua check
./build.ps1                # check + package
./build.ps1 -Bump patch    # bump the version, then package
./build.ps1 -Install       # also copy into your AddOns folder ($env:WOW_FOREVER_ADDONS)
```

`docs/FOREVER_API_NOTES.md` records what Forever's client exposes, measured in live play. It's the place to look before touching cast or swing logic.

## Licence

[MIT](LICENSE)
