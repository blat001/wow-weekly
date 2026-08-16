local ADDON_NAME = "WoWWeekly"
local WoWWeekly = _G[ADDON_NAME]
local Constants = _G[ADDON_NAME .. "Constants"]

local Database = {}

function Database:Initialize()
	self.charKey = self:BuildCharKey()
	self:RegisterCharacter()
	WoWWeekly:RegisterEvent("PLAYER_LOGIN", function() self:OnPlayerLogin() end)
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
		-- Update last seen and level/ilvl
		local charState = db.chars[charKey]
		charState.lastSeen = time()
		charState.level = UnitLevel("player")
		charState.ilvl = select(2, GetAverageItemLevel())
		charState.minSlotIlvl = Constants.GetMinEquippedIlvl()
	end
end

function Database:OnPlayerLogin()
	self:RegisterCharacter()
end

function Database:GetCharState()
	return WoWWeekly.db.chars[self.charKey]
end

function Database:GetAllCharStates()
	return WoWWeekly.db.chars
end

_G[ADDON_NAME .. "Database"] = Database
