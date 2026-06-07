local ADDON_NAME = "WoWWeekly"
local WoWWeekly = _G[ADDON_NAME]

local TrackerRegistry = {}
TrackerRegistry.trackers = {}

function TrackerRegistry:Register(trackerModule)
	if not trackerModule.id then
		error("Tracker must have an id field")
	end
	self.trackers[trackerModule.id] = trackerModule
	WoWWeekly:Print("Registered tracker: " .. trackerModule.label)
end

function TrackerRegistry:GetTracker(trackerId)
	return self.trackers[trackerId]
end

function TrackerRegistry:GetAll()
	return self.trackers
end

function TrackerRegistry:ScanAll()
	local db = WoWWeekly.db
	local Database = _G[ADDON_NAME .. "Database"]
	local charState = Database:GetCharState()

	if not charState then return end

	-- Initialize tracker state for this character if not present
	if charState.trackers == nil then
		charState.trackers = {}
	end

	for trackerId, tracker in pairs(self.trackers) do
		if charState.trackers[trackerId] == nil then
			charState.trackers[trackerId] = {}
		end
		-- Call the tracker's Scan function to update its state
		if tracker.Scan then
			tracker:Scan(charState)
		end
	end
end

function TrackerRegistry:RegisterEvents()
	-- TODO: register tracker events (disabled for now to prevent loops)
end

_G[ADDON_NAME .. "TrackerRegistry"] = TrackerRegistry
