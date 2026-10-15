-- Monthly profession reminders, including offline alts and weekly resets.
time = function() return 1800000000 end
dofile('Constants.lua')
local C = WoWWeeklyConstants
local now = {year=2026, month=9, monthDay=12, weekday=7}
C_DateAndTime = {GetCurrentCalendarTime=function() return now end}
local done = {}
C_QuestLog = {IsQuestFlaggedCompleted=function(id) return done[id] == true end}
GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(index)
    return index == 1 and 'Alchemy' or 'Mining', nil, 100, 100, nil, nil,
        index == 1 and 171 or 186
end
WoWWeeklyConfig = {HasCharacterGoal=function() return true end}
dofile('Trackers/WeeklyProfession.lua')
local p1, p2 = WoWWeeklyProfession1Tracker, WoWWeeklyProfession2Tracker
local char = {trackers={}}
done[93690], done[95127] = true, true
p1:Scan(char)
p2:Scan(char)
assert(p1:IsRelevant(char))
assert(not p1:IsComplete(char))
assert(p1:RecTags(char)[1] == 'Darkmoon Faire')
assert(p1:GetAction(char):find('Darkmoon Faire', 1, true))
assert(p1:GetSummary(char):find('Darkmoon Faire-', 1, true))
done[29506] = true
p1:Scan(char)
assert(p1:IsComplete(char))
assert(not p2:IsComplete(char))
assert(#p1:RecTags(char) == 0)
p1:OnWeeklyReset(char)
assert(char.trackers.profession1.darkmoonDone == true)
assert(not p1:GetAction(char):find('Darkmoon Faire', 1, true))
-- Hide after closing even without scanning the offline alt.
now.monthDay, now.weekday = 13, 1
assert(not p2:GetSummary(char):find('Darkmoon Faire', 1, true))
assert(not p2:GetAction(char):find('Darkmoon Faire', 1, true))
-- A new Faire invalidates last month's completion on offline alts.
now.month, now.monthDay, now.weekday = 10, 4, 1
assert(p1:GetAction(char):find('Darkmoon Faire', 1, true))
-- Month beginning on Sunday: open on the 1st, closed on the 8th.
now.month, now.monthDay, now.weekday = 11, 1, 1
assert(p1:GetAction(char):find('Darkmoon Faire', 1, true))
now.monthDay = 8
assert(not p1:GetAction(char):find('Darkmoon Faire', 1, true))
now.month, now.monthDay, now.weekday = 9, 5, 7
assert(not p1:GetAction(char):find('Darkmoon Faire', 1, true))
now.monthDay, now.weekday = 6, 1
assert(p2:GetAction(char):find('Darkmoon Faire', 1, true))
GetProfessions = function() end
p1:Scan(char)
assert(p1:IsComplete(char))
assert(not p1:IsRelevant(char))
C_DateAndTime = nil
assert(not p2:GetAction(char):find('Darkmoon Faire', 1, true))
print('Darkmoon profession checks passed')
