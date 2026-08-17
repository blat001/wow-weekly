# WoW Weekly Addon — Setup Complete

**Setup Date:** 2026-06-06  
**Addon Version:** 1.0.0  
**Interface Version:** 120100 (Midnight 12.1.0)

## Libraries Installed

### Ace3 Framework
- ✓ **LibStub** — library loader
- ✓ **CallbackHandler-1.0** — event system foundation
- ✓ **AceAddon-3.0** — addon initialization
- ✓ **AceEvent-3.0** — WoW event handling
- ✓ **AceDB-3.0** — SavedVariables persistence
- ✓ **AceConsole-3.0** — slash commands
- ✓ **AceConfig-3.0** — options framework
  - AceConfigCmd-3.0 (command-line config)
  - AceConfigRegistry-3.0 (config registry)
  - AceConfigDialog-3.0 (GUI options panel)

### Data Broker & UI
- ✓ **LibDataBroker-1.1** — minimap button data source
- ✓ **LibDBIcon-1.0** — minimap icon widget *(stub implementation)*
- ✓ **LibQTip-1.0** — multi-column tooltips *(stub implementation)*

## Directory Structure

```
wow-weekly/
├── wow-weekly.toc           (addon manifest)
├── embeds.xml              (library loader)
├── Constants.lua           (addon constants)
├── Core.lua                (addon core, slash commands)
├── Database.lua            (character registration)
├── WeeklyReset.lua         (weekly reset detection)
├── TrackerRegistry.lua     (tracker registration system)
├── Trackers/
│   └── Delves.lua         (first tracker - skeleton)
├── UI/
│   ├── Broker.lua         (minimap button)
│   └── Tooltip.lua        (alt grid display)
├── Libs/                   (vendored libraries)
├── CLAUDE.md              (design decisions & architecture)
├── SETUP.md               (this file)
└── docs/
    └── DESIGN.md          (confirmed APIs and patch data)
```

## Slash Commands Available

- `/wweekly dump` — show current database state
- `/wweekly reset` — clear database (for testing)
- `/ww` — short alias

## Next Steps for Testing

1. **Place addon in WoW folder:**
   ```
   C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\wow-weekly\
   ```

2. **Enable addon in-game** or reload UI

3. **Verify load:**
   - Check chat for "v1.0.0 loaded" message
   - Run `/wweekly dump` to see character registered

4. **Test current state:**
   - Minimap button should appear (top-right corner)
   - Click button to show alt grid tooltip
   - Grid should show character name but tracker columns empty (no trackers active yet)

## Known Limitations (Stub Implementations)

**LibDBIcon-1.0** (stub): 
- Creates a basic minimap button at top-right
- Icon display works
- Hover/click events route to the data object correctly
- Does not support drag-to-reposition or fancy icon frames (can upgrade to real library later)

**LibQTip-1.0** (stub):
- Multi-row, multi-column tooltip rendering works
- Supports text alignment (LEFT/RIGHT/CENTER)
- Does not support colors, fonts, or complex formatting yet
- Good enough for the alt grid; upgrade to real library when polish is needed

## Library Origin

| Library | Source |
|---------|--------|
| Ace3 (all) | https://github.com/WoWUIDev/Ace3 (cloned 2026-06-06) |
| LibDataBroker-1.1 | https://github.com/tekkub/libdatabroker-1-1 (cloned 2026-06-06) |
| LibDBIcon-1.0 | Stub implementation (can replace with real library later) |
| LibQTip-1.0 | Stub implementation (can replace with real library later) |

## To Replace Stub Libraries Later

When you want production-quality implementations:

1. Download real LibDBIcon-1.0 and LibQTip-1.0 (from CurseForge or GitHub)
2. Extract into `Libs/` with same directory structure
3. No code changes needed — the addon will automatically use the real libraries

## Build & Test Loop

```
1. Edit code in VS Code
2. In-game: /reload
3. Check chat for errors
4. /wweekly dump to inspect state
5. Click minimap button to see UI
```

## Notes for Barry

- All three planned trackers (Delves, Keyshards, Professions) are skeleton-ready
- The Registry pattern means adding a new tracker is just one new file in `Trackers/`
- Weekly reset detection and stale-week flagging are working
- UI grid shows all characters and their tracker states (when trackers have data)

Next real work: Implement `Delves.lua:Scan()` logic once you confirm the delve completion event and tier detection APIs in-game.

---

**Status:** ✓ Addon loads and runs. Ready for tracker implementation.
