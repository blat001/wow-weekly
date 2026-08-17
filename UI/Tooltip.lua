local ADDON_NAME = "WoWWeekly"
local WoWWeekly  = _G[ADDON_NAME]
local Constants  = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
local WeeklyReset = _G[ADDON_NAME .. "WeeklyReset"]
local LibQTip = LibStub("LibQTip-1.0")

local Tooltip = {}

-- Return a "|cAARRGGBB" color escape for a class, falling back to white.
local function ClassColor(classFile)
    local c = classFile and (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
    if c and c.colorStr then
        return "|c" .. c.colorStr
    end
    return Constants.COLOR_WHITE
end

local function CharacterHeaderLabel(charState, fallbackKey)
    local name = charState.name or fallbackKey
    local ilvl = tonumber(charState.ilvl)
    if ilvl and ilvl > 0 then
        return string.format("%s (%.0f)", name, ilvl)
    end
    return name
end


-- Build the column order: the character you're logged into is always first,
-- followed by the other *tracked* characters (sorted by level/ilvl).
local function OrderedCharKeys(db)
    local Database = _G[ADDON_NAME .. "Database"]
    local Config   = _G[ADDON_NAME .. "Config"]
    local currentKey = Database and Database.charKey

    local others = {}
    for k in pairs(db.chars) do
        if k ~= currentKey then
            local tracked = true
            if Config and Config.IsTracked then tracked = Config:IsTracked(k) end
            if tracked then others[#others + 1] = k end
        end
    end
    table.sort(others, function(a, b)
        local A, B = db.chars[a], db.chars[b]
        if (A.level or 0) ~= (B.level or 0) then return (A.level or 0) > (B.level or 0) end
        if (A.ilvl or 0) ~= (B.ilvl or 0) then return (A.ilvl or 0) > (B.ilvl or 0) end
        return a < b
    end)

    local keys = {}
    if currentKey and db.chars[currentKey] then keys[#keys + 1] = currentKey end  -- always first
    for _, k in ipairs(others) do keys[#keys + 1] = k end
    return keys
end

function Tooltip:Show(anchorFrame)
    local db = WoWWeekly.db
    if not db or not db.chars then return end

    -- Opening the UI is another reliable opportunity to capture equipment
    -- data after the login loading sequence has completed.
    local Database = _G[ADDON_NAME .. "Database"]
    if Database and Database.RefreshCurrentCharacter then
        Database:RefreshCurrentCharacter()
    end

    -- If the weekly reset happened while we stayed logged in, sweep stale
    -- character snapshots before rendering so old-week numbers never show.
    if WeeklyReset and WeeklyReset.CheckAndApplyWeeklyReset then
        WeeklyReset:CheckAndApplyWeeklyReset()
    end

    -- Refresh the current character's trackers so live data (e.g. a keystone
    -- looted this session) is up to date whenever you open the grid.
    if TrackerRegistry and TrackerRegistry.ScanAll then TrackerRegistry:ScanAll() end

    local charKeys = OrderedCharKeys(db)
    if #charKeys == 0 then return end

    local numCols = 1 + #charKeys
    if self.tip then LibQTip:Release(self.tip); self.tip = nil end

    local just = {"LEFT"}
    for i = 1, #charKeys do just[#just+1] = "CENTER" end

    local tip = LibQTip:Acquire(ADDON_NAME .. "Tip", numCols, unpack(just))
    self.tip = tip
	if tip.SetBackdropColor then tip:SetBackdropColor(0.02, 0.015, 0.03, 0.96) end

    -- Title row, centered across the whole table
    local titleLine = tip:AddHeader("")
    tip:SetCell(titleLine, 1, Constants.COLOR_YELLOW .. "WoW Weekly" .. Constants.COLOR_RESET, nil, "CENTER", numCols)
    tip:AddSeparator(1, 1, 1, 1, 0.4)

    -- Column-header row: "Task" label + each character in class color
    local hdr = tip:AddLine()
    tip:SetCell(hdr, 1, Constants.COLOR_GRAY .. "Task" .. Constants.COLOR_RESET)
    for i, key in ipairs(charKeys) do
        local c = db.chars[key]
        local label = CharacterHeaderLabel(c, key)
        if WeeklyReset:IsWeekStale(key) then
            label = Constants.COLOR_GRAY .. label .. " (old)" .. Constants.COLOR_RESET
        else
            label = ClassColor(c.classFile) .. label .. Constants.COLOR_RESET
        end
        tip:SetCell(hdr, i + 1, label)
    end
    -- Collect enabled trackers, bucketed by their declared group
    local Config = _G[ADDON_NAME .. "Config"]
    local byGroup, ungrouped = {}, {}
    for _, t in pairs(TrackerRegistry:GetAll()) do
        local enabled = true
        if Config and Config.IsTrackerEnabled then enabled = Config:IsTrackerEnabled(t.id) end
        if enabled then
            if t.group then
                byGroup[t.group] = byGroup[t.group] or {}
                byGroup[t.group][#byGroup[t.group] + 1] = t
            else
                ungrouped[#ungrouped + 1] = t
            end
        end
    end

    local function sortByOrder(list)
        table.sort(list, function(a, b)
            local ao, bo = a.order or 999, b.order or 999
            if ao ~= bo then return ao < bo end
            return (a.label or "") < (b.label or "")
        end)
    end

    -- LibQTip only exposes horizontal justification per cell. For multi-line
    -- cells (e.g. the stacked profession rows) we also want the text block
    -- pinned to the TOP of the row so the column-1 label lines up with the
    -- first line instead of floating in the vertical middle. Reach into the
    -- cell's fontString to set vertical justification directly.
    local function SetCellVJust(lineNum, colNum, vjust)
        local lineObj = tip.lines and tip.lines[lineNum]
        local cell = lineObj and lineObj.cells and lineObj.cells[colNum]
        if cell and cell.fontString then cell.fontString:SetJustifyV(vjust) end
    end

    -- Render one section: a gold header spanning the table, then its rows
    -- (thin dividers between rows for a table feel).
    local renderedAny = false
    local function renderGroup(label, list)
        if #list == 0 then return end
        sortByOrder(list)
        -- heavier divider above each section after the first
        tip:AddSeparator(2, 1, 1, 1, renderedAny and 0.6 or 0.6)
        renderedAny = true
        local h = tip:AddLine()
        tip:SetCell(h, 1, Constants.COLOR_YELLOW .. label .. Constants.COLOR_RESET,
            GameFontNormal, "LEFT", numCols)
        tip:AddSeparator(1, 1, 1, 1, 0.25)
        local firstRow = true
        for _, tracker in ipairs(list) do
            if not firstRow then tip:AddSeparator(1, 0.3, 0.3, 0.3, 0.4) end
            firstRow = false
            local line = tip:AddLine()
            -- Multi-line trackers (professions) read better left-justified with
            -- the label pinned to the top of the row, not vertically centered.
            local cellJust = (tracker.group == "professions") and "LEFT" or nil
            tip:SetCell(line, 1, Constants.COLOR_WHITE .. "  " .. tracker.label .. Constants.COLOR_RESET)
            SetCellVJust(line, 1, "TOP")
            for i, key in ipairs(charKeys) do
                tip:SetCell(line, i + 1, tracker:GetSummary(db.chars[key]), nil, cellJust)
                SetCellVJust(line, i + 1, "TOP")
            end
        end
    end

    -- Rank every character by its single best plausible next action. Activities
    -- already started this week get a strong boost. Dungeon/Raid relevance is
    -- supplied by their trackers (recent runs/kills), and low-rank professions
    -- are filtered by the profession tracker.
    local basePriority = {
        [Constants.TRACKER_BOUNTYMAP] = 760,
        [Constants.TRACKER_METAQUEST] = 720,
        [Constants.TRACKER_DELVES] = 650,
        [Constants.TRACKER_GILDEDSTASH] = 620,
        [Constants.TRACKER_TIMEWALKING] = 600,
        [Constants.TRACKER_TURNBACKSURGE] = 560,
        [Constants.TRACKER_PURGINGVAULTS] = 550,
        [Constants.TRACKER_COFFERKEYSHARDS] = 500,
        [Constants.TRACKER_PROFESSION1] = 300,
        [Constants.TRACKER_PROFESSION2] = 300,
    }

    local activityForTracker = {
        [Constants.TRACKER_DELVES] = "delves",
        [Constants.TRACKER_GILDEDSTASH] = "delves",
        [Constants.TRACKER_BOUNTYMAP] = "delves",
        [Constants.TRACKER_MYTHICPLUS] = "mplus",
        [Constants.TRACKER_RAID] = "raid",
        [Constants.TRACKER_PROFESSION1] = "professions",
        [Constants.TRACKER_PROFESSION2] = "professions",
    }

    local delveGearTrackers = {
        [Constants.TRACKER_DELVES] = true,
        [Constants.TRACKER_GILDEDSTASH] = true,
        [Constants.TRACKER_BOUNTYMAP] = true,
    }

    local function hasMythTrackActivity(c)
        local function hasMythSlot(trackerID)
            local st = c.trackers[trackerID] or {}
            for _, slot in ipairs(st.slots or {}) do
                if slot.unlocked and slot.track == "M" then return true end
            end
            return false
        end
        if hasMythSlot(Constants.TRACKER_MYTHICPLUS)
            or hasMythSlot(Constants.TRACKER_RAID) then return true end

        local profile = c.activityProfile or {}
        local mplus = profile.mplus
        if mplus and (mplus.highest or 0) >= Constants.MPLUS_MIN_LEVEL
            and Constants.GetActivityAffinity(c, "mplus") >= 0.5 then return true end

        local raid = profile.raid
        if raid and (raid.highest or 0) >= 3
            and Constants.GetActivityAffinity(c, "raid") >= 0.5 then return true end
        return false
    end

    local function actionScore(t, c)
        local st = c.trackers[t.id] or {}
        local score = basePriority[t.id] or 450
        -- Finishing something already underway is normally the best next move.
        if t.id == Constants.TRACKER_MYTHICPLUS and st.hasRuns then
            score = 1000 + (st.rawProgress or 0)
        elseif t.id == Constants.TRACKER_RAID and st.hasKills then
            score = 980 + (st.count or 0)
        elseif t.id == Constants.TRACKER_BOUNTYMAP and st.state == "inbags" then
            score = 960
        elseif t.id == Constants.TRACKER_METAQUEST and (st.cur or 0) > 0 then
            score = 940 + (st.cur or 0)
        elseif t.id == Constants.TRACKER_DELVES and (st.rawProgress or 0) > 0 then
            score = 900 + (st.rawProgress or 0)
        elseif t.id == Constants.TRACKER_TIMEWALKING and (st.cur or 0) > 0 then
            score = 880 + (st.cur or 0)
        elseif t.id == Constants.TRACKER_GILDEDSTASH and (st.looted or 0) > 0 then
            score = 860 + (st.looted or 0)
        end
        local activity = activityForTracker[t.id]
        if activity then
            score = score + math.min(160, Constants.GetActivityAffinity(c, activity) * 40)
        end
        return score
    end

    local recs = {}
    for _, key in ipairs(charKeys) do
        local c = db.chars[key]
        local best
        for _, t in pairs(TrackerRegistry:GetAll()) do
            if t.countsForRecommend then
                local enabled = not (Config and Config.IsTrackerEnabled)
                    or Config:IsTrackerEnabled(t.id)
                local relevant = (t.IsRelevant == nil) or t:IsRelevant(c)
                -- A decaying history can make established M+/Raid characters
                -- relevant before they begin that activity in the current week.
                local activity = activityForTracker[t.id]
                if not relevant and (activity == "mplus" or activity == "raid") then
                    relevant = Constants.GetActivityAffinity(c, activity) >= 0.5
                end
                local worthwhile = (t.StopIlvl == nil)
                    or Constants.VaultWorthDoing(c, t:StopIlvl(c))
                if worthwhile and delveGearTrackers[t.id] and hasMythTrackActivity(c) then
                    worthwhile = false
                end
                if enabled and relevant and worthwhile and t.IsComplete and not t:IsComplete(c) then
                    local score = actionScore(t, c)
                    if not best or score > best.score
                        or (score == best.score and (t.order or 999) < (best.order or 999)) then
                        best = {
                            score = score,
                            order = t.order or 999,
                            text = (t.GetAction and t:GetAction(c)) or t.label,
                        }
                    end
                end
            end
        end
        recs[#recs + 1] = {
            name = c.name or key,
            classFile = c.classFile,
            ilvl = c.ilvl or 0,
            best = best,
            needsCalibration = c.playedSeason ~= Constants.MIDNIGHT_SEASON_KEY,
            engagement = ((c.seasonPlayed or 0) / 3600)
                + Constants.GetActivityAffinity(c, "mplus") * 2
                + Constants.GetActivityAffinity(c, "raid") * 2
                + Constants.GetActivityAffinity(c, "delves")
                + Constants.GetActivityAffinity(c, "professions") * 0.5,
        }
    end
    table.sort(recs, function(a, b)
        local aw, bw = a.best ~= nil, b.best ~= nil
        if aw ~= bw then return aw end
        -- Main-like characters (more Season 2 play and sustained activity)
        -- come first; their best current action breaks down what to do next.
        if a.engagement ~= b.engagement then return a.engagement > b.engagement end
        local as, bs = a.best and a.best.score or -1, b.best and b.best.score or -1
        if as ~= bs then return as > bs end
        -- At equal opportunity, the lower-geared character benefits more.
        if a.ilvl ~= b.ilvl then return a.ilvl < b.ilvl end
        return a.name < b.name
    end)

    tip:AddSeparator(2, 1, 1, 1, 0.6)
    local recHdr = tip:AddLine()
    tip:SetCell(recHdr, 1, Constants.COLOR_YELLOW .. "Weekly Game Plan" .. Constants.COLOR_RESET,
        GameFontNormal, "LEFT", numCols)
    tip:AddSeparator(1, 1, 1, 1, 0.25)
    local calibrationCount = 0
    local calibrationNames = {}
    for _, r in ipairs(recs) do
        if r.needsCalibration then
            calibrationCount = calibrationCount + 1
            calibrationNames[#calibrationNames + 1] = ClassColor(r.classFile)
                .. r.name .. Constants.COLOR_RESET
        end
    end
    local calibratedCount = #recs - calibrationCount
    if calibratedCount == 0 then
        local warning = tip:AddLine()
        tip:SetCell(warning, 1,
            Constants.COLOR_YELLOW .. "I can't guide your warband yet." .. Constants.COLOR_RESET,
            nil, "LEFT", numCols)
        local loginLine = tip:AddLine()
        tip:SetCell(loginLine, 1, Constants.COLOR_WHITE .. "Log into: " .. Constants.COLOR_RESET
            .. table.concat(calibrationNames, ", "), nil, "LEFT", numCols)
    else
        if calibrationCount > 0 then
            local hint = tip:AddLine()
            tip:SetCell(hint, 1,
                Constants.COLOR_GRAY .. "More paths unlock after you visit: " .. Constants.COLOR_RESET
                    .. table.concat(calibrationNames, ", "), nil, "LEFT", numCols)
            tip:AddSeparator(1, 0.3, 0.3, 0.3, 0.35)
        end
        local rankIndex = 0
        for _, r in ipairs(recs) do
          if not r.needsCalibration then
            rankIndex = rankIndex + 1
            local line = tip:AddLine()
            local rank = Constants.COLOR_GRAY .. rankIndex .. ". " .. Constants.COLOR_RESET
            tip:SetCell(line, 1, rank .. ClassColor(r.classFile) .. r.name .. Constants.COLOR_RESET)
            local action = r.best
                and (Constants.COLOR_WHITE .. r.best.text .. Constants.COLOR_RESET)
                or Constants.CHECK_GREEN
            tip:SetCell(line, 2, action, nil, "LEFT", numCols - 1)
          end
        end
    end

    -- The plan is the primary value of the addon, so show it before the detailed
    -- tracker grid. The grid remains the evidence behind each recommendation.
    -- Put the character roster's established endgame path first. This keeps the
    -- same grid for every alt while making the addon feel native to M+ players,
    -- raiders, or both instead of imposing one fixed activity hierarchy.
    local displayGroups = {}
    for _, grp in ipairs(Constants.GROUPS) do displayGroups[#displayGroups + 1] = grp end
    local groupPriority = { raidprogress = 0, mplus = 0 }
    for _, key in ipairs(charKeys) do
        local c = db.chars[key]
        groupPriority.raidprogress = groupPriority.raidprogress + Constants.GetActivityAffinity(c, "raid")
        groupPriority.mplus = groupPriority.mplus + Constants.GetActivityAffinity(c, "mplus")
    end
    if groupPriority.mplus > groupPriority.raidprogress then
        table.sort(displayGroups, function(a, b)
            if a.id == "mplus" then return true end
            if b.id == "mplus" then return false end
            if a.id == "raidprogress" then return true end
            if b.id == "raidprogress" then return false end
            local ai, bi
            for i, grp in ipairs(Constants.GROUPS) do
                if grp.id == a.id then ai = i end
                if grp.id == b.id then bi = i end
            end
            return (ai or 999) < (bi or 999)
        end)
    end
    for _, grp in ipairs(displayGroups) do
        renderGroup(grp.label, byGroup[grp.id] or {})
    end
    renderGroup("Other", ungrouped)

    -- Clickable footer that opens the tracked-characters config
    tip:AddSeparator(2, 1, 1, 1, 0.6)
    local footer = tip:AddLine()
    tip:SetCell(footer, 1,
        Constants.COLOR_GRAY .. "Click to choose tracked characters" .. Constants.COLOR_RESET,
        nil, "CENTER", numCols)
    tip:SetLineScript(footer, "OnMouseUp", function()
        local Config = _G[ADDON_NAME .. "Config"]
        if Config and Config.Open then Config:Open() end
    end)

    if anchorFrame then tip:SmartAnchorTo(anchorFrame) end
    tip:SetAutoHideDelay(0.25, anchorFrame)
    tip:Show()
end

function Tooltip:Hide()
    if self.tip then LibQTip:Release(self.tip); self.tip = nil end
end

_G[ADDON_NAME .. "Tooltip"] = Tooltip
