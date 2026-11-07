# Changelog

## v0.5.0: Queued spell

- **New: queued spell display** (on by default). When you press your next spell during a cast, channel or the GCD (inside the spell queue window), its icon appears at the right end of the bar until it goes off. The timer moves left of it.
  - Detection: the key press (`UNIT_SPELLCAST_SENT` / `SPELL_UPDATE_COOLDOWN`) names the candidate, `C_Spell.IsCurrentSpell` confirms it is queued (the same check action buttons use), and `CURRENT_SPELL_CAST_CHANGED` clears it when cancelled. It also clears when the spell starts or succeeds. Pet spells, Auto Attack, wand and Auto Shot are ignored.
- The spell queue window now comes from the client (`C_Spell.GetSpellQueueWindow`), falling back to the CVar.
- `/oc test` shows Fire Blast queued during the Frostbolt cast, followed by its GCD.
- Setting: Settings > Casting > Queued spell.

## v0.4.1

- **Selection:** selecting the bar now deselects any selected Blizzard frame, so only one thing is selected and arrow keys reach the bar. This uses `ClearSelectedSystem`, which Blizzard runs through a secure delegate out of combat, so it is taint-safe.
- **Snap preview lines:** red guide lines show which edge or centre the bar is snapping to while dragging, like Blizzard's frames.
- **Edit Mode dialog:** text no longer overflows. It uses the same layout as Blizzard's settings dialog (100px label, 200px slider with value, 343px rows), with full-width stacked buttons.

## v0.4.0: Edit Mode

- **The bar behaves like a native Edit Mode frame:**
  - Blizzard's selection highlight: blue normally, yellow when selected.
  - Click to select. Selecting a Blizzard frame, or clicking empty space, deselects it.
  - **Live snapping** while dragging, following Blizzard's rules (8px range, the Snap toggle). It snaps beside, above or below other Edit Mode frames, aligns edges and centres with nearby frames, and snaps to screen edges and centre, and to grid lines when the grid is shown.
  - **Arrow keys** nudge the selected bar 1px (Shift: 10px).
  - **Settings dialog** in Edit Mode style: Width, Height, Frame Thickness, Reset Position, and More Settings.
  - **Position saved per Edit Mode layout:** switching layouts moves the bar, like native frames do.
- Taint-safe: Edit Mode state is read and Blizzard functions are only post-hooked. Nothing is written into Blizzard's Edit Mode tables.
- `/oc unlock` outside Edit Mode still gives the simple drag handle.

## v0.3.2

- **Modern style: the frame no longer zooms with the bar.** As with native UI frames, the bar grows but the frame and spark keep Blizzard's native thickness: a 2px frame and an 8px-wide pip that pokes about 4.5px past the fill. The background and frame art are nine-sliced (corners and edges at native size, only the middle stretches). This replaces v0.3.1's proportional zoom, which made the frame and spark chunky on large bars.
- **New setting: Frame thickness** (0.5x to 3x, default 1x = Blizzard native) under Appearance.

## v0.3.1

- **Modern style scales cleanly at any size.** The frame thickness, fill inset, icon gap and spark keep Blizzard's proportions (an 11px fill inside a 15px frame) at any bar height. The frame and background art are three-sliced: the rounded end caps keep their shape and scale with the height, and only the middle stretches with the width.
- The log records atlas sizes and slice data, to check the art against the screen.

## v0.3.0: Forever look

- **New default style: Modern.** It is built from Forever's own UI art, taken from the exported Blizzard code:
  - Casts and channels use the native cast bar fills, including the "full" art on success and the red interrupted fill.
  - Swings use Forever's own swing timer fills for main hand, off hand and ranged.
  - The GCD uses the grey cast bar fill.
  - The cast bar background and frame wrap the bar, with Blizzard's pip as the spark and the icon floating to the left like the default bar.
- If any atlas is missing, the bar falls back to the Simple style automatically, and the log records which atlas was missing.
- The old default is still available as **Simple**, with Minimal alongside it. Colour and texture settings apply to those two.
- Swing labels now use Forever's localised strings (`SWING_TIMER_MAIN_HAND`/`OFF_HAND`/`RANGED`).
- Existing installs are moved to Modern once.

## v0.2.3

- **Text priority:** when the spell name and target don't both fit, one keeps its full width. **Auto** (the default) puts the spell name first when the icon is hidden and the target first when it is shown. It can be forced to Spell name first or Target first in Settings > Appearance. In name-first mode the target fills the remaining space and hides when there's no room.

## v0.2.2

- A hard cast of a spell not yet learned (e.g. Opening, Herbalism) no longer assumes it triggers the GCD. It waits for the cooldown event, which arrives in the same frame.
- Confirmed in play: pushback matches the game's `delayTimeMs` exactly, and spell target names are readable in combat in the open world.

## v0.2.1 (code review fixes)

- **Cast identity:** stop, interrupt, fail and success events are now matched to the current cast by GUID, like Blizzard's cast bar does. A late stop can no longer end a newer cast, and another spell's success is no longer mistaken for the current cast finishing. State-based checks remain as a fallback when GUIDs are not readable.
- **GCD length per spell and class:** learned exactly per spell out of combat, with a fallback to your class's learned value (rogues default to 1.0s). It is no longer one value shared by every character.
- **Target cache bounded:** entries expire after 3s and are pruned on every send. Nothing is stored while target display is off.
- **Less work per frame:** text, colours, icons and markers (latency, queue, ticks) are redrawn only when they change. Weapon icons are cached. The update loop sleeps when idle and wakes on events.
- **Idle opacity:** with opacity above 0, the bar is cleared once idle instead of showing the last spell indefinitely.

## v0.2.0

- **New: pushback display** (on by default). When damage delays your cast, the bar flashes and shows the total delay next to the time, e.g. `+0.4 1.2`. Channels show the time lost when they are cut short. Uses the new never-secret `delayTimeMs` from `UnitCastingInfo`.
- **New: spell target** (off by default). Shows who you are casting at on the right of the bar. Self-targets are hidden. Works in combat even when the name is a secret value.
- Channel ticks now sit on the real tick times, so they stay correct after pushback.
- Both options are in Settings > Casting, and both appear in `/oc test`.

## v0.1.4

- **Fixed:** cast bars didn't appear at all in v0.1.3. A cleanup removed `C.SpellQueueWindow`, so every cast start and GCD bar errored.
- Build check now fails when code calls a module function that doesn't exist.

## v0.1.3

- **Fixed:** the GCD for real this time. Forever has no GCD spell (61304), so that lookup always returned nothing. The GCD now starts when one of your spells actually fires: cast start for hard casts, success for instants. Which spells trigger the GCD is learned from the cooldown event and saved between sessions.
- **Fixed:** your pet's spells (e.g. Imp Firebolt) no longer create fake GCD bars.
- **Fixed:** an instant queued during a cast no longer starts its GCD early. The cooldown event fires on key press, not when the spell goes off.
- GCD length is learned from your spells' cooldowns out of combat and saved.

## v0.1.2

- **Fixed:** the in-combat GCD. The log showed that both the GCD timing and `isActive` are unusable in combat. The GCD now triggers from `SPELL_UPDATE_COOLDOWN`'s `startRecoveryCategory` (133 = GCD), falling back to "an instant spell just succeeded". The fill animates from the GCD duration object (`StatusBar:SetTimerDuration`) so it stays exact even when the numbers are secret.
- **Changed:** latency now comes from network stats (the higher of home and world). The log showed Forever starts casts client-side in the same frame the spell is sent, so measuring send-to-start gave nothing.
- Heroic Strike-style abilities no longer create a fake GCD.
- Diagnostics: raw GCD readout in `/oc probe`. Cooldown and succeeded-spell payloads, plus whether `SetTimerDuration` works, are now logged.

## v0.1.1

- **Fixed:** an instant cast right after a hard cast didn't show its GCD. In combat the GCD timing is a secret value. The bar now uses the never-secret `isActive` flag with a GCD length learned out of combat. A GCD that starts as a cast finishes also cuts the success flash short.
- **Fixed:** latency was inflated when chain-casting. Spells queued during a cast or GCD are no longer measured; idle casts give a smoothed round-trip value, with world latency as a fallback.
- **Fixed:** `PLAYER_SWING` decoding. The payload is `(duration, swingType)`, and the duration is now used directly. Main/off/ranged hands were previously guessed.
- **Fixed:** the swing bar showed "Out of range" with no target. Range updates now respect `checksRange`.
- **Fixed:** `/oc probe` crashed halfway on characters without a ranged weapon.
- GCD bar now shows the spell-queue marker.
- Interrupted channels now flash red.
- Ranged speed now read from `UnitAttackSpeed` (third return).

## v0.1.0 — first beta

- One fixed-size bar that shows the highest-priority activity: cast/channel > swing timers > GCD.
- Secondary strip shows the swing timer under a cast, or the GCD under swings.
- Dual wield splits the bar into stacked main-hand and off-hand lanes.
- Swing timers use Forever's native `PLAYER_SWING` event, with Auto Shot/wand/throw casts, on-next-swing abilities and weapon-speed prediction as fallbacks. The combat log isn't available to addons on Forever.
- Cast bar extras: latency zone, spell-queue-window marker, channel ticks, success and interrupted flashes.
- Hides Blizzard's player cast bar and native swing timer.
- Settings panel, `/oc` commands, unlock/drag (also in Edit Mode), and the `/oc test` demo sequence.
- `/oc probe` diagnostics plus a persistent event log, for live beta testing.
