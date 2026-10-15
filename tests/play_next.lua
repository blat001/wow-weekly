-- Exercise the actual tooltip renderer, including independent pagination.
unpack = unpack or table.unpack
time = function() return 1800000000 end
dofile('Constants.lua')
local C = WoWWeeklyConstants
WoWWeekly = { db = { chars = {}, profileOptions = {} } }
local trackers = {}
WoWWeeklyTrackerRegistry = {
    Register = function(_, t) trackers[t.id] = t end,
    GetAll = function() return trackers end,
}
WoWWeeklyDatabase = { charKey = 'a' }
WoWWeeklyWeeklyReset = { IsWeekStale = function() return false end }
local cells = {}
local tip = setmetatable({ lines = {}, AddLine = function() return 1 end, AddHeader = function() return 1 end,
    SetCell = function(_, _, _, value) cells[#cells + 1] = value end },
    { __index = function() return function() end end })
LibStub = function() return { Acquire = function() return tip end, Release = function() end } end
for _, file in ipairs({'Delves', 'MythicPlus', 'Raid'}) do dofile('Trackers/' .. file .. '.lua') end
dofile('UI/Tooltip.lua')
dofile('UI/Config.lua')
local function character(name, runs, ilvl, focus)
    return { name = name, ilvl = ilvl or 280, playedSeason = C.MIDNIGHT_SEASON_KEY,
        gamePlanGoal = { focus = focus or 'delves', vaultSlots = 3 },
        trackers = { delves = { count = runs, qualifiedRuns = runs, rawProgress = runs } } }
end
local function render(chars, page)
    WoWWeekly.db.chars = chars
    WoWWeeklyTooltip.page = page or 1
    cells = {}
    WoWWeeklyTooltip:Show(nil, true)
    local text = table.concat(cells, '\n'):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', '')
    return assert(text:match('Play Next\n(.-)Weekly Status')), assert(text:match('Weekly Status\n(.*)'))
end
local function before(text, a, b)
    assert(assert(text:find(a, 1, true)) < assert(text:find(b, 1, true)), a .. ' should precede ' .. b)
end
-- A full Labyrinth is useful early in the week, but not for a one-credit
-- finish. Preserve owned-map priority, goal gating, and older-client behavior.
dofile('Trackers/BountyMap.lua')
GetBuildInfo = function() return '12.1.5', '', '', 120105 end
local labyrinthChar = character('Labyrinth', 0)
labyrinthChar.trackers.bountymap = {state='notlooted'}
local labyrinthPlan = render({a=labyrinthChar})
assert(labyrinthPlan:find('all 9 chambers', 1, true))
assert(labyrinthPlan:find('3 World Vault credits', 1, true))
assert(not labyrinthPlan:find('Complete Purging the Vaults', 1, true))
assert(labyrinthPlan:find('~60 min estimated', 1, true))
labyrinthChar.trackers.bountymap.state = 'inbags'
assert(render({a=labyrinthChar}):find('Use your Map', 1, true))
labyrinthChar.trackers.bountymap.state = 'notlooted'
labyrinthChar.trackers.delves = {count=4, qualifiedRuns=7, rawProgress=7}
assert(not WoWWeeklyDelveTracker:GetLabyrinthAction(labyrinthChar))
labyrinthChar.trackers.delves = {count=0, qualifiedRuns=0, rawProgress=0}
labyrinthChar.gamePlanGoal.vaultSlots = 1
assert(not WoWWeeklyDelveTracker:GetLabyrinthAction(labyrinthChar))
labyrinthChar.gamePlanGoal.vaultSlots = 3
GetBuildInfo = function() return '12.1.0', '', '', 120100 end
assert(not WoWWeeklyDelveTracker:GetLabyrinthAction(labyrinthChar))
GetBuildInfo = nil
trackers.bountymap = nil
local chars = { a = character('Current', 4), b = character('Closer', 7), c = character('Done', 8) }
local plan, status = render(chars)
before(plan, 'Closer', 'Current')
before(plan, 'Current', 'Done')
before(status, 'Current', 'Closer')
assert(plan:find('1 more Tier 8 Delve', 1, true))
assert(plan:find('~20 min estimated', 1, true))
chars.c = character('TargetMet', 2)
chars.c.gamePlanGoal.vaultSlots = 1
plan = render(chars)
before(plan, 'Current', 'TargetMet')
assert(plan:find('Weekly targets met', 1, true), 'selected target does not require all eight delves')

-- Compare units of work, not percentages: a single delve beats a dungeon
-- including setup; within a similar effort band the lower geared alt wins.
chars.a = character('Dungeon', 0, 270, 'mplus')
chars.a.trackers.mythicplus = { count = 0, qualifiedRuns = 0, rawProgress = 0, hasRuns = true }
plan = render(chars)
before(plan, 'Closer', 'Dungeon')
chars.a = character('HigherGear', 7, 300)
plan = render(chars)
before(plan, 'Closer', 'HigherGear')
chars.a.trackers.delves = { rawProgress = 7 }
plan = render(chars)
before(plan, 'Closer', 'HigherGear')
assert(plan:find('time estimate unavailable', 1, true))
chars.a = character('Multiple', 3)
chars.a.gamePlanGoal = { activities = { delves = true, mplus = true }, vaultSlots = 3 }
chars.a.trackers.mythicplus = { count = 1, qualifiedRuns = 3, rawProgress = 3, hasRuns = true }
plan = render({a = chars.a})
assert(plan:find('1 more Tier 8 Delve', 1, true), 'choose shorter milestone across selected goals')
assert(not plan:find('more +10', 1, true))

-- Only a confirmed raid starting within two hours can jump ahead.
C_DateAndTime = {
    GetCurrentCalendarTime = function() return 1000 end,
    AdjustTimeByMinutes = function(t, minutes) return t + minutes end,
    CompareCalendarTime = function(a, b) return a - b end,
}
chars.a = character('Raider', 0, 280, 'raid')
chars.a.trackers.raid = { count = 0, rawProgress = 0,
    calendar = { state = 'scheduled', startTime = 1060, timeText = 'soon' } }
plan = render(chars)
before(plan, 'Raider', 'Closer')
assert(plan:find('time-sensitive', 1, true))
chars.a.trackers.raid.calendar.state = 'pending'
plan = render(chars)
before(plan, 'Closer', 'Raider')
chars.a.trackers.raid.calendar.state = 'scheduled'
chars.a.trackers.raid.calendar.startTime = 900
plan = render(chars)
before(plan, 'Closer', 'Raider')

-- A top recommendation can come from a different grid page. Every character
-- still appears exactly once as the independent ranking is paged.
chars = {}
for i, key in ipairs({'a','b','c','d','e','f','g'}) do chars[key] = character('Alt' .. i, 4) end
chars.g = character('BestAlt', 7)
plan, status = render(chars, 1)
before(plan, 'BestAlt', 'Alt1')
assert(not status:find('BestAlt', 1, true), 'grid still uses its original first page')
local second = render(chars, 2)
assert(not second:find('BestAlt', 1, true), 'ranked rows are not pinned or repeated')
for _, c in pairs(chars) do
    local _, count = (plan .. second):gsub(c.name, '')
    assert(count == 1, c.name .. ' appears once across ranking pages')
end
WoWWeekly.db.profileOptions.trackedChars = { g = false }
plan = render(chars)
assert(not plan:find('BestAlt', 1, true), 'untracked alts stay out of ranking')

-- Bonus-only targets also compare elapsed effort, not raw activity counts.
local bonus = character('Bonus', 2)
bonus.trackers.mythicplus = { rawProgress = 0 }
local _, action = WoWWeeklyConfig:GetCombinedVaultProgress(bonus)
assert(action.id == C.TRACKER_DELVES, 'two World activities beat one dungeon with group setup')
-- Gear relevance gates the world boss before the short time estimate can win.
dofile('Trackers/CoiledIsleWeeklies.lua')
for _, ilvl in ipairs({278, 279, 279.1, 280, 300, 0}) do
    local c = character('WorldBossCheck', 8, ilvl, 'balanced')
    c.trackers[C.TRACKER_COILEDISLE_WORLDBOSS] = { done = false }
    plan, status = render({a = c})
    local recommended = plan:find('Defeat the Coiled Isle World Boss', 1, true) ~= nil
    assert(recommended == (ilvl > 0 and ilvl <= 279), 'world boss gear cutoff: ' .. ilvl)
    assert(status:find('World Boss', 1, true), 'world boss status stays visible')
end
local mixed = character('MixedGoals', 3, 300)
mixed.gamePlanGoal = { activities = { balanced = true, delves = true }, vaultSlots = 3 }
plan = render({a = mixed})
assert(not plan:find('Defeat the Coiled Isle World Boss', 1, true), 'Delves goal cannot bypass world boss gear gate')
local completed = character('BossDone', 3, 279, 'balanced')
completed.trackers[C.TRACKER_COILEDISLE_WORLDBOSS] = { done = true }
plan = render({a = completed})
assert(not plan:find('Defeat the Coiled Isle World Boss', 1, true), 'completed boss is not recommended')
dofile('Trackers/RaidProgress.lua')
for _, ilvl in ipairs({279, 279.1, 280, 300, 0}) do
    local c = character('LFRCheck', 8, ilvl, 'raid')
    c.trackers.raid = { hasKills = true, count = 0, rawProgress = 1, highestDifficulty = 'Raid Finder',
        slots = {{level = 17, unlocked = false}} }
    c.trackers.raidprogress_lfr = {progress = 1}
    plan, status = render({a = c})
    assert((plan:find('Raid Finder: kill', 1, true) ~= nil) == (ilvl > 0 and ilvl <= 279), 'LFR cutoff: ' .. ilvl)
    assert(status:find('Raid Finder', 1, true), 'LFR status remains visible')
    if ilvl > 279 then
        local _, nextBonus = WoWWeeklyConfig:GetCombinedVaultProgress(c)
        assert(not nextBonus or nextBonus.id ~= C.TRACKER_RAID, 'bonus goal does not reintroduce LFR')
    end
    c.trackers.raid.highestDifficulty = 'Normal'
    plan = render({a = c})
    assert(plan:find('Normal: kill', 1, true), 'Normal remains eligible at ' .. ilvl)
end
local legacy = character('LegacyLFR', 8, 300, 'raid')
legacy.trackers.raid = { rawProgress = 1, slots = {{level = 17}} }
assert(not WoWWeeklyRaidTracker:IsRecommendationRelevant(legacy), 'legacy LFR snapshot also excluded')
legacy.trackers.raid.slots[2] = {level = 14}
assert(WoWWeeklyRaidTracker:IsRecommendationRelevant(legacy), 'mixed difficulties retain Normal eligibility')
print('Play Next ranking, urgency, uncertainty, goals, pagination, world boss and LFR eligibility tests passed')
