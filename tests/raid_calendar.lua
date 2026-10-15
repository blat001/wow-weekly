-- Regression coverage for restricted calendar data; run from the repository root.
time = function() return 1800000000 end
Enum = { CalendarEventType = { Raid = 0 }, WeeklyRewardChestThresholdType = { Raid = 3 } }
dofile('Constants.lua')
dofile('Trackers/Raid.lua')
local tracker = WoWWeeklyRaidTracker
local secret = setmetatable({}, {
    __index = function() error('read secret table') end,
    __lt = function() error('compared secret value') end,
})
issecretvalue = function(value) return rawequal(value, secret) end
local function date(day)
    return { year=2026, month=10, monthDay=day, weekday=4, hour=19, minute=25 }
end
local function event(day, status)
    return { eventType=0, calendarType='PLAYER', title='Raid',
        inviteStatus=status, startTime=date(day) }
end
local events = {}
local countOverride, failCount, failEvent
C_Calendar = {
    GetNumDayEvents = function(_, day)
        if failCount then error('unavailable') end
        if countOverride then return countOverride end
        return day == 14 and #events or 0
    end,
    GetDayEvent = function(_, _, index)
        if failEvent then error('unavailable') end
        return events[index]
    end,
}
C_DateAndTime = {
    GetCurrentCalendarTime = function() return date(14) end,
    GetSecondsUntilWeeklyReset = function() return 6 * 86400 end,
    AdjustTimeByMinutes = function() return date(20) end,
    AdjustTimeByDays = function(_, days) return date(14 + days) end,
    CompareCalendarTime = function(a, b) return a.monthDay - b.monthDay end,
}
local st = {}
events = {event(15, 0), event(18, 1), event(16, 3), event(20, 1), event(13, 1)}
tracker:ScanCalendar(st)
assert(st.calendar.state == 'scheduled' and st.calendar.startTime.monthDay == 16)
assert(st.calendar.timeText == 'Wed 7:25 PM')
local cached = st.calendar
local function restricted()
    tracker:ScanCalendar(st)
    assert(st.calendar == cached, 'incomplete scan must preserve cached schedule')
    local fresh = {}
    tracker:ScanCalendar(fresh)
    assert(fresh.calendar == nil, 'restricted data must not be cached as no events')
end
for _, field in ipairs({'eventType', 'calendarType', 'inviteStatus', 'title', 'startTime'}) do
    events = {event(15, 1)}
    events[1][field] = secret
    restricted()
end
for _, field in ipairs({'year', 'month', 'monthDay', 'weekday', 'hour', 'minute'}) do
    events = {event(15, 1)}
    events[1].startTime[field] = secret
    restricted()
end
events = {secret}
restricted()
events = {event(15, 1), secret} -- Do not commit partial results either.
restricted()
countOverride = secret
restricted()
countOverride = nil
failCount = true
restricted()
failCount, failEvent = false, true
restricted()
failEvent = false

-- Calendar restrictions must not prevent committing refreshed Vault progress.
C_WeeklyRewards = { GetActivities = function()
    return {{type=3, index=1, progress=2, threshold=2, level=14}}
end }
events = {secret}
local char = { trackers = {raid = st} }
tracker:Scan(char)
assert(char.trackers.raid.count == 2 and char.trackers.raid.slots[1].unlocked)
assert(st.calendar == cached)

-- Once readable again, update normally, including pending and empty calendars.
events = {event(15, 0)}
tracker:ScanCalendar(st)
assert(st.calendar.state == 'pending')
events = {}
tracker:ScanCalendar(st)
assert(st.calendar.state == 'none' and st.calendar.startTime == nil)
issecretvalue = nil -- Compatibility when the secret-value API is absent.
events = {event(15, 1)}
tracker:ScanCalendar(st)
assert(st.calendar.state == 'scheduled')
print('Raid calendar checks passed')
