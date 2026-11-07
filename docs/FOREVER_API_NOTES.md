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

## Still open

1. Is the `SPELL_UPDATE_COOLDOWN` payload (`startRecoveryCategory`) readable in combat? It's logged.
2. Does `StatusBar:SetTimerDuration(gcdDurationObject)` work from addon code? It's logged once per session.
3. Is the spell ID on `UNIT_SPELLCAST_SUCCEEDED` secret in combat? It's logged.

## Logs and source

- Saved log: `_forever_\WTF\Account\POPIDGE\SavedVariables\OmniCast_Forever.lua`. It's written on `/reload` or logout.
- Blizzard source: `_forever_\BlizzardInterfaceCode\Interface\AddOns\`. API docs are in `Blizzard_APIDocumentationGenerated\`.
