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
	title:SetText("WoW Weekly")

	local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	hint:SetJustifyH("LEFT")
	hint:SetWidth(560)
	panel.hint = hint

	-- Tab bar: Tracking | Characters
	local function makeTab(text, key, anchor)
		local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
		b:SetSize(120, 24)
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

	for _, cb in ipairs(panel.checks) do cb:Hide() end
	for _, fs in ipairs(panel.headers) do fs:Hide() end

	local y = -4
	local checkIdx, hdrIdx = 0, 0

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

	-- One checkbox row. kind: "tracker" | "char" | "group" | "crest". For "group",
	-- childIds is the list of tracker IDs the master toggle controls.
	local function addCheck(kind, key, text, color, checked, indent, childIds)
		checkIdx = checkIdx + 1
		local cb = panel.checks[checkIdx]
		if not cb then
			cb = CreateFrame("CheckButton", "WoWWeeklyConfigCheck" .. checkIdx, child, "UICheckButtonTemplate")
			cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
			cb:SetScript("OnClick", function(self)
				if self.kind == "tracker" then
					Config:SetTrackerEnabled(self.key, self:GetChecked())
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
		cb:Show()
		cb.label:SetText(text)
		if color then cb.label:SetTextColor(color.r, color.g, color.b) else cb.label:SetTextColor(1, 1, 1) end
		cb.kind = kind
		cb.key = key
		cb.childIds = childIds
		cb:SetChecked(checked)
		y = y - 26
	end

	if self.activeTab == "chars" then
		panel.hint:SetText("Choose which characters appear in the tooltip grid. The character you are currently logged into always appears first.")
		panel.btnAll:SetText("Track All")
		panel.btnNone:SetText("Track None")

		addHeader("Characters to show")
		local keys = {}
		for k in pairs(db.chars) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			local A, B = db.chars[a], db.chars[b]
			if (A.level or 0) ~= (B.level or 0) then return (A.level or 0) > (B.level or 0) end
			if (A.ilvl or 0) ~= (B.ilvl or 0) then return (A.ilvl or 0) > (B.ilvl or 0) end
			return a < b
		end)
		for _, key in ipairs(keys) do
			local c = db.chars[key]
			local name = c.name or key
			local col = ClassColor(c.classFile)
			local text = name .. "  |cFF888888(" .. (c.realm or "?") .. ", level " .. (c.level or 0) .. ")|r"
			addCheck("char", key, text, col, Config:IsTracked(key))
		end
	else
		panel.hint:SetText("Choose which tracker rows appear in the tooltip grid. A category toggle turns its whole group on or off.")
		panel.btnAll:SetText("Enable All")
		panel.btnNone:SetText("Disable All")

		local GOLD = { r = 1, g = 0.82, b = 0 }
		local byGroup, ungrouped = CollectTrackersByGroup()

		-- One category per declared group, in display order: a master toggle for
		-- the whole group, then its trackers indented beneath it.
		local function renderCategory(label, list)
			if #list == 0 then return end
			-- The group title shows as on if ANY sub-item is enabled, so ticking
			-- a single child lights up its category. (Clicking the title itself
			-- toggles every child on/off together.)
			local childIds, anyOn = {}, false
			for _, t in ipairs(list) do
				childIds[#childIds + 1] = t.id
				if Config:IsTrackerEnabled(t.id) then anyOn = true end
			end
			addCheck("group", label, "|cFFFFD100" .. label .. "|r", GOLD, anyOn, 0, childIds)
			for _, t in ipairs(list) do
				addCheck("tracker", t.id, t.label, nil, Config:IsTrackerEnabled(t.id), 24)
				if t.id == Constants.TRACKER_READYTOCRAFT then
					local selected = Config:GetReadyCraftCrest()
					addCheck("crest", "hero", "Use Hero Mistcrests", nil, selected == "hero", 48)
					addCheck("crest", "myth", "Use Myth Mistcrests", nil, selected == "myth", 48)
				end
			end
			y = y - 6
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
