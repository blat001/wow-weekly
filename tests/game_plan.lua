-- Run from the repository root with Lua 5.1 or later.
unpack = unpack or table.unpack
time = function() return 1800000000 end
Enum = { WeeklyRewardChestThresholdType = { World = 1, Activities = 2, Raid = 3 } }
dofile('Constants.lua')
local C = WoWWeeklyConstants
WoWWeekly = { db = { chars = {}, profileOptions = {} } }
local trackers = {}
WoWWeeklyTrackerRegistry = {
    Register = function(_, t) trackers[t.id] = t end,
    GetAll = function() return trackers end,
    GetTracker = function(_, id) return trackers[id] end,
}
for _, file in ipairs({'Delves', 'MythicPlus', 'Raid', 'MetaQuest'}) do
    dofile('Trackers/' .. file .. '.lua')
end
local function check(value, message) assert(value, message) end
local function rows(thresholds, progress, level)
    local result = {}
    for _, threshold in ipairs(thresholds) do
        result[#result + 1] = { threshold = threshold, progress = progress, level = level }
    end
    return result
end
local c = { trackers = {}, resetPeriodId = 1, playedSeason = C.MIDNIGHT_SEASON_KEY }
local activities = rows({2,4,8}, 3, 8)
C_WeeklyRewards = {
    GetActivities = function() return activities end,
    GetSortedProgressForActivity = function() return {{difficulty = 8, numPoints = 3}} end,
}
local delve, dungeon, raid = trackers.delves, trackers.mythicplus, trackers.raid
delve:Scan(c)
check(delve:GetAction(c):find('1 more Tier 8', 1, true), 'three delves leaves one run')
check(not delve:IsGoalMet(c), 'three runs below target')
c.trackers.delves.count = 4
check(delve:IsGoalMet(c) and not delve:IsComplete(c), 'four is enough but not complete')
c.trackers.delves.count = 8
check(delve:IsComplete(c), 'eight completes all slots')
activities = rows({1,4,8}, 3, 10)
C_MythicPlus = { GetRunHistory = function() return {{level=10},{level=10},{level=10}} end }
dungeon:Scan(c)
check(c.trackers.mythicplus.count == 1, 'locked slots do not count')
check(dungeon:GetAction(c):find('1 more +10', 1, true), 'three dungeons leaves one run')
C_MythicPlus.GetRunHistory = function() return {} end
dungeon:Scan(c)
check(c.trackers.mythicplus.qualifiedRuns == 3, 'empty history preserves known run count')
activities = rows({1,4,8}, 4, 10)
dungeon:Scan(c)
check(dungeon:IsGoalMet(c) and not dungeon:IsComplete(c), 'dungeon target distinct from full vault')
activities = rows({1,4,8}, 3, 10)
dungeon:Scan(c)
activities = rows({2,4,6}, 4, 14)
raid:Scan(c)
for _, failure in ipairs({'empty','error','missing'}) do
    C_WeeklyRewards.GetActivities = failure == 'empty' and function() return {} end
        or failure == 'error' and function() error('loading') end or nil
    dungeon:Scan(c); raid:Scan(c); delve:Scan(c)
    check(c.trackers.mythicplus.rawProgress == 3, 'dungeon snapshot preserved: '..failure)
    check(c.trackers.raid.rawProgress == 4, 'raid snapshot preserved: '..failure)
    check(c.trackers.delves.rawProgress == 3, 'delve snapshot preserved: '..failure)
end
check(not trackers.metaquest:IsRelevant({trackers={metaquest={none=true}}}), 'absent meta is ineligible')

-- Render the real recommendation path with a minimal tooltip adapter.
local cells = {}
local tip = setmetatable({ lines = {}, AddLine = function() return 1 end, AddHeader = function() return 1 end,
    SetCell = function(_, _, _, value) cells[#cells+1] = value end },
    {__index = function() return function() end end})
LibStub = function() return {Acquire=function() return tip end, Release=function() end} end
WoWWeeklyDatabase = {charKey='test'}
WoWWeeklyWeeklyReset = {IsWeekStale=function() return false end}
WoWWeeklyConfig = {IsRaidPlanShown=function() return false end,
    IsRecommendationEnabled=function(_, id) return id ~= 'disabled' end}
dofile('UI/Tooltip.lua')
local function render(list, state)
    trackers = list
    state.name = 'Test'; state.playedSeason = C.MIDNIGHT_SEASON_KEY
    WoWWeekly.db.chars = {test=state}; cells = {}
    WoWWeeklyTooltip:Show(nil, true)
    return table.concat(cells, '\n')
end
check(not render({raid=raid}, {trackers={raid={hasKills=true}}}):find('Continue ',1,true), 'raid stays out of next step')
check(render({delves=delve}, c):find('Eligible activities complete',1,true), 'full completion label')
c.trackers.delves.count = 4
check(render({delves=delve}, c):find('Weekly targets met',1,true), 'enough label')
check(render({metaquest=WoWWeeklyMetaQuestTracker}, {trackers={}}):find('No eligible recommendations',1,true), 'no candidates is not complete')
local disabled = {id='disabled', label='Disabled', countsForRecommend=true,
    IsComplete=function() return false end, GetSummary=function() return '-' end}
check(render({disabled=disabled}, {trackers={}}):find('No eligible recommendations',1,true), 'disabled tasks are not complete')
c.trackers.delves.count = 2
c.trackers.mythicplus.slots = {{unlocked=true,track='M'}}
check(render({delves=delve}, c):find('1 more Tier 8',1,true), 'myth slot does not suppress delves')
C_WeeklyRewards.GetActivities = function() return rows({2,4,8}, 7, 5) end
C_WeeklyRewards.GetSortedProgressForActivity = function()
    return {{difficulty=11,numPoints=1},{difficulty=8,numPoints=2},{difficulty=5,numPoints=4}}
end
delve:Scan(c)
check(c.trackers.delves.qualifiedRuns == 3, 'low tiers do not count toward Hero goal')
check(delve:GetAction(c):find('1 more Tier 8',1,true), 'mixed tiers use qualified run count')
dofile('UI/Config.lua')
local Config = WoWWeeklyConfig
local main = {trackers={mythicplus={count=4,qualifiedRuns=4}}}
local alt = {trackers={delves={count=2,qualifiedRuns=2}}}
WoWWeekly.db.chars = {main=main,alt=alt}
check(Config:GetCharacterGoal(main) == 'balanced', 'existing characters default to balanced')
Config:SetCharacterGoal('main','mplus')
Config:SetCharacterVaultSlots('main',3)
Config:SetCharacterGoal('alt','delves')
Config:SetCharacterVaultSlots('alt',1)
check(not dungeon:IsGoalMet(main), 'three slot goal continues after four runs')
check(delve:IsGoalMet(alt), 'one slot goal stops after two delves')
check(Config:GetCharacterGoal(main) == 'mplus', 'separate character focus')
check(not Config:GoalAllowsTracker(main,C.TRACKER_BOUNTYMAP), 'mplus focus excludes maps')
check(Config:GoalAllowsTracker(alt,C.TRACKER_BOUNTYMAP), 'delve focus includes maps')
Config:SetCharacterGoal('main','invalid')
Config:SetCharacterVaultSlots('main',99)
check(Config:GetCharacterGoal(main) == 'mplus' and Config:GetCharacterVaultSlots(main) == 3, 'invalid settings rejected')
local fresh = {gamePlanGoal={focus='mplus'},trackers={}}
check(render({mythicplus=dungeon,delves=delve},fresh):find('Complete +10',1,true), 'explicit mplus goal starts without history')
check(render({mythicplus=dungeon},main):find('4 more +10',1,true), 'full goal recommends third slot')
check(render({delves=delve},alt):find('Weekly targets met',1,true), 'one slot enough label')
local raider = {gamePlanGoal={focus='raid',vaultSlots=1},trackers={raid={count=2}}}
check(render({raid=raid,delves=delve},raider):find('Weekly targets met',1,true), 'raid target respected')
raider.trackers.raid.count = 0
check(render({raid=raid},raider):find('kill 2 more bosses',1,true), 'explicit raid goal starts without history')
dofile('Trackers/WeeklyProfession.lua')
local crafter = {gamePlanGoal={focus='professions'},trackers={profession1={hasProf=true,skillLevel=25,weeklyDone=false}}}
check(WoWWeeklyProfession1Tracker:IsRelevant(crafter), 'explicit profession goal bypasses history')
check(render({profession1=WoWWeeklyProfession1Tracker,delves=delve},crafter):find('weekly quest',1,true), 'profession goal recommends knowledge')
WoWWeekly.db.global = {}
WoWWeekly.db.chars = {main=main,alt=alt}
WoWWeekly.Print = function() end
C_DateAndTime = {GetSecondsUntilWeeklyReset=function() return 1000 end}
dofile('WeeklyReset.lua')
WoWWeeklyWeeklyReset:CheckAndApplyWeeklyReset()
check(Config:GetCharacterGoal(main) == 'mplus' and Config:GetCharacterVaultSlots(alt) == 1, 'goals survive weekly reset')
local mixed = {gamePlanGoal={focus='bonusroll'},trackers={
    delves={rawProgress=4,slots={{unlocked=true,track='V'},{unlocked=true,track='V'},{unlocked=false}}},
    mythicplus={rawProgress=1,slots={{unlocked=true,track='C'},{unlocked=false},{unlocked=false}}},
}}
check(Config:GetCombinedVaultProgress(mixed) == 3, 'mixed low quality slots count toward bonus roll')
check(render({delves=delve,mythicplus=dungeon,raid=raid},mixed):find('bonus-roll option unlocked',1,true), 'mixed rows meet bonus roll goal')
mixed.trackers.mythicplus = {}
local total, action = Config:GetCombinedVaultProgress(mixed)
check(total == 2 and action.id == C.TRACKER_MYTHICPLUS and action.remaining == 1, 'suggest first dungeon slot over four more world runs')
check(render({delves=delve,mythicplus=dungeon},mixed):find('2/3 filled across all rows',1,true), 'two is not enough')
mixed.trackers = {delves={rawProgress=2},mythicplus={rawProgress=1},raid={rawProgress=2}}
check(Config:GetCombinedVaultProgress(mixed) == 3, 'one slot from each row')
mixed.trackers = {raid={rawProgress=6}}
check(Config:GetCombinedVaultProgress(mixed) == 3, 'single full row also meets goal')
WoWWeekly.db.profileOptions.raidPlanEnabled = false
check(Config:GetCombinedVaultProgress(mixed) == 3, 'hidden raid row still contributes earned slots')
WoWWeekly.db.profileOptions.raidPlanEnabled = true
check(Config:GetCharacterGoal(mixed) == 'none' and Config:IsCharacterBonusRollEnabled(mixed), 'old bonus-only goal migrates without adding activities')
local combo = {gamePlanGoal={focus='mplus',vaultSlots=3},trackers={
    mythicplus={count=4,qualifiedRuns=4,rawProgress=4},delves={count=2,qualifiedRuns=2,rawProgress=2},
    raid={count=0},profession1={hasProf=true,skillLevel=25,weeklyDone=false},
}}
WoWWeekly.db.chars = {combo=combo}
Config:SetCharacterActivityGoal('combo','raid',true)
Config:SetCharacterActivityGoal('combo','professions',true)
Config:SetCharacterBonusRoll('combo',true)
check(Config:HasCharacterGoal(combo,'mplus') and Config:HasCharacterGoal(combo,'raid'), 'multiple goals persist together')
check(WoWWeeklyProfession1Tracker:IsRelevant(combo), 'profession history override works with multiple goals')
local comboText = render({mythicplus=dungeon,raid=raid},combo)
check(comboText:find('4 more +10',1,true), 'unfinished dungeon goal survives raid and bonus goals')
check(comboText:find('bonus-roll option unlocked',1,true), 'bonus completed independently')
WoWWeekly.db.chars = {combo=combo}
Config:SetCharacterActivityGoal('combo','mplus',false)
check(Config:HasCharacterGoal(combo,'raid') and Config:IsCharacterBonusRollEnabled(combo), 'unticking one preserves other goals')
Config:SetCharacterBonusRoll('combo',false)
check(not Config:IsCharacterBonusRollEnabled(combo) and Config:HasCharacterGoal(combo,'raid'), 'bonus toggle independent')
comboText = render({raid=raid},combo)
check(comboText:find('kill 2 more bosses',1,true) and not comboText:find('bonus-roll option',1,true), 'disabled bonus produces no guidance')
print('Game Plan, multiple-goal, migration, and independent bonus-roll checks passed')
