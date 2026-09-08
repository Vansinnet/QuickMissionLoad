# Quick Mission Load

A standalone Darktide Mod Framework mod that requests packages for a selected or assigned mission while you are waiting to enter it. It holds its own package references, without bypassing the game's loaders or changing matchmaking.

## Behavior

- A selected-mission party vote can start warmup before the transition.
- Quickplay waits for a concrete mission in a confirmed `StateLoading` transition. It does not guess a map.
- The fixed manifest includes mission and intro/view levels, their item dependencies, mission themes, game-mode packages, HUD/view packages, the loading background, and selected circumstance/Havoc mutator assets.
- A missing theme resolves to `default`. The game's theme helper still controls disabled themes and fallback for an unavailable theme configuration.
- Expedition can add the existing generated current section and the immediately previous section's delayed-despawn levels. It only copies names and eligibility flags; it never generates a layout, changes the layout, or looks ahead to future sections.
- Scheduling attempts at most two new package references per update and keeps at most four incomplete requests. Requests are non-prioritized and non-resident. Global package concurrency is unchanged, and the scheduler does not wait on a global busy flag that includes its own work.
- Changed mission metadata preserves intersecting loaded and in-flight references. Existing references remain held until the replacement levels expose their dependency set, then obsolete references are released. During this interval, references from a superseded target can temporarily remain held.
- `event_loading_resources_started` stops new submissions. Existing IDs remain held until `event_loading_finished`, unless the operation is cancelled, redirected to a non-mission destination, disabled, unloaded, or otherwise aborted.
- Vote rejection/loss, matchmaking cancellation, title/menu/error entry, and `StateGame` exit clean up owned references. Full DMF reload releases old IDs; enabling/reloading during `StateLoading` conservatively waits for a later loading finish instead of guessing whether the stop event already fired.

**Preload missions** (`preload_missions`) and **Skip briefing** (`skip_mission_briefing`) are independent and on by default. Preloading requests mission packages before normal loading. Skipping briefing suppresses mission-intro VO and its minimum timer for fastest local entry once normal loading is ready; it does not bypass the intro view or lobby gate. Turn either feature off without disabling the other; disabling preloading releases its held package references. The standard DMF enable/disable toggle controls the whole mod. Both states are cached; there are no memory tiers.

VO changes apply to the next intro: enabling during a playing briefing lets it finish naturally, then bypasses any remaining minimum timer. Disabling does not restart a briefing already skipped. No audio stop API or retained view references are used.

## Limits And Compatibility

Avoid using Quick Mission Load alongside another mod that preloads the same mission packages or skips the same briefing wait. Overlapping package retention can increase memory use, and duplicate briefing hooks are not supported or tested.

This mod does not retain the hub or Psykhanium, preload squad loadouts, request every breed, pre-stream runtime textures, add a preloader registry, or shorten server-side/network waits. Briefing suppression is limited to `MissionIntroView` and the local briefing-wait state: no global dialogue/subtitle filters, host/server or Mortis hooks, presentation changes, or forced resource/network readiness. Package references do not guarantee physical RAM/VRAM residency or full-resolution streamed textures.

Warmup is best effort. A short assignment-to-loading interval can leave little or no opportunity to submit work. Unavailable packages are skipped. Item dependencies wait for their level package and cached master items. Selected mutator assets are not a prediction of every enemy or resource the server will use. Expedition's generated layout may become available too late to help; no pre-handoff availability is promised.

The resource-started event means the game has requested mission loading, **not** that every dependency already has a game-owned reference. Quick Mission Load therefore does not release references at that event and makes no ownership-transfer claim.

No load-time improvement or memory cost has been measured. Maintainer in-game testing has been completed, but exact test contexts and timings were not recorded. Dedicated-server behavior is not established by these local checks; the mod explicitly disables its work on a dedicated-server process.

## Layout

```text
QuickMissionLoad.mod
scripts/mods/QuickMissionLoad/QuickMissionLoad.lua
scripts/mods/QuickMissionLoad/QuickMissionLoad_data.lua
scripts/mods/QuickMissionLoad/QuickMissionLoad_localization.lua
scripts/mods/QuickMissionLoad/mission_manifest.lua
scripts/mods/QuickMissionLoad/mission_warmup.lua
```

The bootstrap owns five hooks and DMF/event lifecycle slots, including the briefing setting cache. `mission_manifest.lua` resolves package names without loading them or creating game objects. `mission_warmup.lua` owns target discovery, reconciliation, scheduling, and reference cleanup. Reconciliation keeps callback entry identities intact; cleanup advances a generation, and removed entries reject late callbacks.

`tests/warmup_spec.lua` is a development-only behavioral harness, never loaded by the mod and not intended for a release payload.

## Verification

Run from the workspace root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate.ps1 -Path "mods\active\QuickMissionLoad"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate.ps1 -Path "mods\active\QuickMissionLoad\tests\warmup_spec.lua"
& ".\lua-5.5.0_Win64_bin\lua55.exe" "mods\active\QuickMissionLoad\tests\warmup_spec.lua"
```

The behavioral harness uses mocked package completions and source-data fixtures to check intersections, late/duplicate callbacks, deferred dependency discovery, limits, cancellation, quickplay/Havoc, Expedition snapshots, and lifecycle cleanup. Briefing checks cover default/localized settings, cached reads, disabled/setting/dedicated-server gates, lobby and absent UI/view cases, mid-VO enabling, remaining-timer bypass, and preservation of original arguments and multiple returns. It is not an in-game test or proof of native loading behavior.

Briefing manual checks still required: enter a normal mission with the default setting and confirm no briefing VO, successful entry and no leftover audio; repeat with the setting off; enable during playing VO and confirm natural completion; toggle off after suppression; verify lobby waiting and full DMF reload during an intro. No timing improvement is measured or guaranteed, and Psykhanium cannot prove dedicated-server-backed mission behavior.

The remaining manual checks are: a selected-mission vote and cancellation; quickplay assignment; a same-map circumstance/theme change; normal loading finish; disable and full DMF reload during pending loads; an aborted load returning to title/menu; and an Expedition whose generated layout is available before the stop event. Observe package reference cleanup as well as successful entry. Havoc, Expedition, reconnect/party join, and dedicated-server-backed missions remain untested in game.
