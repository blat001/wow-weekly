local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local function RewardIlvl(activity)
	local getRewards = C_WeeklyRewards and C_WeeklyRewards.GetActivityRewards
	if not (getRewards and activity.type and activity.index) then return nil end
	local ok, rewards = pcall(getRewards, activity.type, activity.index)
	if not ok or type(rewards) ~= "table" then return nil end
	local best = 0
	for _, reward in ipairs(rewards) do
		best = math.max(best, tonumber(reward.itemLevel) or 0)
	end
	return best > 0 and best or nil
end

local function TrackForIlvl(ilvl)
	if ilvl >= 318 then return "M" end
	if ilvl >= 305 then return "H" end
	if ilvl >= 292 then return "C" end
	if ilvl >= 279 then return "V" end
	return "A"
end

local function TrackForLevel(level)
	-- Raid difficulty IDs: 17=LFR, 14=Normal, 15=Heroic, 16=Mythic.
	if level == 15 or level == 16 then return "M" end
	if level == 14 then return "H" end
	if level == 17 then return "C" end
	if level >= 4 then return "M" end
	if level >= 2 then return "H" end
	return "C"
end

local function TrackColor(track)
	if track == "A" then return "|cFF0070DD" end
	return Constants.COLOR_PURPLE
end

local TRACK_NAMES = { A = "Adventurer", V = "Veteran", C = "Champion", H = "Hero", M = "Myth" }

local function RaidDifficultyRank(level)
	if level == 16 then return 4 end -- Mythic
	if level == 15 then return 3 end -- Heroic
	if level == 14 then return 2 end -- Normal
	if level == 17 then return 1 end -- Raid Finder
	return level or 0
end

local function RaidDifficultyName(level)
	if level == 16 or level == 4 then return "Mythic" end
	if level == 15 or level == 3 then return "Heroic" end
	if level == 14 or level == 2 then return "Normal" end
	if level == 17 or level == 1 then return "Raid Finder" end
	return nil
end

local T = {
	id = Constants.TRACKER_RAID,
	label = "Raid",
	icon = 525134,
	category = "weekly",
	group = "vault",
	order = 1,
	cadence = "weekly",
	events = { "PLAYER_LOGIN", "ENCOUNTER_END", "BOSS_KILL", "UPDATE_INSTANCE_INFO" },
	enabledByDefault = true,
	countsForRecommend = true,
}

local ACCEPTED_CALENDAR_STATUS = {
	[1] = true, -- Available / accepted
	[3] = true, -- Confirmed
	[6] = true, -- Signed up
}

local PENDING_CALENDAR_STATUS = {
	[0] = true, -- Invited
	[5] = true, -- Standby
	[8] = true, -- Tentative
}

local function IsSecret(value)
	return issecretvalue and issecretvalue(value)
end

local CALENDAR_TIME_FIELDS = { "year", "month", "monthDay", "weekday", "hour", "minute" }

local function IsReadableCalendarTime(value)
	if IsSecret(value) or type(value) ~= "table" then return false end
	for _, field in ipairs(CALENDAR_TIME_FIELDS) do
		if IsSecret(value[field]) or type(value[field]) ~= "number" then return false end
	end
	return true
end

local function IsReadableCalendarEvent(event)
	if IsSecret(event) or type(event) ~= "table" then return false end
	-- Calendar fields can be secret even when GetDayEvent itself succeeds.
	-- Check before comparisons, status lookups, formatting, or caching the event.
	return not IsSecret(event.eventType) and not IsSecret(event.calendarType)
		and not IsSecret(event.inviteStatus) and not IsSecret(event.title)
		and IsReadableCalendarTime(event.startTime)
end

local function IsBefore(a, b)
	return C_DateAndTime.CompareCalendarTime(a, b) < 0
end

local function FormatEventTime(startTime)
	local weekday = CALENDAR_WEEKDAY_NAMES and CALENDAR_WEEKDAY_NAMES[startTime.weekday]
		or ({ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" })[startTime.weekday]
	weekday = weekday and weekday:sub(1, 3) or "Raid"
	local hour = startTime.hour or 0
	local suffix = hour >= 12 and "PM" or "AM"
	local displayHour = hour % 12
	if displayHour == 0 then displayHour = 12 end
	return string.format("%s %d:%02d %s", weekday, displayHour, startTime.minute or 0, suffix)
end

function T:ScanCalendar(st)
	if not (C_Calendar and C_Calendar.GetNumDayEvents and C_Calendar.GetDayEvent
		and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
		and C_DateAndTime.AdjustTimeByDays and C_DateAndTime.CompareCalendarTime
		and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.AdjustTimeByMinutes) then
		return
	end

	-- OpenCalendar requests the character's event list without displaying the UI.
	-- CALENDAR_UPDATE_EVENT_LIST will trigger another scan once it is populated.
	if C_Calendar.OpenCalendar and not self.calendarOpened then
		self.calendarOpened = true
		pcall(C_Calendar.OpenCalendar)
	end
	local now = C_DateAndTime.GetCurrentCalendarTime()
	local secondsToReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
	if not IsReadableCalendarTime(now) or IsSecret(secondsToReset)
		or type(secondsToReset) ~= "number" then return end
	local resetTime = C_DateAndTime.AdjustTimeByMinutes(now, math.floor(secondsToReset / 60))
	if not IsReadableCalendarTime(resetTime) then return end
	local scanDays = math.min(8, math.ceil(secondsToReset / 86400))
	local accepted, pending

	for dayOffset = 0, scanDays do
		local day = C_DateAndTime.AdjustTimeByDays(now, dayOffset)
		if not IsReadableCalendarTime(day) then return end
		local monthOffset = (day.year - now.year) * 12 + day.month - now.month
		local countOK, count = pcall(C_Calendar.GetNumDayEvents, monthOffset, day.monthDay)
		-- An incomplete/restricted scan must not overwrite the last known schedule.
		if not countOK or IsSecret(count) or type(count) ~= "number" then return end
		for eventIndex = 1, count do
			local eventOK, event = pcall(C_Calendar.GetDayEvent, monthOffset, day.monthDay, eventIndex)
			if not eventOK or not IsReadableCalendarEvent(event) then return end
			local isRaid = event and event.eventType == Enum.CalendarEventType.Raid
			local usableType = event and event.calendarType ~= "SYSTEM"
				and event.calendarType ~= "HOLIDAY" and event.calendarType ~= "RAID_LOCKOUT"
			if isRaid and usableType and event.startTime
				and not IsBefore(event.startTime, now) and IsBefore(event.startTime, resetTime) then
				local candidate = {
					title = event.title,
					startTime = event.startTime,
					inviteStatus = event.inviteStatus,
				}
				if ACCEPTED_CALENDAR_STATUS[event.inviteStatus] then
					if not accepted or IsBefore(candidate.startTime, accepted.startTime) then accepted = candidate end
				elseif PENDING_CALENDAR_STATUS[event.inviteStatus] then
					if not pending or IsBefore(candidate.startTime, pending.startTime) then pending = candidate end
				end
			end
		end
	end

	local event = accepted or pending
	st.calendar = {
		scannedAt = time(),
		state = accepted and "scheduled" or (pending and "pending" or "none"),
		title = event and event.title,
		startTime = event and event.startTime,
		timeText = event and FormatEventTime(event.startTime),
	}
end

function T:Scan(charState)
	local st = charState.trackers[self.id] or {}

	-- Great Vault raid track: 3 slots unlock at 2 / 4 / 6 boss kills.
	-- `progress` = bosses killed this week, `threshold` = bosses needed for that slot.
	-- Report the highest slot threshold (2/4/6) whose run requirement is met.
	local count = 0
	local rawProgress = 0
	local hasKills = false
	local highestLevel = 0
	local highestDifficulty
	local slots = {}
	local ok, activities = pcall(function() return C_WeeklyRewards.GetActivities(
	                             Enum.WeeklyRewardChestThresholdType.Raid) end)
	if not ok or type(activities) ~= "table" or #activities == 0 then
		self:ScanCalendar(st)
		charState.trackers[self.id] = st
		return
	end
	if ok and activities then
		for _, a in ipairs(activities) do
			if (a.progress or 0) > 0 then hasKills = true end
			if (a.progress or 0) > rawProgress then rawProgress = a.progress end
			local difficultyRank = RaidDifficultyRank(a.level)
			if (a.progress or 0) > 0 and difficultyRank > highestLevel then
				highestLevel = difficultyRank
				highestDifficulty = RaidDifficultyName(a.level)
			end
			if (a.progress or 0) >= (a.threshold or 0) and (a.threshold or 0) > count then
				count = a.threshold
			end
			slots[#slots + 1] = {
				threshold = a.threshold or 0,
				unlocked = (a.progress or 0) >= (a.threshold or 0),
				ilvl = RewardIlvl(a),
				level = a.level or 0,
			}
		end
		st.rewardIlvl = Constants.MaxRewardIlvl(activities)
	end
	table.sort(slots, function(a, b) return a.threshold < b.threshold end)
	for _, slot in ipairs(slots) do
		slot.track = slot.ilvl and TrackForIlvl(slot.ilvl) or TrackForLevel(slot.level)
	end

	st.count = count
	st.rawProgress = rawProgress
	st.hasKills = hasKills
	st.highestDifficulty = highestDifficulty
	st.slots = slots
	st.lastUpdated = time()
	self:ScanCalendar(st)
	charState.trackers[self.id] = st
	if hasKills then Constants.RecordActivity(charState, "raid", highestLevel) end
end

function T:GetSummary(charState)
	local st = charState.trackers[self.id] or {}
	local parts = {}
	for i = 1, 3 do
		local slot = st.slots and st.slots[i]
		if slot and slot.unlocked then
			local track = slot.track or "?"
			parts[i] = TrackColor(track) .. "[" .. (TRACK_NAMES[track] or "?") .. "]" .. Constants.COLOR_RESET
		else
			parts[i] = Constants.COLOR_GRAY .. "-" .. Constants.COLOR_RESET
		end
	end
	return table.concat(parts, " ")
end

function T:StopIlvl(charState)
	return Constants.VAULT_STOP_RAID  -- never auto-skip (best gear in the game)
end

function T:IsComplete(charState)
	local st = charState.trackers[self.id] or {}
	return (st.count or 0) >= Constants.RAID_FULL_THRESHOLD
end

-- Only recommend raid to characters who actually raided this week.
function T:IsRelevant(charState)
	local st = charState.trackers[self.id] or {}
	return st.hasKills == true
end

-- Keep earned slots visible, but do not suggest continuing LFR once its gear
-- is outside the user's desired gearing range. Normal and higher stay eligible.
function T:IsRecommendationRelevant(charState)
	local st = charState.trackers[self.id] or {}
	local difficulty = st.highestDifficulty
	if not difficulty then
		local bestRank = 0
		for _, slot in ipairs(st.slots or {}) do
			local rank = RaidDifficultyRank(slot.level)
			if rank > bestRank then
				bestRank = rank
				difficulty = RaidDifficultyName(slot.level)
			end
		end
	end
	if difficulty ~= "Raid Finder" then return true end
	local ilvl = tonumber(charState.ilvl) or 0
	return ilvl > 0 and ilvl <= 279
end

function T:GetAction(charState)
	local st = charState.trackers[self.id] or {}
	local progress = st.rawProgress or st.count or 0
	local nextThreshold
	for _, threshold in ipairs({ 2, 4, 6 }) do
		if progress < threshold then nextThreshold = threshold break end
	end
	if not nextThreshold then return "Raid Great Vault complete" end
	local remaining = nextThreshold - progress
	local noun = remaining == 1 and "boss" or "bosses"
	local difficulty = st.highestDifficulty
	if not difficulty then
		local bestRank = 0
		for _, slot in ipairs(st.slots or {}) do
			local rank = RaidDifficultyRank(slot.level)
			if rank > bestRank then
				bestRank = rank
				difficulty = RaidDifficultyName(slot.level)
			end
		end
	end
	return string.format("Continue %s on %s and kill %d more %s",
		Constants.CURRENT_RAID_NAME, difficulty or "your current difficulty", remaining, noun)
end

function T:GetRaidGoal(charState)
	local st = charState.trackers[self.id] or {}
	local progress = st.rawProgress or st.count or 0
	local nextThreshold
	for _, threshold in ipairs({ 2, 4, 6 }) do
		if progress < threshold then nextThreshold = threshold break end
	end
	if not nextThreshold then return "Raid Great Vault complete" end

	local remaining = nextThreshold - progress
	local noun = remaining == 1 and "boss" or "bosses"
	local difficulty = st.highestDifficulty or "Normal"
	local goal = string.format("%s: kill %d more %s", difficulty, remaining, noun)
	local calendar = st.calendar
	if calendar and calendar.startTime and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
		and C_DateAndTime.CompareCalendarTime(calendar.startTime,
			C_DateAndTime.GetCurrentCalendarTime()) < 0 then
		return goal .. "; log in to refresh calendar"
	end
	if calendar and calendar.state == "scheduled" then
		return string.format("Raid scheduled %s; %s", calendar.timeText or "this week", goal)
	elseif calendar and calendar.state == "pending" then
		return string.format("Raid invite pending (%s); may need to pug %s: kill %d more %s",
			calendar.timeText or "this week", difficulty, remaining, noun)
	elseif calendar and calendar.state == "none" then
		return "Pug " .. goal
	end
	return goal .. "; calendar not scanned on this character"
end

_G[ADDON_NAME .. "RaidTracker"] = T

local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
if TrackerRegistry then
	TrackerRegistry:Register(T)
end
