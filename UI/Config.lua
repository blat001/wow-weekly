local ADDON_NAME = "WoWWeekly"
local WoWWeekly  = _G[ADDON_NAME]
local Constants  = _G[ADDON_NAME .. "Constants"]

local Config = {}

local CHARACTER_GOALS = {
	{ key = "balanced", label = "Balanced week",
		description = "A little of everything. Suggests eligible weekly quests, Delves, dungeons and profession tasks using your Game Plan priorities and activity history. Your slot target applies separately to World and Dungeon; Raid keeps its full three-slot target. Other weekly tasks can still be suggested after your Vault targets are met." },
	{ key = "delves", label = "Delves and Hero gear",
		description = "Gear this character through Delves. Suggests Tier 8+ runs for Hero-quality World Vault choices, plus available Bounty Maps and Gilded Stash tasks. Your slot target counts only the World row; map and stash tasks may remain after that target is met." },
	{ key = "mplus", label = "Mythic+ Vault",
		description = "Work toward Myth-quality Dungeon Vault choices with +10 or higher Mythic+ runs. Suggests dungeons even if you have not started this week. Stops when the chosen number of qualifying Dungeon slots is filled. World and Raid slots do not count toward this gear goal." },
	{ key = "raid", label = "Raid Vault",
		description = "Fill the Raid Vault row. Raid Goals uses your recorded difficulty and calendar to suggest boss kills or joining a group; it starts with Normal if no difficulty is known. Stops at your chosen number of Raid slots. This goal counts unlocked slots, without requiring a particular gear quality." },
	{ key = "professions", label = "Profession knowledge",
		description = "Keep this character's profession knowledge moving. Suggests tracked weekly profession quests and treatises for known professions at skill 25 or higher, even without activity history. Stops when those tracked tasks are complete. Does not suggest Vault runs or track every possible knowledge source." },
}

function Config:GetCharacterGoalDescription(charState)
	local descriptions = {}
	for _, choice in ipairs(CHARACTER_GOALS) do
		if self:HasCharacterGoal(charState, choice.key) then descriptions[#descriptions + 1] = choice.description end
	end
	return table.concat(descriptions, "\n\n")
end

function Config:GetCharacterGoal(charState)
	local selected = self:GetCharacterGoals(charState)
	local labels, only = {}, nil
	for _, choice in ipairs(CHARACTER_GOALS) do
		if selected[choice.key] then labels[#labels + 1] = choice.label; only = choice.key end
	end
	if #labels == 0 then return "none", "No activity goals" end
	return #labels == 1 and only or "multiple", table.concat(labels, " + ")
end

function Config:GetCharacterGoals(charState)
	if not charState then return {balanced=true} end
	charState.gamePlanGoal = charState.gamePlanGoal or {}
	local goal = charState.gamePlanGoal
	if not goal.activities then
		goal.activities = {}
		if goal.focus == "bonusroll" then
			goal.bonusRoll = true
		else
			local valid = false
			for _, choice in ipairs(CHARACTER_GOALS) do
				if choice.key == goal.focus then goal.activities[choice.key] = true; valid = true end
			end
			if not valid then goal.activities.balanced = true end
		end
		goal.focus = nil
	end
	return goal.activities
end

function Config:HasCharacterGoal(charState, focus)
	return self:GetCharacterGoals(charState)[focus] == true
end

function Config:SetCharacterActivityGoal(charKey, focus, enabled)
	local c = WoWWeekly.db.chars[charKey]
	if not c then return end
	for _, choice in ipairs(CHARACTER_GOALS) do
		if choice.key == focus then
			self:GetCharacterGoals(c)[focus] = enabled and true or nil
			return
		end
	end
end

function Config:IsCharacterBonusRollEnabled(charState)
	self:GetCharacterGoals(charState)
	return charState and charState.gamePlanGoal.bonusRoll == true
end

function Config:SetCharacterBonusRoll(charKey, enabled)
	local c = WoWWeekly.db.chars[charKey]
	if not c then return end
	self:GetCharacterGoals(c)
	c.gamePlanGoal.bonusRoll = enabled and true or false
end

function Config:SetCharacterGoal(charKey, focus)
	local c = WoWWeekly.db.chars[charKey]
	if not c then return end
	for _, choice in ipairs(CHARACTER_GOALS) do
		if focus == choice.key then
			self:GetCharacterGoals(c)
			c.gamePlanGoal.activities = {[focus] = true}
			return
		end
	end
end

function Config:GetCharacterVaultSlots(charState)
	local goal = charState and charState.gamePlanGoal
	local slots = goal and tonumber(goal.vaultSlots)
	if slots == 1 or slots == 2 or slots == 3 then return slots end
	return self:GetCharacterGoal(charState) == "raid" and 3 or 2
end

function Config:SetCharacterVaultSlots(charKey, slots)
	local c = WoWWeekly.db.chars[charKey]
	slots = tonumber(slots)
	if not c or (slots ~= 1 and slots ~= 2 and slots ~= 3) then return end
	c.gamePlanGoal = c.gamePlanGoal or {}
	c.gamePlanGoal.vaultSlots = slots
end

function Config:GoalAllowsTracker(charState, trackerID)
	local selected = self:GetCharacterGoals(charState)
	if selected.balanced then return true end
	if selected.delves and (trackerID == Constants.TRACKER_DELVES or trackerID == Constants.TRACKER_BOUNTYMAP
			or trackerID == Constants.TRACKER_GILDEDSTASH
		) then return true end
	if selected.mplus and trackerID == Constants.TRACKER_MYTHICPLUS then return true end
	if selected.raid and trackerID == Constants.TRACKER_RAID then return true end
	if selected.professions and (trackerID == Constants.TRACKER_PROFESSION1 or trackerID == Constants.TRACKER_PROFESSION2) then return true end
	return false
end

-- Count unlocked reward choices, independent of gear quality and chosen focus.
-- Prefer the saved slot flags; thresholds provide compatibility for old snapshots.
function Config:GetCombinedVaultProgress(charState)
	local sources = {
		{ id = Constants.TRACKER_DELVES, thresholds = {2,4,8}, noun = "World activities" },
		{ id = Constants.TRACKER_MYTHICPLUS, thresholds = {1,4,8}, noun = "qualifying dungeon runs" },
		{ id = Constants.TRACKER_RAID, thresholds = {2,4,6}, noun = "raid boss kills" },
	}
	local total, nextActions = 0, {}
	for _, source in ipairs(sources) do
		local st = (charState.trackers or {})[source.id] or {}
		local unlocked, nextThreshold = 0, nil
		for i, threshold in ipairs(source.thresholds) do
			local slot = st.slots and st.slots[i]
			local filled
			if slot then filled = slot.unlocked == true
			else filled = (st.rawProgress or st.count or 0) >= threshold end
			if filled then unlocked = unlocked + 1
			elseif not nextThreshold then nextThreshold = threshold end
		end
		total = total + unlocked
		local enabled = source.id == Constants.TRACKER_RAID and self:IsRaidPlanShown()
			or source.id ~= Constants.TRACKER_RAID and self:IsRecommendationEnabled(source.id)
		local raidTracker = _G[ADDON_NAME .. "RaidTracker"]
		if source.id == Constants.TRACKER_RAID and raidTracker and raidTracker.IsRecommendationRelevant then
			enabled = enabled and raidTracker:IsRecommendationRelevant(charState)
		end
		if nextThreshold and enabled then
			nextActions[#nextActions + 1] = {
				id = source.id, noun = source.noun,
				remaining = math.max(1, nextThreshold - (st.rawProgress or st.count or 0)),
			}
		end
	end
	local planner = _G[ADDON_NAME .. "Tooltip"]
	for _, action in ipairs(nextActions) do
		if planner and planner.PlanEffort then
			action.minutes, action.gain, action.urgent = planner:PlanEffort(action.id, charState, action.remaining)
		end
	end
	-- Compare estimated effort across activities, including group setup.
	table.sort(nextActions, function(a, b)
		if not not a.urgent ~= not not b.urgent then return a.urgent == true end
		local ae, be = math.ceil((a.minutes or math.huge) / 10), math.ceil((b.minutes or math.huge) / 10)
		if ae ~= be then return ae < be end
		if (a.gain or 0) ~= (b.gain or 0) then return (a.gain or 0) > (b.gain or 0) end
		return self:GetRecommendationRank(a.id) < self:GetRecommendationRank(b.id)
	end)
	return total, nextActions[1]
end

function Config:GetVaultGoalThreshold(charState, trackerID)
	local slots = self:GetCharacterVaultSlots(charState)
	if trackerID == Constants.TRACKER_RAID then
		-- Balanced retains the existing full raid goal.
		return self:HasCharacterGoal(charState, "balanced") and not self:HasCharacterGoal(charState, "raid") and 6 or ({2, 4, 6})[slots]
	end
	return (trackerID == Constants.TRACKER_MYTHICPLUS and {1, 4, 8} or {2, 4, 8})[slots]
end

local RECOMMENDATIONS = {
	{ key = Constants.TRACKER_BOUNTYMAP, label = "Bounty Map", ids = { Constants.TRACKER_BOUNTYMAP } },
	{ key = Constants.TRACKER_METAQUEST, label = "Weekly Meta Quest", ids = { Constants.TRACKER_METAQUEST } },
	{ key = Constants.TRACKER_GILDEDSTASH, label = "Gilded Stash", ids = { Constants.TRACKER_GILDEDSTASH } },
	{ key = Constants.TRACKER_DELVES, label = "Delves / World Vault", ids = { Constants.TRACKER_DELVES } },
	{ key = Constants.TRACKER_TIMEWALKING, label = "Timewalking", ids = { Constants.TRACKER_TIMEWALKING } },
	{ key = Constants.TRACKER_MYTHICPLUS, label = "Mythic+", ids = { Constants.TRACKER_MYTHICPLUS } },
	{ key = Constants.TRACKER_COILEDISLE_WORLDBOSS, label = "Coiled Isle World Boss", ids = { Constants.TRACKER_COILEDISLE_WORLDBOSS } },
	{ key = "professions", label = "Professions", ids = { Constants.TRACKER_PROFESSION1, Constants.TRACKER_PROFESSION2 } },
	{ key = Constants.TRACKER_TURNBACKSURGE, label = "Turn Back the Surge", ids = { Constants.TRACKER_TURNBACKSURGE } },
}

local function RecommendationKey(trackerId)
	if trackerId == Constants.TRACKER_PROFESSION1 or trackerId == Constants.TRACKER_PROFESSION2 then
		return "professions"
	end
	return trackerId
end

function Config:IsGamePlanShown()
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	return not po or po.gamePlanEnabled ~= false
end

function Config:IsNextStepShown()
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	return not po or po.nextStepEnabled ~= false
end

function Config:IsRaidPlanShown()
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	return not po or po.raidPlanEnabled ~= false
end

function Config:SetPlanOption(key, value)
	WoWWeekly.db.profileOptions[key] = value and true or false
end

function Config:GetMaxDelveTier()
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	return math.max(8, math.min(11, math.floor(tonumber(po and po.maxDelveTier) or 11)))
end

function Config:SetMaxDelveTier(value)
	WoWWeekly.db.profileOptions.maxDelveTier = math.max(8, math.min(11,
		math.floor(tonumber(value) or 11)))
end

function Config:IsRecommendationEnabled(trackerId)
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	local enabled = po and po.enabledRecommendations
	return not enabled or enabled[RecommendationKey(trackerId)] ~= false
end

function Config:SetRecommendationEnabled(key, value)
	local po = WoWWeekly.db.profileOptions
	po.enabledRecommendations = po.enabledRecommendations or {}
	po.enabledRecommendations[key] = value and true or false
end

function Config:SetAllRecommendations(value)
	for _, item in ipairs(RECOMMENDATIONS) do
		self:SetRecommendationEnabled(item.key, value)
	end
end

function Config:GetRecommendationOrder()
	local po = WoWWeekly.db.profileOptions
	local saved = po.recommendationOrder or {}
	local valid, order = {}, {}
	for _, item in ipairs(RECOMMENDATIONS) do valid[item.key] = true end
	for _, key in ipairs(saved) do
		if valid[key] then order[#order + 1] = key; valid[key] = nil end
	end
	for _, item in ipairs(RECOMMENDATIONS) do
		if valid[item.key] then order[#order + 1] = item.key end
	end
	return order
end

function Config:GetRecommendationRank(trackerId)
	local wanted = RecommendationKey(trackerId)
	for rank, key in ipairs(self:GetRecommendationOrder()) do
		if key == wanted then return rank end
	end
	return 999
end

function Config:MoveRecommendation(key, direction)
	local order = self:GetRecommendationOrder()
	for i, current in ipairs(order) do
		if current == key then
			local target = i + direction
			if target >= 1 and target <= #order then
				order[i], order[target] = order[target], order[i]
			end
			break
		end
	end
	WoWWeekly.db.profileOptions.recommendationOrder = order
end

function Config:ResetGamePlanDefaults()
	local po = WoWWeekly.db.profileOptions
	po.gamePlanEnabled, po.nextStepEnabled, po.raidPlanEnabled = true, true, true
	po.maxDelveTier = 11
	po.enabledRecommendations, po.recommendationOrder = {}, nil
end

-- A character is tracked unless explicitly unticked (default = true).
function Config:IsTracked(charKey)
	local t = WoWWeekly.db and WoWWeekly.db.profileOptions and WoWWeekly.db.profileOptions.trackedChars
	if not t then return true end
	return t[charKey] ~= false
end

function Config:SetTracked(charKey, val)
	local po = WoWWeekly.db.profileOptions
	po.trackedChars = po.trackedChars or {}
	po.trackedChars[charKey] = val and true or false
end

function Config:SetAll(val)
	for key in pairs(WoWWeekly.db.chars) do
		self:SetTracked(key, val)
	end
end

-- A tracker (row) is shown unless explicitly disabled (default = true).
function Config:IsTrackerEnabled(trackerId)
	local t = WoWWeekly.db and WoWWeekly.db.profileOptions and WoWWeekly.db.profileOptions.enabledTrackers
	if not t then return true end
	return t[trackerId] ~= false
end

function Config:SetTrackerEnabled(trackerId, val)
	local po = WoWWeekly.db.profileOptions
	po.enabledTrackers = po.enabledTrackers or {}
	po.enabledTrackers[trackerId] = val and true or false
end

function Config:SetAllTrackers(val)
	local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
	if not (TrackerRegistry and TrackerRegistry.GetAll) then return end
	for _, t in pairs(TrackerRegistry:GetAll()) do
		self:SetTrackerEnabled(t.id, val)
	end
end

function Config:GetReadyCraftCrest()
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	return (po and po.readyCraftCrest == "hero") and "hero" or "myth"
end

function Config:SetReadyCraftCrest(crestType)
	WoWWeekly.db.profileOptions.readyCraftCrest = crestType == "hero" and "hero" or "myth"
end

function Config:IsMinimapIconShown()
	local minimap = WoWWeekly.db and WoWWeekly.db.profileOptions and WoWWeekly.db.profileOptions.minimap
	return minimap and minimap.hide == false
end

function Config:SetMinimapIconShown(shown)
	local Broker = _G[ADDON_NAME .. "Broker"]
	if Broker and Broker.SetMinimapShown then Broker:SetMinimapShown(shown) end
end

function Config:GetHoverCharacterLimit()
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	return math.max(1, math.min(20, tonumber(po and po.hoverCharacterLimit) or 5))
end

function Config:SetHoverCharacterLimit(limit)
	WoWWeekly.db.profileOptions.hoverCharacterLimit = math.max(1, math.min(20,
		math.floor(tonumber(limit) or 5)))
end

local VALID_SORT_KEYS = { name = true, ilvl = true, lastSeen = true, level = true }

function Config:GetCharacterSortKey()
	local po = WoWWeekly.db and WoWWeekly.db.profileOptions
	local key = po and po.sortKey
	return VALID_SORT_KEYS[key] and key or "ilvl"
end

function Config:SetCharacterSortKey(key)
	if VALID_SORT_KEYS[key] then WoWWeekly.db.profileOptions.sortKey = key end
end

function Config:SortCharacterKeys(keys, chars)
	local sortKey = self:GetCharacterSortKey()
	table.sort(keys, function(a, b)
		local A, B = chars[a], chars[b]
		if sortKey == "name" then
			local an = (A.name or a):lower()
			local bn = (B.name or b):lower()
			if an ~= bn then return an < bn end
		elseif sortKey == "lastSeen" then
			if (A.lastSeen or 0) ~= (B.lastSeen or 0) then
				return (A.lastSeen or 0) > (B.lastSeen or 0)
			end
		elseif sortKey == "level" then
			if (A.level or 0) ~= (B.level or 0) then return (A.level or 0) > (B.level or 0) end
		elseif (A.ilvl or 0) ~= (B.ilvl or 0) then
			return (A.ilvl or 0) > (B.ilvl or 0)
		end
		return a < b
	end)
end

local function ClassColor(classFile)
	return classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
end

-- Registered trackers bucketed by their declared group, each bucket sorted by
-- order. Returns: byGroup (id -> sorted list), and ungrouped list.
local function CollectTrackersByGroup()
	local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
	local byGroup, ungrouped = {}, {}
	if TrackerRegistry and TrackerRegistry.GetAll then
		for _, t in pairs(TrackerRegistry:GetAll()) do
			if t.group then
				byGroup[t.group] = byGroup[t.group] or {}
				byGroup[t.group][#byGroup[t.group] + 1] = t
			else
				ungrouped[#ungrouped + 1] = t
			end
		end
	end
	local function sortList(l)
		table.sort(l, function(a, b)
			local ao, bo = a.order or 999, b.order or 999
			if ao ~= bo then return ao < bo end
			return (a.label or "") < (b.label or "")
		end)
	end
	for _, l in pairs(byGroup) do sortList(l) end
	sortList(ungrouped)
	return byGroup, ungrouped
end

-- Build the panel that gets embedded into Options > AddOns.
function Config:Initialize()
	if self.panel then return end

	local panel = CreateFrame("Frame", "WoWWeeklyConfigPanel")
	panel.name = "WoW Weekly"
	self.activeTab = "tracking"

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("|cFFFFD100WoW Weekly|r")

	local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	hint:SetJustifyH("LEFT")
	hint:SetWidth(560)
	hint:SetTextColor(0.72, 0.72, 0.72)
	panel.hint = hint

	-- Tab bar: Tracking | Game Plan | Characters
	local function makeTab(text, key, anchor)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(132, 26)
		b:SetText(text)
		if anchor then
			b:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
		else
			b:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
		end
		b:SetScript("OnClick", function()
			Config.activeTab = key
			Config:Refresh()
		end)
		return b
	end
	panel.tabTracking = makeTab("Tracking", "tracking", nil)
	panel.tabPlan     = makeTab("Game Plan", "gameplan", panel.tabTracking)
	panel.tabChars    = makeTab("Characters", "chars", panel.tabPlan)

	-- Bottom action buttons (relabeled per active tab)
	local btnAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnAll:SetSize(120, 22)
	btnAll:SetPoint("BOTTOMLEFT", 16, 16)
	btnAll:SetScript("OnClick", function()
		if Config.activeTab == "chars" then Config:SetAll(true)
		elseif Config.activeTab == "gameplan" then Config:SetAllRecommendations(true)
		else Config:SetAllTrackers(true) end
		Config:Refresh()
	end)
	panel.btnAll = btnAll

	local btnNone = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnNone:SetSize(120, 22)
	btnNone:SetPoint("LEFT", btnAll, "RIGHT", 8, 0)
	btnNone:SetScript("OnClick", function()
		if Config.activeTab == "chars" then Config:SetAll(false)
		elseif Config.activeTab == "gameplan" then Config:SetAllRecommendations(false)
		else Config:SetAllTrackers(false) end
		Config:Refresh()
	end)
	panel.btnNone = btnNone

	local btnReset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnReset:SetSize(140, 22)
	btnReset:SetPoint("LEFT", btnNone, "RIGHT", 8, 0)
	btnReset:SetText("Restore Defaults")
	btnReset:SetScript("OnClick", function()
		Config:ResetGamePlanDefaults()
		Config:Refresh()
	end)
	panel.btnReset = btnReset

	-- Scrollable content area
	local scroll = CreateFrame("ScrollFrame", "WoWWeeklyConfigScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel.tabTracking, "BOTTOMLEFT", 0, -12)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 46)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(540, 10)
	scroll:SetScrollChild(child)
	panel.scrollChild = child
	panel.checks = {}
	panel.headers = {}
	panel.sliders = {}
	panel.cards = {}
	panel.choiceRows = {}
	panel.priorityRows = {}
	panel.helpTexts = {}

	panel:SetScript("OnShow", function() Config:Refresh() end)

	self.panel = panel

	-- Register into the Blizzard Settings UI (Options > AddOns).
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "WoW Weekly")
		Settings.RegisterAddOnCategory(category)
		self.category = category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)  -- fallback for older clients
	end
end

function Config:Refresh()
	local panel = self.panel
	if not panel then return end
	local db = WoWWeekly.db
	if not db then return end
	local child = panel.scrollChild

	for _, cb in ipairs(panel.checks) do
		cb:Hide()
		if cb.rowBg then cb.rowBg:Hide() end
	end
	for _, fs in ipairs(panel.headers) do fs:Hide() end
	for _, slider in ipairs(panel.sliders) do slider:Hide() end
	for _, card in ipairs(panel.cards) do card:Hide() end
	for _, row in ipairs(panel.choiceRows) do row:Hide() end
	for _, row in ipairs(panel.priorityRows) do row:Hide() end
	for _, fs in ipairs(panel.helpTexts) do fs:Hide() end
	if panel.planExplanation then panel.planExplanation:Hide() end

	local y = -4
	local checkIdx, hdrIdx, sliderIdx, cardIdx, choiceIdx, priorityIdx = 0, 0, 0, 0, 0, 0
	local helpIdx = 0
	local function addHelp(text)
		helpIdx = helpIdx + 1
		local fs = panel.helpTexts[helpIdx]
		if not fs then
			fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetWidth(480)
			fs:SetJustifyH("LEFT")
			fs:SetTextColor(0.75, 0.75, 0.8)
			panel.helpTexts[helpIdx] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", child, "TOPLEFT", 12, y)
		fs:SetText(text)
		fs:Show()
		y = y - fs:GetStringHeight() - 14
	end

	-- Soft-backed cards turn related controls into visual sections instead of
	-- one uninterrupted list. Cards are laid out after their contents so their
	-- height naturally follows however many trackers/characters they contain.
	local function beginCard()
		cardIdx = cardIdx + 1
		local card = panel.cards[cardIdx]
		if not card then
			card = CreateFrame("Frame", nil, child, "BackdropTemplate")
			card:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8X8",
				edgeFile = "Interface\\Buttons\\WHITE8X8",
				edgeSize = 1,
			})
			card:SetBackdropColor(0.055, 0.05, 0.075, 0.88)
			card:SetBackdropBorderColor(0.22, 0.20, 0.28, 0.9)
			card:EnableMouse(false)
			panel.cards[cardIdx] = card
		end
		-- Keep the card backdrop on the scroll child's own frame level so its
		-- BACKGROUND layer stays behind headings and controls.
		card:SetFrameLevel(child:GetFrameLevel())
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y + 6)
		card:SetWidth(520)
		card:Show()
		y = y - 10
		return card, y
	end

	local function endCard(card, contentTop)
		-- Include the full height of the final 26px control plus breathing room.
		card:SetHeight(math.max(48, contentTop - y + 24))
		y = y - 12
	end

	-- A non-interactive category label.
	local function addHeader(text, color)
		hdrIdx = hdrIdx + 1
		local fs = panel.headers[hdrIdx]
		if not fs then
			fs = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
			panel.headers[hdrIdx] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 2, y)
		fs:SetText(text)
		if color then fs:SetTextColor(color.r, color.g, color.b) else fs:SetTextColor(1, 1, 1) end
		fs:Show()
		y = y - 24
	end

	-- One checkbox row. kind: "tracker" | "char" | "group" | "crest" | "minimap". For "group",
	-- childIds is the list of tracker IDs the master toggle controls.
	local function addCheck(kind, key, text, color, checked, indent, childIds, help)
		checkIdx = checkIdx + 1
		local cb = panel.checks[checkIdx]
		if not cb then
			cb = CreateFrame("CheckButton", "WoWWeeklyConfigCheck" .. checkIdx, child, "UICheckButtonTemplate")
			cb:SetHitRectInsets(0, -470, 0, 0)
			cb.rowBg = child:CreateTexture(nil, "BACKGROUND")
			cb.rowBg:SetColorTexture(1, 1, 1, 0.025)
			cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
			cb:SetScript("OnEnter", function(self)
				if not self.help then return end
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(self.label:GetText())
				GameTooltip:AddLine(self.help, 1, 1, 1, true)
				GameTooltip:Show()
			end)
			cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
			cb:SetScript("OnHide", function(self)
				if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
			end)
			cb:SetScript("OnClick", function(self)
				if self.kind == "tracker" then
					Config:SetTrackerEnabled(self.key, self:GetChecked())
				elseif self.kind == "planoption" then
					Config:SetPlanOption(self.key, self:GetChecked())
				elseif self.kind == "recommendation" then
					Config:SetRecommendationEnabled(self.key, self:GetChecked())
				elseif self.kind == "activitygoal" then
					Config:SetCharacterActivityGoal(self.key, self.childIds, self:GetChecked())
				elseif self.kind == "bonusroll" then
					Config:SetCharacterBonusRoll(self.key, self:GetChecked())
				elseif self.kind == "minimap" then
					Config:SetMinimapIconShown(self:GetChecked())
				elseif self.kind == "crest" then
					Config:SetReadyCraftCrest(self.key)
				elseif self.kind == "group" then
					local v = self:GetChecked()
					for _, id in ipairs(self.childIds or {}) do Config:SetTrackerEnabled(id, v) end
				else
					Config:SetTracked(self.key, self:GetChecked())
				end
				Config:Refresh()  -- so a master toggle / parent state updates
			end)
			panel.checks[checkIdx] = cb
		end
		cb:ClearAllPoints()
		cb:SetPoint("TOPLEFT", 4 + (indent or 0), y)
		cb.rowBg:ClearAllPoints()
		cb.rowBg:SetPoint("TOPLEFT", child, "TOPLEFT", 6, y - 1)
		cb.rowBg:SetSize(506, 24)
		cb.rowBg:Show()
		cb:Show()
		cb.label:SetText(text)
		if color then cb.label:SetTextColor(color.r, color.g, color.b) else cb.label:SetTextColor(1, 1, 1) end
		cb.kind = kind
		cb.key = key
		cb.childIds = childIds
		cb.help = help
		cb:SetChecked(checked)
		y = y - 26
	end

	local function addPriorityRow(rank, item, enabled, canUp, canDown)
		priorityIdx = priorityIdx + 1
		local row = panel.priorityRows[priorityIdx]
		if not row then
			row = CreateFrame("Frame", nil, child)
			row.bg = row:CreateTexture(nil, "BACKGROUND")
			row.bg:SetAllPoints()
			row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
			row.check:SetPoint("LEFT", 34, 0)
			row.check:SetScript("OnClick", function(self)
				Config:SetRecommendationEnabled(self.key, self:GetChecked())
				Config:Refresh()
			end)
			row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.rank:SetPoint("LEFT", 12, 0)
			row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
			row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.up:SetSize(48, 22); row.up:SetPoint("RIGHT", -62, 0); row.up:SetText("Up")
			row.down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			row.down:SetSize(48, 22); row.down:SetPoint("LEFT", row.up, "RIGHT", 4, 0); row.down:SetText("Down")
			row.up:SetScript("OnClick", function(self)
				Config:MoveRecommendation(self.key, -1); Config:Refresh()
			end)
			row.down:SetScript("OnClick", function(self)
				Config:MoveRecommendation(self.key, 1); Config:Refresh()
			end)
			panel.priorityRows[priorityIdx] = row
		end
		row:ClearAllPoints(); row:SetPoint("TOPLEFT", child, "TOPLEFT", 6, y); row:SetSize(506, 28)
		row.bg:SetColorTexture(1, 1, 1, rank % 2 == 0 and 0.035 or 0.015)
		row.rank:SetText(rank .. ".")
		row.label:SetText(item.label)
		row.check.key = item.key; row.check:SetChecked(enabled)
		row.up.key, row.down.key = item.key, item.key
		row.up:SetEnabled(canUp); row.down:SetEnabled(canDown)
		row:Show(); y = y - 30
	end

	local function addSlider(text, value, minValue, maxValue, onChanged)
		sliderIdx = sliderIdx + 1
		local slider = panel.sliders[sliderIdx]
		if not slider then
			local name = "WoWWeeklyConfigSlider" .. sliderIdx
			slider = CreateFrame("Slider", name, child, "OptionsSliderTemplate")
			slider:SetWidth(260)
			slider:SetObeyStepOnDrag(true)
			slider:SetValueStep(1)
			slider:SetScript("OnValueChanged", function(self, newValue)
				newValue = math.floor(newValue + 0.5)
				_G[self:GetName() .. "Text"]:SetText(self.label .. ": " .. newValue)
				if not self.refreshing then self.onChanged(newValue) end
			end)
			panel.sliders[sliderIdx] = slider
		end
		slider:ClearAllPoints()
		slider:SetPoint("TOPLEFT", 12, y - 8)
		slider:SetMinMaxValues(minValue, maxValue)
		_G[slider:GetName() .. "Low"]:SetText(minValue)
		_G[slider:GetName() .. "High"]:SetText(maxValue)
		slider.label = text
		slider.onChanged = onChanged
		slider.refreshing = true
		slider:SetValue(value)
		slider.refreshing = false
		_G[slider:GetName() .. "Text"]:SetText(text .. ": " .. value)
		slider:Show()
		y = y - 54
	end

	local function addDropdown(text, choices, selected, onChanged)
		choiceIdx = choiceIdx + 1
		local row = panel.choiceRows[choiceIdx]
		if not row then
			row = CreateFrame("Frame", nil, child)
			row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			row.label:SetPoint("TOPLEFT", 4, 0)
			row.dropdown = CreateFrame("Frame", "WoWWeeklyConfigDropdown" .. choiceIdx, row,
				"UIDropDownMenuTemplate")
			row.dropdown:SetPoint("TOPLEFT", -16, -18)
			UIDropDownMenu_SetWidth(row.dropdown, 300)
			UIDropDownMenu_Initialize(row.dropdown, function(_, level)
				for _, choice in ipairs(row.choices or {}) do
					local key, label = choice.key, choice.label
					local info = UIDropDownMenu_CreateInfo()
					info.text = label
					info.checked = key == row.selected
					if choice.description then
						info.tooltipTitle = label
						info.tooltipText = choice.description
						info.tooltipOnButton = true
					end
					info.func = function()
						row.onChanged(key)
						Config:Refresh()
					end
					UIDropDownMenu_AddButton(info, level)
				end
			end)
			panel.choiceRows[choiceIdx] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 12, y)
		row:SetSize(496, 48)
		row.label:SetText(text)
		row.choices = choices
		row.selected = selected
		row.onChanged = onChanged
		local selectedLabel = selected
		for _, choice in ipairs(choices) do
			if choice.key == selected then selectedLabel = choice.label break end
		end
		UIDropDownMenu_SetText(row.dropdown, selectedLabel)
		row:Show()
		y = y - 52
	end

	panel.btnReset:SetShown(self.activeTab == "gameplan")
	if self.activeTab == "gameplan" then
		panel.hint:SetText("Shape the guidance without hiding useful tracker rows. Higher activities win whenever they are available.")
		panel.btnAll:SetText("Enable All")
		panel.btnNone:SetText("Disable All")

		local displayCard, displayTop = beginCard()
		addHeader("Game Plan display", { r = 1, g = 0.82, b = 0 })
		addCheck("planoption", "gamePlanEnabled", "Show Weekly Game Plan", nil, Config:IsGamePlanShown())
		addCheck("planoption", "nextStepEnabled", "Show Next Step recommendations", nil, Config:IsNextStepShown(), 18)
		addCheck("planoption", "raidPlanEnabled", "Show Raid Plan column", nil, Config:IsRaidPlanShown(), 18)
		addHelp("Play Next ranks all tracked characters by upcoming raids, estimated time to the next reward, then gear benefit. Choose goals in the Characters tab. Completed goals go last; status columns keep their own order.")
		y = y - 14
		addSlider("Maximum Delve tier", Config:GetMaxDelveTier(), 8, 11,
			function(value) Config:SetMaxDelveTier(value) end)
		endCard(displayCard, displayTop)

		local priorityCard, priorityTop = beginCard()
		addHeader("Activity preferences", { r = 1, g = 0.82, b = 0 })
		local explanation = panel.planExplanation or child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		panel.planExplanation = explanation
		explanation:ClearAllPoints()
		explanation:SetPoint("TOPLEFT", child, "TOPLEFT", 12, y)
		explanation:SetWidth(480); explanation:SetJustifyH("LEFT")
		explanation:SetText("Untick an activity to exclude it from recommendations. Arrows break ties after urgency, estimated effort and gear benefit. Time estimates are rough and include group setup.")
		explanation:SetTextColor(0.65, 0.65, 0.7)
		explanation:Show()
		y = y - math.max(34, explanation:GetStringHeight() + 8)
		local byKey = {}
		for _, item in ipairs(RECOMMENDATIONS) do byKey[item.key] = item end
		local order = Config:GetRecommendationOrder()
		for rank, key in ipairs(order) do
			local item = byKey[key]
			addPriorityRow(rank, item, Config:IsRecommendationEnabled(key), rank > 1, rank < #order)
		end
		endCard(priorityCard, priorityTop)
	elseif self.activeTab == "chars" then
		panel.hint:SetText("Choose characters and weekly goals. Hover over a goal for details.")
		panel.btnAll:SetText("Track All")
		panel.btnNone:SetText("Track None")

		local displayCard, displayTop = beginCard()
		addHeader("Character display")
		addSlider("Characters shown on hover", Config:GetHoverCharacterLimit(), 1, 20,
			function(value) Config:SetHoverCharacterLimit(value) end)
		addDropdown("Sort characters by", {
			{ key = "name", label = "Name" },
			{ key = "ilvl", label = "Item Level" },
			{ key = "lastSeen", label = "Last Played" },
			{ key = "level", label = "Level" },
		}, Config:GetCharacterSortKey(), function(key) Config:SetCharacterSortKey(key) end)
		endCard(displayCard, displayTop)

		local rosterCard, rosterTop = beginCard()
		addHeader("Tracked characters")
		local keys = {}
		for k in pairs(db.chars) do keys[#keys + 1] = k end
		Config:SortCharacterKeys(keys, db.chars)
		for _, key in ipairs(keys) do
			local c = db.chars[key]
			local name = c.name or key
			local col = ClassColor(c.classFile)
			local text = name .. "  |cFF888888(" .. (c.realm or "?") .. ", level " .. (c.level or 0) .. ")|r"
			addCheck("char", key, text, col, Config:IsTracked(key))
			local charKey = key
			for _, choice in ipairs(CHARACTER_GOALS) do
				addCheck("activitygoal", charKey, choice.label, nil, Config:HasCharacterGoal(c, choice.key), 18, choice.key, choice.description)
			end
			addCheck("bonusroll", charKey, "Bonus-roll option", nil, Config:IsCharacterBonusRollEnabled(c), 18, nil,
				"Fill any three Vault slots across World, Dungeon and Raid to unlock a bonus-roll token instead of gear. Works alongside your goals, or alone if all activities are unticked.")
			local selected = Config:GetCharacterGoals(c)
			if selected.balanced or selected.delves or selected.mplus or selected.raid then
				addDropdown("Weekly Vault target", {
					{ key = 1, label = "1 Vault slot", description = "Per selected row: 2 Tier 8+ World credits, 1 Mythic+ run at +10 or higher, or 2 raid bosses." },
					{ key = 2, label = "2 Vault slots", description = "Per selected row: 4 Tier 8+ World credits, 4 Mythic+ runs at +10 or higher, or 4 raid bosses." },
					{ key = 3, label = "All 3 Vault slots", description = "Per selected row: 8 Tier 8+ World credits, 8 Mythic+ runs at +10 or higher, or 6 raid bosses. More slots give more choices, not more weekly items." },
				}, Config:GetCharacterVaultSlots(c),
					function(slots) Config:SetCharacterVaultSlots(charKey, slots) end)
			end
		end
		endCard(rosterCard, rosterTop)
	else
		panel.hint:SetText("Choose the information that matters to you. Category switches control every tracker inside their card.")
		panel.btnAll:SetText("Enable All")
		panel.btnNone:SetText("Disable All")

		local GOLD = { r = 1, g = 0.82, b = 0 }
		local byGroup, ungrouped = CollectTrackersByGroup()

		local displayCard, displayTop = beginCard()
		addHeader("Display")
		addCheck("minimap", "minimap", "Show minimap icon", nil, Config:IsMinimapIconShown())
		endCard(displayCard, displayTop)

		-- One category per declared group, in display order: a master toggle for
		-- the whole group, then its trackers indented beneath it.
		local function renderCategory(label, list)
			if #list == 0 then return end
			local card, cardTop = beginCard()
			-- The group title shows as on if ANY sub-item is enabled, so ticking
			-- a single child lights up its category. (Clicking the title itself
			-- toggles every child on/off together.)
			local childIds, anyOn = {}, false
			for _, t in ipairs(list) do
				childIds[#childIds + 1] = t.id
				if Config:IsTrackerEnabled(t.id) then anyOn = true end
			end
			addHeader(label, GOLD)
			addCheck("group", label, "Enable this section", nil, anyOn, 0, childIds)
			for _, t in ipairs(list) do
				addCheck("tracker", t.id, t.label, nil, Config:IsTrackerEnabled(t.id), 18)
				if t.id == Constants.TRACKER_READYTOCRAFT then
					local selected = Config:GetReadyCraftCrest()
					addCheck("crest", "hero", "Use Hero Mistcrests", nil, selected == "hero", 48)
					addCheck("crest", "myth", "Use Myth Mistcrests", nil, selected == "myth", 48)
				end
			end
			endCard(card, cardTop)
		end

		for _, grp in ipairs(Constants.GROUPS) do
			renderCategory(grp.label, byGroup[grp.id] or {})
		end
		renderCategory("Other", ungrouped)
	end

	child:SetHeight(math.max(10, -y + 8))

	-- Reflect the active tab on the tab buttons (locked-down = selected).
	for key, button in pairs({ tracking = panel.tabTracking, gameplan = panel.tabPlan, chars = panel.tabChars }) do
		if key == self.activeTab then
			button:SetButtonState("PUSHED", true); button:LockHighlight()
		else
			button:SetButtonState("NORMAL", false); button:UnlockHighlight()
		end
	end
end

-- Open straight to our panel in the Settings UI.
function Config:Open()
	self:Initialize()
	if self.category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.category:GetID())
	elseif InterfaceOptionsFrame_OpenToCategory and self.panel then
		InterfaceOptionsFrame_OpenToCategory(self.panel)
		InterfaceOptionsFrame_OpenToCategory(self.panel)  -- twice: known Blizzard quirk
	end
end

_G[ADDON_NAME .. "Config"] = Config
