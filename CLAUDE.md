# WoW Weekly Addon — Design & Build Notes

## Overview
A Retail WoW addon (Ace3 stack) that tracks completion of weekly tasks across a main character and alts. Similar to SavedInstances but focused on Barry's specific chores: **4× Tier 11 Delves per week, Keyshards, and Professions knowledge**.

## Locked Decisions

### Architecture
- **Target:** Retail client (Midnight 12.1.0, Interface 120100)
- **Framework:** Ace3 (AceAddon, AceEvent, AceDB, AceConfig, AceConsole) + LibDataBroker + LibQTip + LibDBIcon
- **Character ID:** `Name-Realm` string (account-wide single dataset, no profiles)
- **Persistence:** SavedVariables (`WoWWeeklyDB`) — per-account, survives `/reload`, wipes only on reset
- **Data Model:** Each character's state is a snapshot recorded on login; no live cross-character updates
- **Stale-week detection:** Stamp each character with `resetPeriodId` on login; compare to current period ID to flag old rows in UI

### Tracker Registry Pattern
Each weekly activity is a self-contained Lua module that:
1. Registers itself with `TrackerRegistry:Register()`
2. Implements a contract: `id`, `label`, `icon`, `Scan()`, `IsComplete()`, `GetSummary()`, `RenderTooltip()`
3. Can be added/removed by adding/deleting one file — no core changes
4. Listens to game events (e.g., `SCENARIO_COMPLETE`) to trigger re-scans

This makes the addon extensible: adding a new tracker = one new file under `Trackers/`.

### Weekly Reset
- `WeeklyReset:GetCurrentResetPeriodId()` = `floor((time() + C_DateAndTime.GetSecondsUntilWeeklyReset()) / 604800)` — anchored to the real region reset (Tue 15:00 UTC US), not an arbitrary epoch
- `CheckAndApplyWeeklyReset()` runs on login and on tooltip open; it sweeps ALL stored characters and wipes/restamps any char whose `resetPeriodId` is from an old week (the in-game reset clears everyone, logged in or not)
- The sweep is cadence-aware: `cadence = "persistent"` state is kept (Coffer Keys, Ready to Craft crests); trackers with an `OnWeeklyReset` hook partially reset (professions); everything else is wiped
- Stale rows (from prior weeks) are flagged gray in the alt grid — safety-net only; the sweep normally clears them first

## File Structure

```
wow-weekly/
├─ wow-weekly.toc           (manifest)
├─ embeds.xml              (library includes)
├─ Constants.lua           (addon-wide constants; TODO: currency/quest IDs)
├─ Core.lua                (AceAddon init, slash commands /wweekly)
├─ Database.lua            (char registration, Name-Realm key)
├─ WeeklyReset.lua         (reset period ID, stale-week detection)
├─ TrackerRegistry.lua     (tracker registry + Scan dispatch)
├─ Trackers/
│  ├─ Delves.lua           (4× Tier 11 per week) [SKELETON]
│  └─ (Keyshards, Professions, etc. to follow)
├─ UI/
│  ├─ Broker.lua           (LibDataBroker minimap button)
│  ├─ Tooltip.lua          (LibQTip alt grid + tracker columns)
│  └─ (Options.lua to follow)
├─ Libs/                   (vendored Ace3, LibDataBroker, LibQTip, LibDBIcon)
├─ CLAUDE.md               (this file)
└─ docs/
   └─ DESIGN.md            (confirmed APIs, quest IDs, currency IDs, event names)
```

## SavedVariables Schema

```lua
WoWWeeklyDB = {
  dbVersion = 1,
  chars = {
    ["Tankadin-Illidan"] = {
      name = "Tankadin",
      realm = "Illidan",
      class = "Paladin",
      classFile = "PALADIN",
      faction = "Horde",
      level = 80,
      ilvl = 639,
      lastSeen = <epoch>,
      resetPeriodId = <week_id>,
      trackers = {
        delves = { tier11Count = 3, completed = false, lastUpdated = <epoch> },
        keyshards = { shards = 150, keysEarned = 5, lastUpdated = <epoch> },
        professions = { weeklyQuests = {...}, done = false, lastUpdated = <epoch> },
      },
    },
    ...
  },
  global = {
    currentResetPeriodId = <week_id>,
    nextWeeklyResetAt = <epoch>,
  },
  profileOptions = {
    minimap = { hide = false },
    enabledTrackers = { delves = true, keyshards = true, ... },
    sortKey = "ilvl",  -- or "name"
  },
}
```

## Tracker Contract

Each tracker module must export a table with:

```lua
{
  id              = "delves",        -- stable registry key
  label           = "Delves",        -- display name
  icon            = <textureid>,     -- icon for UI
  category        = "weekly",
  cadence         = "weekly",        -- or "persistent": state survives the reset sweep (banked currencies)
  events          = {"SCENARIO_COMPLETE", ...},  -- game events that trigger Scan
  enabledByDefault = true,

  -- Functions
  Scan(charState),           -- read game state, update charState.trackers[id]
  IsComplete(charState) -> bool,    -- returns true if done for the week
  GetSummary(charState) -> string,  -- short text like "3/4" or "150/250"
  RenderTooltip(charState, tooltip, lineNum),  -- render one row in the alt grid
  OnWeeklyReset(charState),  -- OPTIONAL: partial reset at the sweep (professions keep
                             -- the prof name, clear done flags); omit = state is wiped
}
```

## Known Unknowns — To Be Confirmed In-Game

### Delves
- **Completion event:** Is it `SCENARIO_COMPLETE` or `CHALLENGE_MODE_COMPLETE`? Exact event name and args.
- **Tier detection:** Can we read the delve tier from `C_ScenarioInfo` or do we need to walk the scenario modifiers?
- **Great Vault World track:** Does `C_WeeklyRewards.GetActivities(Enum.WeeklyRewardChestThresholdType.World)` exist and give delve progress?

### Currency IDs
- `CURRENCY_COFFER_KEY_SHARD` — exact currency ID (currently 0, needs `/dump C_CurrencyInfo`)
- `CURRENCY_RESTORED_COFFER_KEY` — same

### Profession Weekly Quests
- Exact quest IDs per profession per patch (patch-specific; confirm in-game or via Wowhead)
- Artisan's Acuity currency ID (if tracking)

## Build / Test Loop

1. **Edit code** in VS Code or text editor
2. **Reload UI** in-game: `/reload` (or Ctrl+R in some addon managers)
3. **Inspect state:** `/dump WoWWeeklyDB` or `/dump WoWWeeklyDatabase:GetCharState()`
4. **Trace events:** `/etrace` (if using a trace addon), run the action, watch event log
5. **Verify UI:** click minimap button, check tooltip grid

## Next Steps

**Phase 1:** Delves tracker (confirm event, tier detection, counting logic)
- Use `/etrace` to find the exact event fired when a delve completes
- Extract tier from event args or scenario data
- Wire up the Scan() logic

**Phase 2:** Keyshards tracker (confirm currency IDs, add to tracker)

**Phase 3:** Professions tracker (confirm quest IDs per profession, add to tracker)

**Phase 4:** Options panel (toggle trackers, minimap hide, sort key)

**Phase 5:** CustomChecklist tracker (arbitrary ad-hoc items)

## Dev Notes

- **No test harness:** WoW addon dev is inherently iterative (`/reload` loop). Embrace it.
- **Lib vendoring:** All Ace3 + LDB + LibQTip libraries are committed in `Libs/` so the addon is self-contained. No external lib downloads at runtime.
- **Error handling:** WoW's Lua doesn't have strict error propagation; use `if not X then` checks liberally.
- **Global namespace:** All module exports are stored in `_G[ADDON_NAME .. "ModuleName"]` to avoid collisions.
- **Event dispatch:** Core.lua sets up `AceEvent-3.0` for WoW events; trackers can register via `WoWWeekly:RegisterEvent()`.

## Barry's Context
Barry is a DB/martech expert, new to Lua and WoW addon dev. The addon should:
- Track his specific chores (Delves, Keyshards, Professions) — NOT M+ or raiding
- Show all alts at a glance in a multi-column grid (similar to SavedInstances)
- Be extensible (add new trackers without touching core code)
- Survive `/reload` but reset weekly
