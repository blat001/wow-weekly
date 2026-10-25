-- Run from the repository root with Lua 5.1 or later.
local launch, week = 1791903600, 604800
local now, nextReset = launch + week + 100, launch + 2 * week
time = function() return now end
C_DateAndTime = {GetSecondsUntilWeeklyReset=function() return nextReset - now end}
dofile('Constants.lua')
local addon = {Print=function() end, RegisterEvent=function(self, event, method)
    self.events = self.events or {}; self.events[event] = method
end}
LibStub = function() return {NewAddon=function() return addon end} end
dofile('Core.lua')
addon.db = {global={}, chars={}}
dofile('TrackerRegistry.lua')
dofile('Trackers/SoulFragment.lua')
dofile('WeeklyReset.lua')
local tracker, reset = WoWWeeklySoulFragmentTracker, WoWWeeklyWeeklyReset
local main = {trackers={}, resetPeriodId=reset:GetCurrentResetPeriodId()}
local alt = {trackers={}, resetPeriodId=main.resetPeriodId}
addon.db.chars = {main=main, alt=alt}
WoWWeeklyDatabase = {GetCharState=function() return main end}
local completed = {[98951]=true, [98963]=true}
C_QuestLog = {IsQuestFlaggedCompleted=function(id) return completed[id] == true end}
-- Week two is detected even if both rewards predate installation.
tracker:Scan(main)
assert(tracker:GetStatus(main) == 'done')
assert(tracker:GetSummary(main):find('2/2', 1, true))
completed[98963] = false
tracker:Scan(alt)
assert(tracker:GetStatus(alt) == 'pending', 'week one alone must not complete week two')
assert(tracker:GetSummary(alt):find('1/2', 1, true))
-- Cached completion survives temporarily false API data and module reload.
dofile('Trackers/SoulFragment.lua')
tracker = WoWWeeklySoulFragmentTracker
tracker:Scan(main)
assert(tracker:IsComplete(main))
addon:RegisterEvents()
assert(addon.events.QUEST_TURNED_IN == 'OnSoulFragmentUpdate')
assert(addon.events.QUEST_LOG_UPDATE == 'OnSoulFragmentUpdate')
-- New week changes the selected quest for offline alts without wiping history.
now, nextReset = launch + 2 * week, launch + 3 * week
reset:CheckAndApplyWeeklyReset()
assert(tracker:GetStatus(main) == 'pending' and tracker:GetStatus(alt) == 'pending')
assert(main.trackers.soulfragment.completed[98963])
assert(tracker:GetSummary(main):find('2/3', 1, true))
assert(tracker:GetSummary(alt):find('1/3', 1, true))
-- Catching up on an old quest does not complete the current week's quest.
addon:OnSoulFragmentUpdate('QUEST_TURNED_IN', 98963)
assert(not tracker:IsComplete(main))
addon:OnSoulFragmentUpdate('QUEST_TURNED_IN', 98962)
assert(tracker:IsComplete(main) and not tracker:IsComplete(alt))
assert(tracker:GetSummary(main):find('3/3', 1, true))
-- EU reset is 16 hours after US; Asia is later still. Local reset controls step.
for _, offset in ipairs({0, 16*3600, 33*3600, -3600}) do
    nextReset = launch + 3 * week + offset
    assert(tracker:IsComplete(main))
    nextReset = launch + 4 * week + offset
    assert(not tracker:IsComplete(main))
end
-- Future IDs below are test fixtures, never production quest guesses.
local fifth, sixth = 900001, 900002
C_QuestLine = {GetQuestLineQuests=function(id)
    assert(id == 6385)
    return {98951, 98963, 98962, 98961, fifth, sixth}
end}
completed[98961], completed[fifth], completed[sixth] = true, true, true
tracker:Scan(main)
now, nextReset = launch + 4 * week, launch + 5 * week
assert(tracker:GetStatus(main) == 'done')
now, nextReset = launch + 5 * week, launch + 6 * week
assert(tracker:GetStatus(main) == 'finished')
assert(tracker:GetSummary(main):find('6/6', 1, true))
now, nextReset = launch + 10 * week, launch + 11 * week
assert(tracker:GetStatus(main) == 'finished', 'no endless new chores after all six quests')
-- Missing future data is unknown, never a guessed weekly completion.
C_QuestLine.GetQuestLineQuests = function() return {98951, 98962} end
tracker:Scan(alt)
assert(tracker:GetStatus(alt) == 'unknown')
assert(tracker:GetSummary(alt):find('?/6', 1, true))
tracker:Scan(main)
assert(tracker:GetStatus(main) == 'finished', 'partial API responses preserve full cached chain')
nextReset = launch
assert(tracker:GetStatus(main) == 'unavailable')
C_DateAndTime.GetSecondsUntilWeeklyReset = function() return nil end
assert(tracker:GetStatus(main) == 'unknown')
assert(tracker.group == 'delves')
print('Soul Fragment checks passed')
