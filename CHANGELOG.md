# Changelog

## v0.7.2: Wand queue marker

- **New:** wand and Throw shots show the spell queue marker on the ranged bar. On Forever a wand fires once per press, and pressing Shoot after the marker gets the next shot off the moment the timer ends. The mage log confirms this for wands; Throw is still to be tested.
- The ranged probe stays in for the Throw test.

## v0.7.1 (wand/Throw diagnostics)

- **Diagnostics:** the movement probe is back for wands and Throw. It logs movement while a ranged timer runs, each shot's interval, and any ranged cast events, to find out whether they share Auto Shot's wind-up rule.
- v0.7.0 hunter log: Auto Shot is detected and timed correctly, and no errors appeared.

## v0.7.0: Auto Shot wind-up

- **New: Auto Shot wind-up** (on by default). The last 0.5s of the Auto Shot timer is marked in amber. Moving there interrupts the shot, as in Classic. While moving holds the shot, the bar says "Stop to shoot"; the shot fires about half a second after you stop.
- Confirmed in play with the v0.6.3 probe: moving near the end delayed shots by 0.8-1.35s, while moving earlier in the timer didn't delay them at all.
- Bows, guns and crossbows only (Auto Shot). Wands aren't marked, since they haven't been tested.
- `/oc test` shows the wind-up during the ranged part.
- Setting: Settings > Swing timers > Auto Shot wind-up.
- Removed the v0.6.3 probe.

## v0.6.3 (hunter diagnostics)

- Hunter log check (level 6): Auto Shot arrives as `PLAYER_SWING` type 2 with the hasted speed (2.14s), shots land 2.11-2.21s apart, Raptor Strike arms and clears correctly, and the bar switches between ranged and melee as the target closes in.
- **Diagnostics:** an Auto Shot probe logs each shot's interval against the speed, movement start/stop with the time left on the shot, and any Auto Shot cast events. It answers whether moving near the end of the timer delays the shot, as in Classic, before the "don't move" window gets built.

## v0.6.2 (taint fix)

- **Fixed:** "OmniCast Forever has been blocked from an action" could appear, e.g. while browsing the game options. The Blizzard cast bar and swing timer sit in the same bottom layout as the protected action bars, and OmniCast hid them with `Hide()`, which re-ran that layout from addon code. They are now made invisible (alpha 0) instead, leaving Blizzard's layout alone. In Edit Mode they keep their normal look so they can still be moved.
- Turning "Hide Blizzard swing timer" off now brings it back straight away.
- An invisible Blizzard swing timer still takes its space at the bottom of the screen in combat. To free it, turn off Swing Timer in the game's own options.
- The log records any blocked action (`ADDON_ACTION_BLOCKED`/`FORBIDDEN`) with the function name and combat state.

## v0.6.1 (review fixes)

- **Fixed:** in Edit Mode, "Switch without saving" kept OmniCast's discarded changes, and saving the next layout then saved them too. Blizzard switches layouts without calling `RevertAllChanges`, so the switch itself now restores the pending position and size.
- **Fixed:** a short cast (0.4s Corruption) measured the queue window against the cast's end, not the GCD, which runs longer. Pressing again early could show a queued repeat while 1.3s of GCD remained. Both queue checks now use whichever ends later, the cast or the GCD.
- **Fixed:** replacing a queued repeat (Frostbolt behind Frostbolt, then another spell) kept showing Frostbolt. A confirmed different spell now replaces it.

## v0.6.0: Next-swing abilities

- **New: armed next swing** (on by default). While Heroic Strike, Cleave, Maul or Raptor Strike waits for your next swing:
  - The main-hand bar shows the ability's name and icon.
  - The bar pulses gently in gold.
  - It returns to normal when the swing lands, or when the ability is cancelled or fails (e.g. not enough rage).
  - Detection uses the same "current spell" check that lights the ability's action button.
- These abilities no longer show up as a queued spell.
- `/oc test` arms Heroic Strike during the dual-wield part.
- Setting: Settings > Swing timers > Next-swing abilities.
- Confirmed in play: mid-combat weapon swaps (v0.5.7). The off-hand item is readable in combat, and the split bar follows swaps in both directions.

## v0.5.7

- **Fixed:** swapping from dual wield to a two-hander (or a shield) in combat left the split off-hand lane up until combat ended. Dual wield was detected from the off-hand speed, which is a secret stat in combat. It now comes from the item in the off-hand slot, read on every equipment change. Swapping to dual wield in combat shows the off-hand lane straight away; its timer starts at the first off-hand swing.
- The log records weapon-slot changes, and whether the off hand was readable.

## v0.5.6

- **Fixed:** after a hard cast in melee (warrior Slam), the swing timers showed "ready" until the next swing landed. They now restart when the cast completes, matching the warrior log:
  - The main hand restarts at full weapon speed.
  - When dual wielding, the off hand is set to swing half its speed later.
  - The next real swing still resyncs both.
- Confirmed in play (warrior, dual wield): `PLAYER_SWING` reports each hand separately with its own speed (main hand 2.0s, off hand 1.9s), and both lanes stay in sync.

## v0.5.5

- **Fixed:** a spell pressed outside the spell queue window could show as queued. The game briefly marks it as current anyway, so the icon flickered. This happened for instants pressed mid-channel (they go off at once and cut the channel), for key spam early in a cast, and for a spell's own cooldown event at the start of its GCD (all in the Ragefire Chasm log). Every press now has to fall inside the queue window, not just repeats of the current spell.

## v0.5.4

- **Diagnostics:** the log now records entering and leaving instances, and boss encounter start and end. It also records which values are secret on the first pull in an instance and at each encounter start. The per-type log caps restart on instance entry and encounter start. In the first Ragefire Chasm run, the caps had been used up while questing beforehand, so the run itself was barely logged.

## v0.5.3

- **Fixed:** a short cast (talented 0.4s Corruption) showed itself as a queued repeat and could stay stuck across several casts. A cast's own start fires the same cooldown event as a queue press, and with a cast no longer than the 0.4s queue window that start fell inside the window. Same-spell events in a cast's first 0.1s are now ignored.
- **Fixed:** a queued repeat now clears as soon as a different spell starts or succeeds, instead of lingering until the bar went idle.

## v0.5.2

- **Fixed:** queueing a repeat of the current spell (v0.5.1 relied on `UNIT_SPELLCAST_SENT`, which the log shows fires when the queued spell goes off, not on the press). The repeat is now detected from the press's `SPELL_UPDATE_COOLDOWN` inside the queue window, excluding the same event at the cast's start and right after it succeeds. SENT is no longer used for queue detection.
- **Fixed:** a queued spell re-detected itself as queued once it started, so the icon stayed up for its whole cast or channel (seen in the log for Shadow Bolt and Drain Soul).
- **Fixed:** the **Revert All Changes** button didn't move the bar back. Blizzard binds that button to the original function at load, so the method hook never saw the click. The button's click is now hooked too, and Blizzard's has-changes flag is cleared after a revert.
- `/oc test`: a second Frostbolt queued behind the first (a repeat queue), then Fire Blast queued behind it.

## v0.5.1 (review fixes)

- **Fixed:** a repeat of the current spell (Shadow Bolt queued behind Shadow Bolt) was never shown as queued. A press of the same spell counts as queued when it is a new send (a different cast GUID from `UNIT_SPELLCAST_SENT`) inside the spell queue window, which is the only time the game accepts it. It stays queued through the current cast's success and clears when it starts or is rejected.
- **Fixed:** some allowed size combinations (e.g. height 8 at frame thickness 3x, or a narrow, tall bar with the icon on) produced negative drawing sizes. The frame thickness now gives way first (the fill never goes below 4px), then the icon is dropped if it would leave the bar under 40px wide. Text priority follows the icon actually shown.
- **Fixed:** Edit Mode's Revert All Changes didn't revert OmniCast. Changes made in Edit Mode are now pending, like native frames:
  - They enable Blizzard's Save and Revert buttons, and closing Edit Mode or switching layouts brings up Blizzard's unsaved-changes warning.
  - Revert, or leaving without saving, restores the position and size from when Edit Mode was opened.
  - Saving a preset as a new layout carries the pending position into the new layout.

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
