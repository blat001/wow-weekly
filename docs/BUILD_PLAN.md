# WoW Weekly — Build Plan (for the implementer)

> **Read this first.** This is a precise, step-by-step build spec. Do the phases **in order**.
> Do **not** invent APIs, do **not** create stub libraries, and do **not** skip steps.
> If a real library will not download, copy it from an already-installed addon (see Phase 1) —
> **never** replace it with a hand-written stub.
>
> **Target client:** Retail WoW **Interface 120100** (Midnight 12.1.0).
> **Test loop:** edit files in `C:\working\wow-weekly` → copy to the AddOns folder → `/reload` → `/ww dump`.

---

## Locked design decisions (do not re-litigate)

| Decision | Choice |
|---|---|
| Titan integration | **LDB broker + Titan's LDB bridge** (the SavedInstances pattern). Keep the LibDataBroker object; Titan auto-detects it. **No native Titan plugin code.** |
| Minimap button | **Removed.** Delete the `LibDBIcon:Register` call. Keep the LDB object (Titan needs it). |
| Tooltip library | **Real LibQTip-1.0**, vendored. Delete the stub. |
| Grid orientation | **Columns = characters, rows = trackers** (matches `ui example.md`). |
| Char identity | `Name-Realm` (unchanged). |

### Target UI (from `ui example.md`)

```
                | Character 1 | Character 2 | Character 3
Delves          |   2 of 8    |   2 of 8    |   2 of 8
Bounty Map      |   Used      |  Not Found  |  In Bags
Coffer Keys     |     2       |     1       |     0
Coffer Key Shards|  Done      |     0       |    550
Weekly Profession|  Done      |     No      |    No
Ready to Craft  |    Yes      |     No      |    No      (Yes = you have 90 myth crests)
```

---

## Tracker set (final)

Replace the old `delves / keyshards / professions / greatvault / custom` set with these **six** trackers.
Each is one file in `Trackers/`, self-registering (the existing registry pattern is unchanged).

| Row | Tracker id | File | Summary values | Color rule |
|---|---|---|---|---|
| Delves | `delves` | `Trackers/Delves.lua` | `"X of 8"` (tier 8+ count) | red if `X<4`, green if `X>=4` |
| Bounty Map | `bountymap` | `Trackers/BountyMap.lua` | `Used` / `Not Found` / `In Bags` | green=Used, yellow=In Bags, gray=Not Found |
| Coffer Keys | `cofferkeys` | `Trackers/CofferKeys.lua` | numeric count | white (informational) |
| Coffer Key Shards | `cofferkeyshards` | `Trackers/CofferKeyShards.lua` | `Done` or numeric (e.g. `550`) | green=Done, white=number |
| Weekly Profession | `weeklyprofession` | `Trackers/WeeklyProfession.lua` | `Done` / `No` | green=Done, red=No |
| Ready to Craft | `readytocraft` | `Trackers/ReadyToCraft.lua` | `Yes` / `No` | green=Yes, red=No |

Delete `Trackers/Keyshards.lua` and `Trackers/Professions.lua` if they exist (replaced above).

---

## Phase 0 — Constants & known-unknowns

Every game ID below is **patch-specific and currently unknown**. Add them to `Constants.lua` as
placeholders, then confirm them in-game with the `/ww find` helper built in Phase 7. **Do not guess IDs.**

Add to `Constants.lua`:

```lua
-- Delves (Great Vault world track)
Constants.DELVE_VAULT_MAX      = 8   -- max meaningful weekly delves
Constants.DELVE_HERO_THRESHOLD = 4   -- >= this => green (Hero gear vault slot secured)
Constants.DELVE_MIN_TIER       = 8   -- only tier 8+ delves count toward the world track

-- Currency IDs (CONFIRM IN-GAME with /ww find coffer  /  /ww find crest)
Constants.CURRENCY_RESTORED_COFFER_KEY = 0  -- "Restored Coffer Key"  -> Coffer Keys row
Constants.CURRENCY_COFFER_KEY_SHARD    = 0  -- "Coffer Key Shard"     -> Coffer Key Shards row
Constants.CURRENCY_MYTH_CREST          = 0  -- highest "Crest" currency -> Ready to Craft
Constants.MYTH_CREST_CRAFT_THRESHOLD   = 90 -- Ready to Craft = Yes when crests >= this

-- Coffer Key Shard "Done" threshold (weekly cap). CONFIRM cap in-game.
Constants.COFFER_SHARD_DONE_AT         = 0  -- set to the weekly cap once known

-- Bounty Map (CONFIRM with /ww find bounty)
Constants.ITEM_DELVERS_BOUNTY_MAP      = 0  -- item id of the Delver's Bounty Map (In Bags check)
Constants.QUEST_BOUNTY_USED            = 0  -- hidden quest id flagged when bounty consumed (Used check)

-- Weekly Profession knowledge quests, keyed by profession skill-line.
-- CONFIRM each quest id in-game (complete it, diff C_QuestLog.GetAllCompletedQuestIDs()).
Constants.PROFESSION_WEEKLY_QUESTS = {
  -- [professionDisplayName] = questID,
  -- Alchemy = 0, Blacksmithing = 0, ... (fill in as confirmed)
}

-- Colors (reuse existing COLOR_* if already defined)
Constants.COLOR_GREEN  = "|cFF00FF00"
Constants.COLOR_RED    = "|cFFFF0000"
Constants.COLOR_YELLOW = "|cFFFFFF00"
Constants.COLOR_GRAY   = "|cFF808080"
Constants.COLOR_WHITE  = "|cFFFFFFFF"
Constants.COLOR_RESET  = "|r"
```

---

## Phase 1 — Vendor real LibQTip-1.0, remove stubs & minimap

**1a. Get the real LibQTip-1.0.** Preferred source (canonical):

```
git clone https://github.com/Torhal/LibQTip-1.0.git
```

Copy `LibQTip-1.0.lua`, `lib.xml`, and the `LibStub/` folder into `Libs\LibQTip-1.0\`,
**overwriting the stub.** Delete the old stub `LibQTip-1.0.lua` contents entirely.

> **If the clone fails:** copy the `LibQTip-1.0` folder from any installed addon that ships it
> (e.g. `...\Interface\AddOns\SavedInstances\Libs\LibQTip-1.0\` or `...\TitanClassic*\` ).
> This guarantees a build compatible with the live client. **Do not write a stub.**

**1b. `embeds.xml`** — replace the stub line with the library's own xml, and **remove LibDBIcon**:

```xml
    <!-- remove this line entirely: -->
    <!-- <Script file="Libs\LibDBIcon-1.0\LibDBIcon-1.0.lua"/> -->

    <!-- replace the LibQTip stub <Script .../> line with: -->
    <Include file="Libs\LibQTip-1.0\lib.xml"/>
```

(LibDataBroker-1.1 stays.) You may delete the `Libs\LibDBIcon-1.0\` folder.

**1c. `wow-weekly.toc`** — add Titan as an optional dependency so load order is friendly:

```
## OptionalDeps: Titan, !LibUIDropDownMenu
```

Remove any line that loads a LibDBIcon file.

---

## Phase 2 — Broker.lua: LDB data source + LibQTip on mouseover

Rewrite `UI/Broker.lua` so it:
1. Creates an LDB object of type **`"data source"`** with an `icon`.
2. On `OnEnter(frame)` shows the LibQTip grid anchored to `frame` (the Titan button).
3. Uses LibQTip's **auto-hide** so you don't have to hand-manage OnLeave.
4. **No LibDBIcon.**

```lua
local ADDON_NAME = "WoWWeekly"
local WoWWeekly  = _G[ADDON_NAME]
local Constants  = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]

local Broker = {}

function Broker:Initialize()
    if self.ldb then return end
    self.ldb = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON_NAME, {
        type = "data source",
        text = "WoW Weekly",
        icon = "Interface\\Icons\\inv_misc_note_01",
        label = "WoW Weekly",
        OnClick = function(_, button) Broker:OnClick(button) end,
        OnEnter = function(frame)
            local Tooltip = _G[ADDON_NAME .. "Tooltip"]
            if Tooltip then Tooltip:Show(frame) end
        end,
        -- No OnLeave needed: LibQTip auto-hides (see Tooltip:Show).
    })
end

function Broker:OnClick(button)
    if button == "RightButton" then
        WoWWeekly:Print("Options panel not yet implemented")
    else
        local Tooltip = _G[ADDON_NAME .. "Tooltip"]
        if Tooltip then Tooltip:Show() end
    end
end

function Broker:UpdateText()
    local Database = _G[ADDON_NAME .. "Database"]
    local charState = Database and Database:GetCharState()
    if not charState then return end
    local delves = TrackerRegistry:GetTracker(Constants.TRACKER_DELVES)
    if delves then self.ldb.text = "Delves " .. delves:GetSummary(charState) end
end

_G[ADDON_NAME .. "Broker"] = Broker
```

Initialize it from `Core.lua:OnInitialize` (after db is ready), same place Database/WeeklyReset are
initialized — **not** at file-load time (that bug already bit us once).

---

## Phase 3 — Tooltip.lua: rewrite to the REAL LibQTip API

Replace `UI/Tooltip.lua`. Key real-API facts (the stub used a different, fake signature):

- `local tip = LibStub("LibQTip-1.0"):Acquire(key, numColumns, justify1, justify2, ...)`
  — **numColumns must be known up front** = `1 + (number of characters)`.
- `local line = tip:AddLine(v1, v2, ...)` returns the line number.
- `local line = tip:AddHeader(...)` for a header row.
- `tip:SetCell(line, col, text, font, justify, colSpan)` — `text` may contain `|cAARRGGBB...|r` color codes.
- `tip:SetCellTextColor(line, col, r,g,b[,a])` — alternative to color codes.
- `tip:AddSeparator()`.
- `tip:SmartAnchorTo(frame)` then `tip:SetAutoHideDelay(0.25, frame)` then `tip:Show()`.
- Release with `LibStub("LibQTip-1.0"):Release(tip)`.

```lua
local ADDON_NAME = "WoWWeekly"
local WoWWeekly  = _G[ADDON_NAME]
local Constants  = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
local WeeklyReset = _G[ADDON_NAME .. "WeeklyReset"]
local LibQTip = LibStub("LibQTip-1.0")

local Tooltip = {}

local function SortedCharKeys(db)
    local keys = {}
    for k in pairs(db.chars) do keys[#keys+1] = k end
    table.sort(keys, function(a,b)
        local A,B = db.chars[a], db.chars[b]
        if A.level ~= B.level then return A.level > B.level end
        if (A.ilvl or 0) ~= (B.ilvl or 0) then return (A.ilvl or 0) > (B.ilvl or 0) end
        return a < b
    end)
    return keys
end

function Tooltip:Show(anchorFrame)
    local db = WoWWeekly.db
    local charKeys = SortedCharKeys(db)
    local numCols = 1 + #charKeys

    if self.tip then LibQTip:Release(self.tip); self.tip = nil end

    -- column 1 left, character columns centered
    local just = {"LEFT"}
    for i = 1, #charKeys do just[#just+1] = "CENTER" end
    local tip = LibQTip:Acquire(ADDON_NAME .. "Tip", numCols, unpack(just))
    self.tip = tip

    -- Title
    local titleLine = tip:AddHeader("")
    tip:SetCell(titleLine, 1, Constants.COLOR_YELLOW .. "WoW Weekly" .. Constants.COLOR_RESET,
                nil, "LEFT", numCols)

    -- Header row: blank + character names (red "(old)" tag if the week is stale)
    local hdr = tip:AddLine("")
    for i, key in ipairs(charKeys) do
        local label = db.chars[key].name or key
        if WeeklyReset:IsWeekStale(key) then
            label = Constants.COLOR_GRAY .. label .. " (old)" .. Constants.COLOR_RESET
        end
        tip:SetCell(hdr, i + 1, label)
    end
    tip:AddSeparator()

    -- One row per tracker
    for _, tracker in pairs(TrackerRegistry:GetAll()) do
        local line = tip:AddLine(tracker.label)
        for i, key in ipairs(charKeys) do
            tip:SetCell(line, i + 1, tracker:GetSummary(db.chars[key]))
        end
    end

    if anchorFrame then tip:SmartAnchorTo(anchorFrame) end
    tip:SetAutoHideDelay(0.25, anchorFrame)
    tip:Show()
end

function Tooltip:Hide()
    if self.tip then LibQTip:Release(self.tip); self.tip = nil end
end

_G[ADDON_NAME .. "Tooltip"] = Tooltip
```

> Each tracker's `GetSummary(charState)` must return a **color-coded string** (see Phase 4–6).
> The tooltip just prints whatever the tracker returns, so keep all formatting inside the trackers.

---

## Phase 4 — Delves tracker (rework)

Use the **Great Vault world track** rather than counting scenarios. Confirm the enum/fields with `/etrace`
+ `/dump` (see Phase 7), but build to this shape:

```lua
function DelveTracker:Scan(charState)
    local st = charState.trackers[self.id] or {}
    local count = 0
    -- World vault track: slots at thresholds 2/4/8; progress = qualifying (tier 8+) delves done.
    local ok, activities = pcall(C_WeeklyRewards.GetActivities,
                                 Enum.WeeklyRewardChestThresholdType.World)
    if ok and activities then
        for _, a in ipairs(activities) do
            if (a.progress or 0) > count then count = a.progress end  -- highest reported progress
        end
    end
    st.count = count
    st.lastUpdated = time()
    charState.trackers[self.id] = st
end

function DelveTracker:GetSummary(charState)
    local st = charState.trackers[self.id] or {}
    local n = st.count or 0
    local color = (n >= Constants.DELVE_HERO_THRESHOLD) and Constants.COLOR_GREEN or Constants.COLOR_RED
    return string.format("%s%d of %d%s", color, n, Constants.DELVE_VAULT_MAX, Constants.COLOR_RESET)
end
```

**Confirm in-game:** that `Enum.WeeklyRewardChestThresholdType.World` exists on 12.1.0 and that delve
progress shows up there; otherwise fall back to counting `SCENARIO_COMPLETE` events where the scenario
is a delve of tier ≥ `DELVE_MIN_TIER` (record the event args via `/etrace`).

---

## Phase 5 — Currency trackers (Coffer Keys, Coffer Key Shards, Ready to Craft)

All three read `C_CurrencyInfo.GetCurrencyInfo(id)` → `.quantity`. Build once you have the IDs.

**CofferKeys.lua**
```lua
function T:Scan(cs)
    local q = 0
    local id = Constants.CURRENCY_RESTORED_COFFER_KEY
    if id and id > 0 then local info = C_CurrencyInfo.GetCurrencyInfo(id); q = info and info.quantity or 0 end
    cs.trackers[self.id] = { qty = q, lastUpdated = time() }
end
function T:GetSummary(cs)
    local st = cs.trackers[self.id] or {}
    return Constants.COLOR_WHITE .. tostring(st.qty or 0) .. Constants.COLOR_RESET
end
```

**CofferKeyShards.lua** — show `Done` at/above the weekly cap, else the number:
```lua
function T:GetSummary(cs)
    local st = cs.trackers[self.id] or {}
    local q = st.qty or 0
    if Constants.COFFER_SHARD_DONE_AT > 0 and q >= Constants.COFFER_SHARD_DONE_AT then
        return Constants.COLOR_GREEN .. "Done" .. Constants.COLOR_RESET
    end
    return Constants.COLOR_WHITE .. tostring(q) .. Constants.COLOR_RESET
end
```

**ReadyToCraft.lua** — `Yes` when myth crests ≥ threshold:
```lua
function T:Scan(cs)
    local q = 0
    local id = Constants.CURRENCY_MYTH_CREST
    if id and id > 0 then local info = C_CurrencyInfo.GetCurrencyInfo(id); q = info and info.quantity or 0 end
    cs.trackers[self.id] = { crests = q, lastUpdated = time() }
end
function T:GetSummary(cs)
    local st = cs.trackers[self.id] or {}
    local ready = (st.crests or 0) >= Constants.MYTH_CREST_CRAFT_THRESHOLD
    return ready and (Constants.COLOR_GREEN.."Yes"..Constants.COLOR_RESET)
                 or  (Constants.COLOR_RED.."No"..Constants.COLOR_RESET)
end
```

---

## Phase 6 — Bounty Map & Weekly Profession trackers

**BountyMap.lua** — three states:
```lua
function T:Scan(cs)
    local state = "notfound"
    if Constants.ITEM_DELVERS_BOUNTY_MAP > 0
       and (C_Item.GetItemCount(Constants.ITEM_DELVERS_BOUNTY_MAP) or 0) > 0 then
        state = "inbags"
    elseif Constants.QUEST_BOUNTY_USED > 0
       and C_QuestLog.IsQuestFlaggedCompleted(Constants.QUEST_BOUNTY_USED) then
        state = "used"
    end
    cs.trackers[self.id] = { state = state, lastUpdated = time() }
end
function T:GetSummary(cs)
    local s = (cs.trackers[self.id] or {}).state
    if s == "used"   then return Constants.COLOR_GREEN .."Used"..     Constants.COLOR_RESET end
    if s == "inbags" then return Constants.COLOR_YELLOW.."In Bags"..  Constants.COLOR_RESET end
    return Constants.COLOR_GRAY .. "Not Found" .. Constants.COLOR_RESET
end
```
> Confirm the bounty item id and the "used" detection (likely a hidden/weekly quest flag) in-game.

**WeeklyProfession.lua** — `Done` if the character's profession weekly quest is flagged complete:
```lua
function T:Scan(cs)
    local done = false
    -- Determine this char's professions via C_TradeSkillUI.GetAllProfessionTradeSkillLines()
    -- then map to Constants.PROFESSION_WEEKLY_QUESTS and check IsQuestFlaggedCompleted.
    for _, questID in pairs(Constants.PROFESSION_WEEKLY_QUESTS) do
        if questID > 0 and C_QuestLog.IsQuestFlaggedCompleted(questID) then done = true break end
    end
    cs.trackers[self.id] = { done = done, lastUpdated = time() }
end
function T:GetSummary(cs)
    local done = (cs.trackers[self.id] or {}).done
    return done and (Constants.COLOR_GREEN.."Done"..Constants.COLOR_RESET)
                or  (Constants.COLOR_RED.."No"..Constants.COLOR_RESET)
end
```

---

## Phase 7 — `/ww find` discovery helper (build this EARLY; you need it for the IDs)

Add a slash subcommand that dumps currencies / items / quests matching a keyword, into the copyable
dump window from Core.lua. This is how Barry confirms every `0` placeholder ID above.

```lua
-- in HandleSlashCommand, add:
elseif input:sub(1,4) == "find" then
    local term = input:sub(6):lower()
    local out = { "Matches for '" .. term .. "':" }
    -- currencies
    local n = C_CurrencyInfo.GetCurrencyListSize()
    for i = 1, n do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info and info.name and info.name:lower():find(term) then
            local link = C_CurrencyInfo.GetCurrencyListLink(i)
            out[#out+1] = string.format("CURRENCY  %s  qty=%s  link=%s", info.name, tostring(info.quantity), tostring(link))
        end
    end
    self:ShowDumpWindow(table.concat(out, "\n"))
```

Usage in-game: `/ww find coffer`, `/ww find crest`, `/ww find bounty`.
For quest IDs: `/dump C_QuestLog.GetAllCompletedQuestIDs()` before/after completing the weekly, then diff.

---

## Phase 8 — Wire-up & verification

1. `Core.lua:OnInitialize` initializes (in this order): Database → WeeklyReset → TrackerRegistry (scan) → Broker.
2. `TrackerRegistry:ScanAll()` runs on `PLAYER_LOGIN` and on each tracker's events.
3. Copy to `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\wow-weekly\`, `/reload`.
4. **Verify, in order:**
   - [ ] No Lua errors on login.
   - [ ] `/ww dump` shows the character and reset period.
   - [ ] With Titan Panel installed, "WoW Weekly" appears under Titan's **[LDB] plugins**; add it to the bar.
   - [ ] Mouse over the Titan button → LibQTip grid appears, columns = characters, rows = the six trackers.
   - [ ] `/ww find coffer` / `crest` / `bounty` returns IDs; paste them into `Constants.lua`; `/reload`.
   - [ ] Delves cell is red below 4, green at 4+; other rows match `ui example.md`.

---

## Definition of done

- Real LibQTip vendored (no stub), LibDBIcon removed.
- Titan shows the broker; mouseover renders the six-row grid with correct colors.
- All placeholder IDs in `Constants.lua` confirmed and filled, or clearly flagged as still-unknown
  with the `/ww find` method documented.
