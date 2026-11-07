# OmniCast Forever: roadmap

## Identity (hard rules)

- **One bar.** OmniCast tracks whatever your character is doing, in a single fixed-size bar. **No second bar, ever.** Features that need another bar (target/focus/enemy castbars, mirror bars, multiple bars) belong in other addons.
- **Only what you're doing right now.** The bar shows the character's current action: cast, channel, GCD, swing. Passive or ambient state, such as mana regen ticks or the five-second rule, belongs elsewhere (e.g. the player frame), not here.
- **Scales cleanly.** Users size the bar to suit their UI, often large and prominent. All art keeps its proportions at any width and height: the bar grows but the frame and spark stay at native thickness (nine-sliced art), like native UI frames. The user tested a proportional zoom and rejected it: at a large size it made the frame and spark chunky.
- **Fits the base UI.** OmniCast should look native to Forever. Forever's Classic and Modern Edit Mode presets differ only in layout, and both use the same modern cast bar art. So the default is **Modern**, built from Forever's own art. A true vanilla-art Classic style may come later.

## Next

1. **Look and feel.** ~~Modern style from Forever's own art~~ (v0.3.0). ~~Edit Mode integration~~ (v0.4.0). Still to do: a colour picker for the flat styles (low priority). A Classic (vanilla art) style is deferred: Forever's Classic/Modern presets only differ in layout, and both use the modern cast bar art.
2. **Queued spell display.** When the next spell is pressed during the spell-queue window, show it (icon and name) at the end of the bar. Forever reports the press through `SPELL_UPDATE_COOLDOWN` and `UNIT_SPELLCAST_SENT`.

## Later

- **Channel clipping help.** Highlight the next tick, and mark where recasting would clip a tick.
- **Crafting counter.** "Elixir of Minor Defense 3/10" when crafting multiples.
- **Theme presets.** Popular third-party UI looks, such as flat ElvUI-style.
- **Import/export share codes** for settings. LibDeflate is available, and Edit Mode share strings set the precedent.

## When testable

- **Hunter Auto Shot window.** Mark the last 0.5s "don't move" part of the shot. Needs a hunter to test.
- **Dual wield**, and **instance restrictions** (Ragefire Chasm at around level 15).

## Rejected

- Second bars of any kind: target, focus, enemy, mirror (breath/fatigue), or multiple bars.
- Mana regen and five-second-rule tick (not an action you're doing right now).
- Combat-log features (interrupted-by names, parry haste): the combat log is blocked on Forever.
