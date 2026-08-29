local ADDON_NAME = "WoWWeekly"
local Constants = _G[ADDON_NAME .. "Constants"]

local WoWWeekly = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")

function WoWWeekly:OnInitialize()
	self.db = self:GetDatabase()
	self.trackerRegistry = {}
	self:RegisterSlashCommands()

	-- Initialize modules that depend on WoWWeekly.db
	local Database = _G[ADDON_NAME .. "Database"]
	if Database and Database.Initialize then
		Database:Initialize()
	end

	local WeeklyReset = _G[ADDON_NAME .. "WeeklyReset"]
	if WeeklyReset and WeeklyReset.Initialize then
		WeeklyReset:Initialize()
	end

	local Broker = _G[ADDON_NAME .. "Broker"]
	if Broker and Broker.Initialize then
		Broker:Initialize()
	end

	local Config = _G[ADDON_NAME .. "Config"]
	if Config and Config.Initialize then
		Config:Initialize()
	end

	self:Print("v" .. Constants.ADDON_VERSION .. " loaded. Use |cFF00FF00/wweekly|r for options.")
end

function WoWWeekly:OnEnable()
	self:RegisterEvents()
end

function WoWWeekly:OnDisable()
	self:UnregisterAllEvents()
end

function WoWWeekly:GetDatabase()
	if WoWWeeklyDB == nil then
		WoWWeeklyDB = {
			dbVersion = Constants.DB_VERSION,
			chars = {},
			global = {
				currentResetPeriodId = 0,
				nextWeeklyResetAt = 0,
			},
			profileOptions = {
				minimap = { hide = true },
				minimapOptionInitialized = true,
				enabledTrackers = {},
				trackedChars = {},
				sortKey = "name",
			},
		}
	end
	WoWWeeklyDB.profileOptions = WoWWeeklyDB.profileOptions or {}
	-- Older releases stored a minimap placeholder even though no icon was
	-- registered. Treat the first release with a working icon as opt-in.
	if not WoWWeeklyDB.profileOptions.minimapOptionInitialized then
		WoWWeeklyDB.profileOptions.minimap = WoWWeeklyDB.profileOptions.minimap or {}
		WoWWeeklyDB.profileOptions.minimap.hide = true
		WoWWeeklyDB.profileOptions.minimapOptionInitialized = true
	end
	return WoWWeeklyDB
end

function WoWWeekly:RegisterSlashCommands()
	self:RegisterChatCommand("wweekly", "HandleSlashCommand")
	self:RegisterChatCommand("ww", "HandleSlashCommand")
end

function WoWWeekly:HandleSlashCommand(input)
	if input == "dump" then
		self:Print("Database dump:")
		self:DumpDatabase()
	elseif input == "reset" then
		self:Print("Resetting database...")
		WoWWeeklyDB = nil
		self.db = self:GetDatabase()
		self:Print("Database reset.")
	elseif input:sub(1,4) == "find" then
		local term = input:sub(6):lower()
		local out = { "Matches for '" .. term .. "':" }
		local n = C_CurrencyInfo.GetCurrencyListSize()
		for i = 1, n do
			local info = C_CurrencyInfo.GetCurrencyListInfo(i)
			if info and info.name and info.name:lower():find(term, 1, true) then
				local link = C_CurrencyInfo.GetCurrencyListLink(i)
				table.insert(out, string.format("CURRENCY  %s  id=%d  qty=%s", info.name, info.currencyID, tostring(info.quantity)))
			end
		end
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input == "vault" then
		local out = { "=== Great Vault: World/Delve track ===" }
		local ok, activities = pcall(C_WeeklyRewards.GetActivities, Enum.WeeklyRewardChestThresholdType.World)
		if ok and activities then
			for i, a in ipairs(activities) do
				table.insert(out, string.format("--- activity [%d] ---", i))
				-- dump every key/value on the activity table
				local keys = {}
				for k in pairs(a) do keys[#keys+1] = tostring(k) end
				table.sort(keys)
				for _, k in ipairs(keys) do
					table.insert(out, string.format("    %s = %s", k, tostring(a[k])))
				end
				-- try the per-slot reward item level (tells us the tier of the filling run)
				local rok, rewards = pcall(C_WeeklyRewards.GetActivityRewards, a.type, a.index)
				if rok and rewards then
					for ri, r in ipairs(rewards) do
						table.insert(out, string.format("    reward[%d]: itemLevel=%s, type=%s, id=%s",
							ri, tostring(r.itemLevel), tostring(r.type), tostring(r.id)))
					end
				end
				-- try encounter/run info for this slot
				local eok, encInfo = pcall(C_WeeklyRewards.GetActivityEncounterInfo, a.type, a.index)
				if eok and encInfo then
					for ei, e in ipairs(encInfo) do
						local ekeys = {}
						for k in pairs(e) do ekeys[#ekeys+1] = tostring(k) end
						table.sort(ekeys)
						local parts = {}
						for _, k in ipairs(ekeys) do parts[#parts+1] = k .. "=" .. tostring(e[k]) end
						table.insert(out, string.format("    enc[%d]: %s", ei, table.concat(parts, ", ")))
					end
				end
			end
		else
			table.insert(out, "Error calling GetActivities")
		end
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input == "config" then
		local Config = _G[ADDON_NAME .. "Config"]
		if Config then Config:Open() end
	elseif input == "shards" then
		local out = { "=== Coffer Key Shards currency ===" }
		local info = C_CurrencyInfo.GetCurrencyInfo(Constants.CURRENCY_COFFER_KEY_SHARD)
		if info then
			local keys = {}
			for k in pairs(info) do keys[#keys+1] = tostring(k) end
			table.sort(keys)
			for _, k in ipairs(keys) do
				table.insert(out, string.format("    %s = %s", k, tostring(info[k])))
			end
		else
			table.insert(out, "    (no currency info)")
		end
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input == "mplus" then
		local out = { "=== Mythic+ debug ===" }
		-- 1) Show the threshold-type enum so we know the correct M+ name/value
		table.insert(out, "Enum.WeeklyRewardChestThresholdType:")
		if Enum and Enum.WeeklyRewardChestThresholdType then
			local ekeys = {}
			for k in pairs(Enum.WeeklyRewardChestThresholdType) do ekeys[#ekeys + 1] = k end
			table.sort(ekeys)
			for _, k in ipairs(ekeys) do
				table.insert(out, string.format("    %s = %s", k, tostring(Enum.WeeklyRewardChestThresholdType[k])))
			end
		end
		-- 2) Dump ALL activities with their type so we can identify the M+ track
		table.insert(out, "All activities (type / level / progress / threshold):")
		local ok, activities = pcall(C_WeeklyRewards.GetActivities)
		if ok and activities then
			for i, a in ipairs(activities) do
				table.insert(out, string.format("[%d] type=%s, level=%s, progress=%s, threshold=%s",
					i, tostring(a.type), tostring(a.level), tostring(a.progress), tostring(a.threshold)))
			end
		else
			table.insert(out, "    Error calling GetActivities()")
		end
		-- 3) Owned keystone
		table.insert(out, "--- Owned keystone ---")
		local lvl = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
		local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
		local mapName = mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
		table.insert(out, string.format("level=%s, mapID=%s, name=%s", tostring(lvl), tostring(mapID), tostring(mapName)))
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input == "prof" then
		local out = { "=== Your Professions ===" }
		local profIndices = { GetProfessions() }
		local function statusFor(questIDs)
			if not questIDs then return "no-quest-id" end
			for _, qid in ipairs(questIDs) do
				if C_QuestLog.IsQuestFlaggedCompleted(qid) then
					return string.format("DONE (quest %d of %d ids)", qid, #questIDs)
				end
			end
			return string.format("not done (checked %d ids: %s)", #questIDs, table.concat(questIDs, ","))
		end
		for slot = 1, 2 do
			local idx = profIndices[slot]
			if idx then
				local name, _, skill, maxSkill, _, _, skillLine = GetProfessionInfo(idx)
				table.insert(out, string.format("slot %d: %s (skillLine=%s, %d/%d)",
					slot, tostring(name), tostring(skillLine), skill or 0, maxSkill or 0))
				table.insert(out, "    weekly   " .. statusFor(skillLine and Constants.PROFESSION_WEEKLY_QUESTS[skillLine]))
				table.insert(out, "    treatise " .. statusFor(skillLine and Constants.PROFESSION_TREATISE_QUESTS[skillLine]))
			else
				table.insert(out, string.format("slot %d: (empty)", slot))
			end
		end
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input:sub(1, 6) == "quests" then
		-- Dump the quest log (optionally filtered) with IDs + objective progress,
		-- so we can find things like a "Gilded Stash 2/4" weekly activity.
		local term = input:sub(8):lower()
		local out = { "=== Quest log" .. (term ~= "" and (" matching '" .. term .. "'") or "") .. " ===" }
		local num = C_QuestLog.GetNumQuestLogEntries()
		for i = 1, num do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID then
				local title = info.title or "?"
				local objs = {}
				local nobj = C_QuestLog.GetNumQuestObjectives(info.questID)
				for j = 1, nobj do
					local text, _, _, fulfilled, required = GetQuestObjectiveInfo(info.questID, j, false)
					if text and text ~= "" then
						objs[#objs + 1] = string.format("%s (%s/%s)", text, tostring(fulfilled), tostring(required))
					end
				end
				local hay = (title .. " " .. table.concat(objs, " ")):lower()
				if term == "" or hay:find(term, 1, true) then
					table.insert(out, string.format("[%d] %s", info.questID, title))
					for _, o in ipairs(objs) do table.insert(out, "    " .. o) end
				end
			end
		end
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input:sub(1, 5) == "findq" then
		-- Search COMPLETED quests by cached title (finds things like the weekly
		-- "Gilded Stash" activity quest, which has dropped out of the active log).
		local term = input:sub(7):lower()
		local out = { "=== Completed quests matching '" .. term .. "' ===" }
		local ids = (C_QuestLog.GetAllCompletedQuestIDs and C_QuestLog.GetAllCompletedQuestIDs()) or {}
		local matches = 0
		for _, qid in ipairs(ids) do
			local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)
			if title and title ~= "" and title:lower():find(term, 1, true) then
				table.insert(out, string.format("[%d] %s", qid, title))
				matches = matches + 1
			end
		end
		table.insert(out, string.format("(scanned %d completed quests, %d matches; some titles may be uncached)", #ids, matches))
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input:sub(1, 3) == "bag" then
		-- List bag items (optionally filtered by name) with item IDs, e.g. to find
		-- the Bounty Map item id: /ww bag bounty
		local term = input:sub(5):lower()
		local out = { "=== Bag items" .. (term ~= "" and (" matching '" .. term .. "'") or "") .. " ===" }
		for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or 5) do
			local slots = C_Container.GetContainerNumSlots(bag) or 0
			for slot = 1, slots do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID then
					local name = info.hyperlink and info.hyperlink:match("%[(.-)%]") or ("item:" .. info.itemID)
					if term == "" or name:lower():find(term, 1, true) then
						table.insert(out, string.format("[%d] %s x%d", info.itemID, name, info.stackCount or 1))
					end
				end
			end
		end
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input == "stash" then
		local out = { "=== Gilded Stash debug ===" }
		local TR = _G[ADDON_NAME .. "TrackerRegistry"]
		local tr = TR and TR.GetTracker and TR:GetTracker(Constants.TRACKER_GILDEDSTASH)
		table.insert(out, "Tracker registered: " .. tostring(tr ~= nil))
		local Database = _G[ADDON_NAME .. "Database"]
		local cs = Database and Database.GetCharState and Database:GetCharState()
		local st = cs and cs.trackers and cs.trackers[Constants.TRACKER_GILDEDSTASH]
		if st then
			table.insert(out, string.format("Stored: looted=%s max=%s", tostring(st.looted), tostring(st.max)))
		else
			table.insert(out, "Stored: (none)")
		end
		local getter = C_UIWidgetManager and C_UIWidgetManager.GetSpellDisplayVisualizationInfo
		table.insert(out, "Widget getter available: " .. tostring(getter ~= nil))
		local WIDS = { 6659, 6718, 6719, 6720, 6721, 6722, 6723, 6724, 6725, 6726, 6727, 6728, 6729, 6794, 7193, 7591 }
		local anyShown = false
		for _, wid in ipairs(WIDS) do
			local info = getter and getter(wid)
			if info and info.spellInfo then
				anyShown = true
				local tip = info.spellInfo.tooltip
				if tip then tip = tip:gsub("\n", " / ") end
				table.insert(out, string.format("[%d] spellID=%s shown=%s tip=%s",
					wid, tostring(info.spellInfo.spellID), tostring(info.spellInfo.shownState), tostring(tip)))
			end
		end
		if not anyShown then
			table.insert(out, "(no widget returned spell info here - try standing out near the delves)")
		end
		self:ShowDumpWindow(table.concat(out, "\n"))
	elseif input == "gear" then
		local out = { "=== Vault: worth doing? ===" }
		local _, equipped = GetAverageItemLevel()
		local avg = equipped or 0
		table.insert(out, string.format("Average equipped ilvl: %.1f", avg))
		table.insert(out, "")
		local tracks = {
			{ "World (Delves)", Constants.VAULT_STOP_DELVE },
			{ "Dungeon (M+)",   Constants.VAULT_STOP_MPLUS },
			{ "Raid",           Constants.VAULT_STOP_RAID },
		}
		for _, tr in ipairs(tracks) do
			local stop = tr[2]
			local worth
			if not stop or stop <= 0 then
				worth = "worth doing (never skips)"
			elseif avg < stop then
				worth = string.format("worth doing (avg %.0f < %d)", avg, stop)
			else
				worth = string.format("SKIP (avg %.0f >= %d, Mythic gear)", avg, stop)
			end
			table.insert(out, string.format("%-16s %s", tr[1], worth))
		end
		self:ShowDumpWindow(table.concat(out, "\n"))
	else
		self:Print("Commands: /wweekly config, /wweekly dump, /wweekly reset, /wweekly find <term>, /wweekly vault, /wweekly mplus, /wweekly prof, /wweekly shards, /wweekly gear")
	end
end

function WoWWeekly:DumpDatabase()
	-- Build output as a single block of text
	local output = {}
	table.insert(output, "=== WoW Weekly Database Dump ===")
	table.insert(output, "DB version: " .. self.db.dbVersion)

	local charCount = 0
	for _ in pairs(self.db.chars) do charCount = charCount + 1 end
	table.insert(output, "Characters: " .. charCount)

	for charKey, charState in pairs(self.db.chars) do
		table.insert(output, string.format("  %s: %s (level %d, ilvl %d)",
			charKey, charState.class, charState.level, charState.ilvl))
	end

	table.insert(output, "Current Reset Period ID: " .. self.db.global.currentResetPeriodId)
	table.insert(output, "Next Weekly Reset: " .. self.db.global.nextWeeklyResetAt)

	-- Show in a copyable frame
	self:ShowDumpWindow(table.concat(output, "\n"))
end

function WoWWeekly:ShowDumpWindow(text)
	-- Create or reuse a frame for displaying the dump
	local frame = _G["WoWWeeklyDumpFrame"]
	if not frame then
		frame = CreateFrame("Frame", "WoWWeeklyDumpFrame", UIParent, "BackdropTemplate")
		frame:SetSize(600, 400)
		frame:SetPoint("CENTER")
		frame:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})
		frame:SetBackdropColor(0, 0, 0, 0.9)
		frame:SetBackdropBorderColor(1, 1, 1, 0.5)

		-- Make it movable
		frame:SetMovable(true)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
		frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

		-- Title
		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOP", frame, "TOP", 0, -10)
		title:SetText("WoW Weekly Database")
		frame.title = title

		-- Close button
		local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
		closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
		closeBtn:SetScript("OnClick", function() frame:Hide() end)

		-- Edit box (copyable text)
		local editbox = CreateFrame("EditBox", nil, frame)
		editbox:SetSize(580, 360)
		editbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
		editbox:SetFont("Fonts/FRIZQT__.TTF", 11, "")
		editbox:SetMultiLine(true)
		editbox:SetAutoFocus(false)
		editbox:EnableMouse(true)
		editbox:SetScript("OnEscapePressed", function() frame:Hide() end)
		frame.editbox = editbox
	end

	frame.editbox:SetText(text)
	frame.editbox:HighlightText()
	frame:Show()
	self:Print("Database dump displayed in window (use Ctrl+A to select all and Ctrl+C to copy)")
end

function WoWWeekly:RegisterEvents()
	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	self:RegisterEvent("PLAYER_LOGOUT", "OnPlayerLogout")
	self:RegisterEvent("TIME_PLAYED_MSG", "OnTimePlayed")
	self:RegisterEvent("WEEKLY_REWARDS_UPDATE", "OnWeeklyRewardsUpdate")
end

function WoWWeekly:OnWeeklyRewardsUpdate()
	local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
	local Database = _G[ADDON_NAME .. "Database"]
	local charState = Database and Database:GetCharState()
	if not (TrackerRegistry and charState) then return end

	-- Refresh only the trackers backed by C_WeeklyRewards.  The event may fire
	-- several times as Blizzard populates the activity rows.
	for _, trackerId in ipairs({
		Constants.TRACKER_DELVES,
		Constants.TRACKER_MYTHICPLUS,
		Constants.TRACKER_RAID,
	}) do
		local tracker = TrackerRegistry:GetTracker(trackerId)
		if tracker and tracker.Scan then tracker:Scan(charState) end
	end
end

function WoWWeekly:OnPlayerLogin()
	self:Print("Player logged in: " .. UnitName("player"))
	-- Sweep stale weeks before scanning so the fresh scan isn't mixed with
	-- last week's leftovers (GetSecondsUntilWeeklyReset is reliable by now).
	local WeeklyReset = _G[ADDON_NAME .. "WeeklyReset"]
	if WeeklyReset and WeeklyReset.CheckAndApplyWeeklyReset then
		WeeklyReset:CheckAndApplyWeeklyReset()
	end
	local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
	if TrackerRegistry and TrackerRegistry.ScanAll then
		TrackerRegistry:ScanAll()
	end
	local Broker = _G[ADDON_NAME .. "Broker"]
	if Broker and Broker.UpdateText then
		Broker:UpdateText()
	end
	if RequestTimePlayed then RequestTimePlayed() end
end

function WoWWeekly:OnTimePlayed(event, totalTime, levelTime)
	local Database = _G[ADDON_NAME .. "Database"]
	local charState = Database and Database:GetCharState()
	if not charState or not totalTime then return end
	if charState.playedSeason ~= Constants.MIDNIGHT_SEASON_KEY
		or not charState.seasonPlayedBaseline then
		charState.playedSeason = Constants.MIDNIGHT_SEASON_KEY
		charState.seasonPlayedBaseline = totalTime
	end
	charState.totalPlayed = totalTime
	charState.seasonPlayed = math.max(0, totalTime - charState.seasonPlayedBaseline)
end

function WoWWeekly:OnPlayerLogout()
	self:Print("Player logged out")
end

_G[ADDON_NAME] = WoWWeekly
