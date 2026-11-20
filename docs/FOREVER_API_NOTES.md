# WoW Forever — addon API notes

Facts about the client OmniCast targets. **Confirmed** means checked against Blizzard's exported UI code (`_forever_\BlizzardInterfaceCode`, exported 2026-11-07) or against the in-game log.

## Client

- Product `wowf`, folder `_forever_`, client **1.60.1.70840**, `## Interface: 16001`, `WOW_PROJECT_ID` = 18. Confirmed by probe.
- Runs on the **retail (Midnight 12.x) engine** with Classic content. Blizzard's UI code covers both "Mainline" and "Classic" styles: `classicStyleCastBar`, and `CastingBarMixin:SetLook("CLASSIC")` uses `Interface\CastingBar\UI-CastingBar-Border`.
- **Secret values apply.** In the API docs, look for `SecretWhen*Restricted` on functions and `NeverSecret` on fields. A secret value is only allowed as an argument when the API's `SecretArguments` says so, and `AllowedWhenUntainted` means Blizzard code only. That includes `StatusBar:SetTimerDuration`, so addons can't animate a bar from a secret duration.
- The combat log can't be used. `COMBAT_LOG_EVENT_UNFILTERED` passes `IsEventValid`, but addons are forbidden from registering it.

## Swing timer — confirmed (`Blizzard_SwingTimer`, `SwingTimerDocumentation.lua`)

- `PLAYER_SWING(swingDuration, swingType)` fires on every swing. The duration is the real hasted swing time. The event is synchronous and fires even when Blizzard's own swing frames are hidden; the log shows it arriving.
- `PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)` only fires for swing types with `C_SwingTimer.EnableRangeCheck(type, true)`. Treat a type as out of range only when `checksRange and not isInRange`.
- `C_SwingTimer.IsTargetWithinSwingRange(swingType)` → `true`, `false` or `nil`. Nil means no check could be made and must **not** be read as out of range.
- `Enum.PlayerSwingType`: `MainHand=0`, `OffHand=1`, `Ranged=2`.
- `UnitAttackSpeed("player")` → `mainHand, offHand, ranged`. It's secret when unit stats are restricted.
- Blizzard's frames are `SwingTimerManagerFrame`, `SwingTimerMainHandFrame`, `SwingTimerOffHandFrame` and `SwingTimerRangedFrame`. The CVar is `showSwingTimer`.

## Casting — confirmed

- The player cast bar is `PlayerCastingBarFrame`, plus `OverlayPlayerCastingBarFrame`.
- `UnitCastingInfo` → `name, displayName, texture, startMs, endMs, isTradeskill, castID, notInterruptible, spellID, castBarID, delayTimeMs`. It's `SecretWhenUnitSpellCastRestricted`.
- `UnitChannelInfo` → `name, displayName, texture, startMs, endMs, isTradeskill, notInterruptible, spellID, isEmpowered, numStages, castBarID`.
- `UNIT_SPELLCAST_CHANNEL_STOP(unit, castGUID, spellID, interruptedBy)`: a non-nil `interruptedBy` means the channel was interrupted.
- `UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)`.

## GCD — confirmed

- **Spell 61304 (the retail GCD spell) doesn't exist on Forever.** `GetSpellCooldown(61304)` returns nil even out of combat, so don't use it.
- `C_Spell.GetSpellCooldown(spellID)` is `SecretWhenCooldownsRestricted`, so a spell's own timing is secret in combat.
- The `SPELL_UPDATE_COOLDOWN(spellID, baseSpellID, category, startRecoveryCategory)` payload is **readable in combat**. A `startRecoveryCategory` of 133 means the spell triggers the GCD. The event fires on **key press**, even when the spell is only queued behind a cast, and also for **pet spells** (Imp Firebolt 7799, roughly every 2.5s). Use it to learn which spells trigger the GCD, never to time it.
- Player spell IDs in `UNIT_SPELLCAST_START` and `UNIT_SPELLCAST_SUCCEEDED` are readable in combat.
- How OmniCast does it: the GCD starts at cast start (hard casts) or on success (instants) of a spell learned to trigger it. The learned data is in `db.gcdSpells`, and the GCD length comes from readable spell cooldowns out of combat. Spells that trigger the GCD but have no cooldown of their own provide a duration object for `SetTimerDuration`.
- Forever renames some spells; for example, 980 is "Bane of Agony".
- The `SPELL_UPDATE_COOLDOWN` payload includes `spellID, baseSpellID, category, startRecoveryCategory, itemID`.

## Secrecy checks (`C_Secrets`)

`ShouldSpellCooldownBeSecret(spellID)`, `ShouldUnitSpellCastBeSecret(unit)`, `ShouldUnitStatsBeSecret(unit)`, `ShouldCooldownsBeSecret()`, `HasSecretRestrictions()`. `/oc probe` reports the first three.

## Confirmed in play (v0.1.1 log, warlock level 9)

- `UNIT_SPELLCAST_START` fires in the **same frame** as `UNIT_SPELLCAST_SENT`. Casts are predicted client-side, so latency can't be measured from events; use `GetNetStats`.
- The player's own `UnitCastingInfo` times are readable in combat.
- In combat, `C_Secrets.ShouldSpellCooldownBeSecret(61304)` is true and `ShouldUnitStatsBeSecret("player")` is true. `GetSpellCooldown(61304)` gave neither readable timing nor a usable `isActive`, and `UnitAttackSpeed` returned nothing usable. The duration in `PLAYER_SWING` covers attack speed.

## Confirmed in play (v0.2.x logs, warlock levels 9–10)

- `UnitCastingInfo` `delayTimeMs` matches pushback exactly: +1.0s for the first hit, then +0.8s per hit.
- The target name in `UNIT_SPELLCAST_SENT` was readable in combat in the open world. Untested in instances and PvP.
- Non-GCD casts such as Opening (22810) and Herbalism send `SPELL_UPDATE_COOLDOWN(id, nil, nil, nil)`, which has no recovery category.
- For a non-queued cast, the cooldown event can arrive in the same frame but *after* `UNIT_SPELLCAST_START`.
- Channels fire `UNIT_SPELLCAST_SUCCEEDED` at channel start.

## Spell queue (confirmed in the v0.5.x logs)

- Pressing a spell during a cast or GCD fires `SPELL_UPDATE_COOLDOWN(spellID, …)` for it at the press, including a repeat of the spell being cast (about 0.16s before the end).
- The same event also fires for the current spell at its cast start, and again right after it succeeds. For casts no longer than the queue window (talented 0.4s Corruption), the start event lands inside the window, so filter by time since cast start, not only by the window.
- `UNIT_SPELLCAST_SENT` for a queued spell fires when it actually goes off, not at the press.
- `C_Spell.IsCurrentSpell(id)` is true for both the queued spell and the one currently being cast.
- `CURRENT_SPELL_CAST_CHANGED` fires on queue changes.

## Instances (first Ragefire Chasm run, v0.5.3, warlock level 13)

- No errors, and no "secret cast timing" entries. Pushback (`delayTimeMs`) stayed readable, and the user saw nothing wrong in play.
- Not conclusive: the per-type log caps were used up beforehand. From v0.5.4 the log marks instance and encounter boundaries, records what is secret on the first pull and at each encounter start, and restarts the caps at both.

## Instances (second Ragefire Chasm run, v0.5.4, level 15, all four bosses)

- Secret on the first pull and at every encounter start: `cooldowns=true`, GCD cooldown true, **player casts false**, player stats true. The same as open-world combat; boss encounters added nothing.
- **The target name from `UNIT_SPELLCAST_SENT` is secret in instances** (readable in the open world). `FontString:SetText` still shows it, but self-targets can't be filtered out by comparing names there.
- Readable in instances and encounters:
  - Spell IDs on START/SUCCEEDED, and the `SPELL_UPDATE_COOLDOWN` payload (category 133).
  - `PLAYER_SWING` (wand).
  - Channel pushback.
  - `IsCurrentSpell`; `SetTimerDuration` worked.
- `IsCurrentSpell` is briefly true for a press *outside* the queue window too: an instant mid-channel goes off at once and cuts the channel, key spam is rejected, and a spell's own post-success event lands. Queue detection must apply the window to every press.

## Dual wield and Slam (v0.5.5 logs, warrior levels 21–24)

- Dual wield: `PLAYER_SWING(2, 0)` and `PLAYER_SWING(1.9, 1)` arrive separately for each hand, with each weapon's own speed. The off hand runs independently.
- Slam is a hard cast here (spell 1240193, about 1.5s). No swing lands during the cast. After it completes, the main hand swings one full speed later (+1.93 to 2.01s on a 2.0s weapon). The off hand swings about **half** its speed later (+0.93 to 0.96s on 1.9s), in all three logged Slams.
- Heroic Strike's `UNIT_SPELLCAST_SUCCEEDED` lands in the same frame as the main-hand `PLAYER_SWING`.

## Still open

1. Is the `SPELL_UPDATE_COOLDOWN` payload (`startRecoveryCategory`) readable in combat? It's logged.
2. Does `StatusBar:SetTimerDuration(gcdDurationObject)` work from addon code? It's logged once per session.
3. Is the spell ID on `UNIT_SPELLCAST_SUCCEEDED` secret in combat? It's logged.

## Logs and source

- Saved log: `_forever_\WTF\Account\<account>\SavedVariables\OmniCast_Forever.lua`. It's written on `/reload` or logout.
- Blizzard source: `_forever_\BlizzardInterfaceCode\Interface\AddOns\`. API docs are in `Blizzard_APIDocumentationGenerated\`.

## Auto Shot wind-up — confirmed (hunter L6, v0.6.3 probe)

- Classic's rule holds: moving in the last ~0.5s of the Auto Shot timer interrupts the shot (`UNIT_SPELLCAST_INTERRUPTED` for spell 75, then `FAILED_QUIET` while still moving). The shot fires 0.68-0.83s after you stop: the 0.5s wind-up plus latency.
- Moving earlier in the timer (1.8-2.0s left, stopped with 0.8-1.2s left) doesn't delay the shot.
- There is no `UNIT_SPELLCAST_START` for the wind-up, so it can't be shown as a cast.
- `PLAYER_STARTED_MOVING`/`PLAYER_STOPPED_MOVING` fire normally in combat.
- A run of `UNIT_SPELLCAST_FAILED` for Auto Shot followed by `STOP_AUTOREPEAT_SPELL` is the mob reaching melee range.

## Wand Shoot — confirmed (mage L7-8, v0.7.1-v0.7.3 probes)

- Shoot (5019) **auto-repeats** while you stand still (1.45-1.60s apart at 1.50s speed). Moving turns it off for good: `STOP_AUTOREPEAT_SPELL` follows ~0.1s after `PLAYER_STARTED_MOVING`, and it doesn't resume when you stop. This is "all or nothing", unlike Auto Shot. Presumably every non-hunter ranged attack works this way.
- The first shot fires 0.53-0.65s after the press (`START_AUTOREPEAT_SPELL`).
- Pressing Shoot again while wanding toggles it off (`FAILED`/`FAILED_QUIET` plus `STOP_AUTOREPEAT_SPELL`). A shot already in its last ~0.5s still fires. It is **not** a queue: v0.7.2 misread it as one.
- Spells and wand shots don't queue into each other (user, in play). Casting while wanding doesn't stop the wand; moving does.
- PLAYER_SWING type 2 carries the wand speed (1.50s).

## Press-and-hold casting (Forever option, from retail)

- CVar `ActionButtonUseKeyHeldSpell` (Options > Combat > Press and Hold Casting). While an action key is held, the game recasts that spell at the next opportunity.
- Nothing is queued in the game's sense. The next cast starts ~0.1s after the previous `SUCCEEDED`, and no `queue:` press is seen.
- Key presses on Blizzard action bars all go through the global `TryUseActionButton(button, down)` (called from `ActionButtonDown/Up` and `MultiActionButtonDown/Up`). A post-hook sees key down and key up. Addon bars with `CLICK` bindings bypass it.

## Warrior/rogue Shoot Bow-Gun-Crossbow and Throw — confirmed (warrior L41, v0.8.1 probe)

- One shot per press, instant (`hardcast=false`), with `PLAYER_SWING(speed, 2)`. Throw was 2.10s. The weapon then cools down for its speed, and no auto-repeat events fire.
- A press during the cooldown gives `UNIT_SPELLCAST_FAILED` (at 0.26s and 0.51s left). It is never queued, so there is no queue marker.
- Moving changes nothing, since there is nothing running to interrupt.

## Ranged summary (in play + outside sources, 2026-11-20)

| Attack | Repeats | Wind-up | Moving |
|---|---|---|---|
| Hunter Auto Shot | yes | last ~0.5s of the timer | inside the wind-up: interrupted, then a retry ~0.5-1.0s after you stop; Auto Shot keeps going |
| Wand Shoot | yes, while standing still | ~0.5s (first shot 0.53-0.65s after the press) | turns it off for good |
| Shoot Bow/Gun/Crossbow, Throw | no, one press = one shot | none seen | no effect |

- Blizzard (Kaivax, beta forum, 2026-09-23): the 0.5s cast before Auto Shot and wand shots "is not functioning properly", fix due. By 2026-10-21 players reported the wind-up live, with a retry quirk after moving: 0.67-0.93s after stopping, from combat logs. That matches the hunter log (0.68-0.83s).
- Forever hunter wiki (classic-hunter/forever-hunter "Shot Mechanics"): Auto Shot cycle = ~0.5s cast + (weapon speed − cast). Auto Shot can fire during Aimed/Multi-Shot casts. **A melee swing resets the ranged timer** (Blizzard calls the linked swing timers intended). OmniCast doesn't model that; it is unverified in our logs.
- Wands toggle (Classic patch 1.5.0): Shoot "will continue attacking with the equipped wand until cancelled (e.g. moving)".
