-- Run from the repository root with Lua 5.1 or later.
time = function() return 1800000000 end
Enum = { WeeklyRewardChestThresholdType = { Raid = 3 } }
dofile('Constants.lua')
local C = WoWWeeklyConstants
local addon = { events = {} }
function addon:RegisterEvent(event, handler) self.events[event] = handler end
LibStub = function() return { NewAddon = function() return addon end } end
dofile('Core.lua')
local state = { trackers = {} }
local trackers = {}
WoWWeeklyDatabase = { GetCharState = function() return state end }
WoWWeeklyTrackerRegistry = {
    Register = function(_, tracker) trackers[tracker.id] = tracker end,
    GetTracker = function(_, id) return trackers[id] end,
}
local requests, kills = 0, 4
RequestRaidInfo = function() requests = requests + 1 end
GetNumSavedInstances = function() return 2 end
GetSavedInstanceInfo = function(i)
    if i == 1 then return C.CURRENT_RAID_NAME, 1, 3600, 14, true, false, 1, true, 20, 'Normal', 8, kills end
    return 'Tidebound Grotto', 2, 3600, 2, true, false, 1, true, 5, 'Normal', 1, 1
end
C_WeeklyRewards = { GetActivities = function()
    return {
        { type = 3, index = 1, level = 14, progress = 6, threshold = 2 },
        { type = 3, index = 2, level = 14, progress = 6, threshold = 4 },
        { type = 3, index = 3, level = 14, progress = 6, threshold = 6 },
    }
end }
dofile('Trackers/RaidProgress.lua')
dofile('Trackers/Raid.lua')
addon:RegisterEvents()
local function fire(event) addon[assert(addon.events[event])](addon, event) end
fire('UPDATE_INSTANCE_INFO')
assert(state.trackers.raidprogress_normal.progress == 4)
fire('BOSS_KILL')
assert(requests == 1, 'boss kill requests fresh lockouts')
kills = 5
fire('UPDATE_INSTANCE_INFO')
assert(state.trackers.raidprogress_normal.progress == 5, 'lockout response updates stale raid count')
assert(requests == 1, 'response scan must not request again and loop')
assert(trackers.raidprogress_normal:GetSummary(state):find('5/8', 1, true))
fire('WEEKLY_REWARDS_UPDATE')
assert(state.trackers.raid.rawProgress == 6, 'Vault keeps all qualifying kills')
assert(state.trackers.raid.count == 6)
local _, labels = trackers.raid:GetSummary(state):gsub('%[Hero%]', '')
assert(labels == 3, 'Normal awards three Hero gear slots in Season 2')
fire('PLAYER_ENTERING_WORLD')
assert(requests == 2, 'entering world requests initial lockouts')
print('Raid refresh tests passed')
