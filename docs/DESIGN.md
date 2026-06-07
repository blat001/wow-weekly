# WoW Weekly — Tracker Specifications

This document records confirmed game data (quest IDs, currency IDs, events) that change between patches. Update it as you verify each value in-game.

## Delves Tracker

**Goal:** 4× Tier 11 Delves per character per week

### Confirmed Data (WIP)

| Item | Value | Status | Notes |
|------|-------|--------|-------|
| Completion event | ??? | TODO | Use `/etrace`, complete a delve, check event log |
| Tier read method | ??? | TODO | Check `C_ScenarioInfo` vs event args |
| Great Vault World API | ??? | TODO | Test `C_WeeklyRewards.GetActivities()` |

### Scan Logic (Skeleton)

```lua
function DelveTracker:Scan(charState)
  -- TODO:
  -- 1. Count scenario completions where tier == 11 this week
  -- 2. Cross-check against Great Vault World track for confidence
  -- 3. Update charState.trackers.delves = { tier11Count = X, completed = (X >= 4) }
end
```

---

## Keyshards Tracker

**Goal:** Track Coffer Key Shards / Restored Coffer Keys (currency)

### Confirmed Data (WIP)

| Currency | ID | Cap | Status |
|----------|----|----|--------|
| Coffer Key Shard | 0 | ??? | TODO: `/dump C_CurrencyInfo.GetCurrencyListSize()` |
| Restored Coffer Key | 0 | ??? | TODO: same |

### Scan Logic (Skeleton)

```lua
function KeyshardTracker:Scan(charState)
  -- TODO:
  -- 1. Get shard quantity: C_CurrencyInfo.GetCurrencyInfo(SHARD_ID)
  -- 2. Get key quantity: C_CurrencyInfo.GetCurrencyInfo(KEY_ID)
  -- 3. Track weekly earned (delta from prior snapshot? or query some other source?)
  -- 4. Update charState.trackers.keyshards = { shards = X, keysEarned = Y }
end
```

---

## Professions Tracker

**Goal:** Track weekly profession knowledge quests (per-profession quest IDs)

### Confirmed Data (WIP)

| Profession | Quest ID | Status |
|-----------|----------|--------|
| Alchemy | 0 | TODO |
| Blacksmithing | 0 | TODO |
| Enchanting | 0 | TODO |
| Engineering | 0 | TODO |
| Herbalism | 0 | TODO |
| Inscription | 0 | TODO |
| Jewelcrafting | 0 | TODO |
| Leatherworking | 0 | TODO |
| Mining | 0 | TODO |
| Skinning | 0 | TODO |
| Tailoring | 0 | TODO |
| ... | 0 | TODO |

**Artisan's Acuity Currency ID:** (tracking optional, TBD)

### Scan Logic (Skeleton)

```lua
function ProfessionsTracker:Scan(charState)
  -- TODO:
  -- 1. For each profession the character has, check C_QuestLog.IsQuestFlaggedCompleted(questID)
  -- 2. Count completed / total professions
  -- 3. Optionally track Artisan's Acuity earned this week
  -- 4. Update charState.trackers.professions = { weeklyQuests = {...}, done = (all_done) }
end
```

---

## How to Confirm Unknown Values

### For Events (Delves)
```
/etrace
(complete a Tier 11 delve)
(watch the event log for SCENARIO_*, CHALLENGE_*, GARRISON_* events)
Note the event name and its arguments (print to chat or addon console)
```

### For Currency IDs
```
/dump C_CurrencyInfo.GetCurrencyListSize()
(returns N, the count of currencies)

for i=1, N do
  local info = C_CurrencyInfo.GetCurrencyInfo(i)
  if info and info.name and string.find(string.lower(info.name), "coffer") then
    print(i, info.name, info.quantity, info.maxQuantity)
  end
end
```

### For Quest IDs
```
/dump C_QuestLog.GetAllCompletedQuestIDs()
(complete a profession weekly quest, then re-run)
(diff the two lists to find the new quest ID)

Or: check Wowhead for "[patch] weekly profession" quests
```

---

## Updates Log

- **2026-06-06:** Initial skeleton created. All values TBD.

