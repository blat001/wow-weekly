local ADDON_NAME = "WoWWeekly"
local WoWWeekly = _G[ADDON_NAME]
local Constants = _G[ADDON_NAME .. "Constants"]

local Database = {}

function Database:Initialize()
	self.charKey = self:BuildCharKey()
	self:RegisterCharacter()
	-- Equipment information can still be unavailable during addon initialization.
	-- Refresh once the character has entered the world and whenever gear changes.
	WoWWeekly:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:RefreshCurrentCharacter() end)
	WoWWeekly:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() self:RefreshCurrentCharacter() end)
end

function Database:BuildCharKey()
	local name = UnitName("player")
	local realm = GetRealmName()
	return string.format("%s-%s", name, realm)
end

function Database:RegisterCharacter()
	local charKey = self.charKey
	local db = WoWWeekly.db

	if db.chars[charKey] == nil then
		local class, classFile = UnitClass("player")
		local faction = UnitFactionGroup("player")
		local level = UnitLevel("player")
		local ilvl = select(2, GetAverageItemLevel())

		db.chars[charKey] = {
			name = UnitName("player"),
			realm = GetRealmName(),
			class = class,
			classFile = classFile,
			faction = faction,
			level = level,
			ilvl = ilvl,
			minSlotIlvl = Constants.GetMinEquippedIlvl(),
			lastSeen = time(),
			resetPeriodId = 0,
			trackers = {},
			activityProfile = {},
			seasonPlayed = 0,
		}
		WoWWeekly:Print("Registered character: " .. charKey)
	else
		self:RefreshCurrentCharacter()
	end
end

function Database:RefreshCurrentCharacter()
	local charState = WoWWeekly.db.chars[self.charKey]
	if not charState then return end

	charState.lastSeen = time()
	charState.level = UnitLevel("player")

	-- Keep the last valid snapshot if the client has not populated equipment
	-- data yet. GetAverageItemLevel() can briefly return zero while loading.
	local ilvl = select(2, GetAverageItemLevel())
	if ilvl and ilvl > 0 then
		charState.ilvl = ilvl
	end

	local minSlotIlvl = Constants.GetMinEquippedIlvl()
	if minSlotIlvl and minSlotIlvl > 0 then
		charState.minSlotIlvl = minSlotIlvl
	end
end

function Database:GetCharState()
	return WoWWeekly.db.chars[self.charKey]
end

function Database:GetAllCharStates()
	return WoWWeekly.db.chars
end

_G[ADDON_NAME .. "Database"] = Database
