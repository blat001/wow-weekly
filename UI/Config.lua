local ADDON_NAME = "WoWWeekly"
local WoWWeekly  = _G[ADDON_NAME]
local Constants  = _G[ADDON_NAME .. "Constants"]

local Config = {}

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

	-- Tab bar: Tracking | Characters
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
	panel.tabChars    = makeTab("Characters", "chars", panel.tabTracking)

	-- Bottom action buttons (relabeled per active tab)
	local btnAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnAll:SetSize(120, 22)
	btnAll:SetPoint("BOTTOMLEFT", 16, 16)
	btnAll:SetScript("OnClick", function()
		if Config.activeTab == "chars" then Config:SetAll(true) else Config:SetAllTrackers(true) end
		Config:Refresh()
	end)
	panel.btnAll = btnAll

	local btnNone = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	btnNone:SetSize(120, 22)
	btnNone:SetPoint("LEFT", btnAll, "RIGHT", 8, 0)
	btnNone:SetScript("OnClick", function()
		if Config.activeTab == "chars" then Config:SetAll(false) else Config:SetAllTrackers(false) end
		Config:Refresh()
	end)
	panel.btnNone = btnNone

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

	local y = -4
	local checkIdx, hdrIdx, sliderIdx, cardIdx, choiceIdx = 0, 0, 0, 0, 0

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
	local function addCheck(kind, key, text, color, checked, indent, childIds)
		checkIdx = checkIdx + 1
		local cb = panel.checks[checkIdx]
		if not cb then
			cb = CreateFrame("CheckButton", "WoWWeeklyConfigCheck" .. checkIdx, child, "UICheckButtonTemplate")
			cb:SetHitRectInsets(0, -470, 0, 0)
			cb.rowBg = child:CreateTexture(nil, "BACKGROUND")
			cb.rowBg:SetColorTexture(1, 1, 1, 0.025)
			cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
			cb:SetScript("OnClick", function(self)
				if self.kind == "tracker" then
					Config:SetTrackerEnabled(self.key, self:GetChecked())
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
		cb:SetChecked(checked)
		y = y - 26
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
			_G[name .. "Low"]:SetText(minValue)
			_G[name .. "High"]:SetText(maxValue)
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
			row.dropdown = CreateFrame("Frame", "WoWWeeklyConfigSortDropdown", row,
				"UIDropDownMenuTemplate")
			row.dropdown:SetPoint("TOPLEFT", -16, -18)
			UIDropDownMenu_SetWidth(row.dropdown, 220)
			UIDropDownMenu_Initialize(row.dropdown, function(_, level)
				for _, choice in ipairs(row.choices or {}) do
					local key, label = choice.key, choice.label
					local info = UIDropDownMenu_CreateInfo()
					info.text = label
					info.checked = key == row.selected
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

	if self.activeTab == "chars" then
		panel.hint:SetText("Choose your hover size and which characters belong in the overview. Your current character always appears first.")
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
	local active, inactive = panel.tabTracking, panel.tabChars
	if self.activeTab == "chars" then active, inactive = panel.tabChars, panel.tabTracking end
	active:SetButtonState("PUSHED", true); active:LockHighlight()
	inactive:SetButtonState("NORMAL", false); inactive:UnlockHighlight()
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
