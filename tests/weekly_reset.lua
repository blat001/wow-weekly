-- Weekly reset, login loading, and stale qualifying-run regressions.
local now, remaining = 1800000000, 1000
time = function() return now end
Enum = { WeeklyRewardChestThresholdType = { World=1, Activities=2, Raid=3 } }
dofile('Constants.lua')
local addon = {Print=function() end}
LibStub = function() return {NewAddon=function() return addon end} end
dofile('Core.lua')
addon.db = {global={}, chars={}}
dofile('TrackerRegistry.lua')
local registry = WoWWeeklyTrackerRegistry
for _, name in ipairs({'Delves', 'MythicPlus', 'Raid'}) do dofile('Trackers/'..name..'.lua') end
C_DateAndTime = {GetSecondsUntilWeeklyReset=function() return remaining end}
dofile('WeeklyReset.lua')
local reset = WoWWeeklyWeeklyReset
local period = reset:GetCurrentResetPeriodId()
local function completed()
    return {resetPeriodId=period, trackers={
        delves={count=8, rawProgress=8, qualifiedRuns=8},
        mythicplus={count=8, rawProgress=8, qualifiedRuns=8},
        raid={count=6, rawProgress=6},
        keys={count=7}, profession={weeklyDone=true, name='Alchemy'},
    }}
end
registry:Register({id='keys', label='Keys', cadence='persistent'})
registry:Register({id='profession', label='Profession', OnWeeklyReset=function(_, char)
    char.trackers.profession.weeklyDone = false
end})
local main, alt = completed(), completed()
addon.db.chars = {main=main, alt=alt}
WoWWeeklyDatabase = {GetCharState=function() return main end}
local loading, progress, details = true, 0, {}
C_WeeklyRewards = {
    GetActivities=function(kind)
        if loading then return {} end
        local thresholds = kind == 2 and {1,4,8} or kind == 3 and {2,4,6} or {2,4,8}
        local rows = {}
        for _, threshold in ipairs(thresholds) do
            rows[#rows+1] = {threshold=threshold, progress=progress, level=10}
        end
        return rows
    end,
    GetSortedProgressForActivity=function() return details end,
}
C_MythicPlus = {GetRunHistory=function() return details end}
-- Unknown reset time must neither throw on initialization nor restamp characters.
remaining = nil
reset:Initialize()
assert(main.resetPeriodId == period and main.trackers.delves.count == 8)
remaining = 1000
reset:CheckAndApplyWeeklyReset()
assert(main.trackers.delves.count == 8, 'same-week snapshots survive')
-- A rewards event crossing reset sweeps offline characters before scanning.
now = now + 1001
remaining = 604799
addon:OnWeeklyRewardsUpdate()
assert(main.resetPeriodId == period + 1 and alt.resetPeriodId == period + 1)
assert(main.trackers.delves.count == nil and alt.trackers.delves == nil)
assert(alt.trackers.keys.count == 7 and alt.trackers.profession.name == 'Alchemy')
assert(not alt.trackers.profession.weeklyDone)
assert(addon.db.global.nextWeeklyResetAt == now + remaining)

-- Repair an already contaminated current-week cache when valid zero rows arrive.
loading = false
for _, data in ipairs({{}, {{difficulty=8, numPoints=8, level=10}}}) do
    details = data
    main.trackers.delves = {count=8, rawProgress=8, qualifiedRuns=8}
    main.trackers.mythicplus = {count=8, rawProgress=8, qualifiedRuns=8}
    addon:OnWeeklyRewardsUpdate()
    for _, id in ipairs({'delves', 'mythicplus'}) do
        assert(main.trackers[id].qualifiedRuns == 0)
        assert(not registry:GetTracker(id):IsComplete(main))
        assert(not registry:GetTracker(id):IsGoalMet(main))
    end
end
-- Partial current-week progress also bounds stale detail/history and cached totals.
progress = 2
addon:OnWeeklyRewardsUpdate()
assert(main.trackers.delves.qualifiedRuns == 2)
assert(main.trackers.mythicplus.qualifiedRuns <= 2)
-- A genuinely unavailable response still preserves this week's known progress.
loading = true
addon:OnWeeklyRewardsUpdate()
assert(main.trackers.delves.qualifiedRuns == 2)
-- Full scans also apply reset before any tracker can read an old-week cache.
now = now + 604800
registry:ScanAll()
assert(main.trackers.delves.qualifiedRuns == nil)
assert(main.trackers.keys.count == 7)
print('Weekly reset and stale Vault progress checks passed')
