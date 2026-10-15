local ADDON_NAME = "WoWWeekly"
local WoWWeekly  = _G[ADDON_NAME]
local Constants  = _G[ADDON_NAME .. "Constants"]
local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
local WeeklyReset = _G[ADDON_NAME .. "WeeklyReset"]
local LibQTip = LibStub("LibQTip-1.0")

local Tooltip = {}
local WINDOW_PAGE_SIZE = 6

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
local function OrderedCharKeys(db, maxCharacters)
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
    if Config and Config.SortCharacterKeys then
        Config:SortCharacterKeys(others, db.chars)
    else
        table.sort(others)
    end

    local keys = {}
    if currentKey and db.chars[currentKey] then keys[#keys + 1] = currentKey end  -- always first
    for _, k in ipairs(others) do keys[#keys + 1] = k end
    local limit = tonumber(maxCharacters)
    if limit and limit > 0 then
        limit = math.floor(limit)
        while #keys > limit do table.remove(keys) end
    end
    return keys
end

-- Planning estimates, not measured clear times. Group activities include setup.
local function UpcomingRaid(st)
    local calendar = st.calendar
    if not (calendar and calendar.state == "scheduled" and calendar.startTime
        and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
        and C_DateAndTime.AdjustTimeByMinutes and C_DateAndTime.CompareCalendarTime) then return false end
    local now = C_DateAndTime.GetCurrentCalendarTime()
    return C_DateAndTime.CompareCalendarTime(calendar.startTime, now) >= 0
        and C_DateAndTime.CompareCalendarTime(calendar.startTime,
            C_DateAndTime.AdjustTimeByMinutes(now, 120)) <= 0
end

function Tooltip:PlanEffort(id, c, bonusRemaining)
    local st = c.trackers[id] or {}
    local thresholds, progress, perRun, setup, reward
    if id == Constants.TRACKER_DELVES or id == Constants.TRACKER_MYTHICPLUS then
        local dungeon = id == Constants.TRACKER_MYTHICPLUS
        thresholds = dungeon and {1, 4, 8} or {2, 4, 8}
        progress = Constants.IsMidnightSeason2Active()
            and st.qualifiedRuns and math.max(st.qualifiedRuns, st.count or 0)
            or (not Constants.IsMidnightSeason2Active() and st.rawProgress or nil)
        perRun, setup, reward = dungeon and 40 or 20, dungeon and 15 or 0, dungeon and 318 or 305
    elseif id == Constants.TRACKER_RAID then
        thresholds, progress, perRun, setup = {2, 4, 6}, st.rawProgress, 20, UpcomingRaid(st) and 0 or 45
    end
    local minutes
    if thresholds then
        local remaining = bonusRemaining
        if not remaining and progress then
            for _, threshold in ipairs(thresholds) do
                if progress < threshold then remaining = threshold - progress break end
            end
        end
        minutes = remaining and (remaining * perRun + setup)
        local delve = _G[ADDON_NAME .. "DelveTracker"]
        if id == Constants.TRACKER_DELVES and not bonusRemaining
            and delve and delve.GetLabyrinthAction and delve:GetLabyrinthAction(c) then
            -- Conservative estimate: a full Labyrinth is three Delve credits.
            minutes = 3 * perRun
        end
    elseif id == Constants.TRACKER_BOUNTYMAP then
        minutes = st.state == "inbags" and 20 or nil
        reward = 305
    elseif id == Constants.TRACKER_GILDEDSTASH then
        minutes = st.looted ~= nil and 25 or nil -- next stash, not every remaining stash
        reward = 305
    elseif id == Constants.TRACKER_PROFESSION1 or id == Constants.TRACKER_PROFESSION2 then
        minutes = st.weeklyDone == false and (15 + (st.treatiseDone == false and 5 or 0))
            or (st.treatiseDone == false and 5 or nil)
    elseif id == Constants.TRACKER_TIMEWALKING then
        minutes = st.cur and st.max and (math.max(1, st.max - st.cur) * 25 + 10)
    elseif id == Constants.TRACKER_COILEDISLE_WORLDBOSS then
        minutes = 15
    end
    -- A ready turn-in is a short, meaningful completion even for an otherwise
    -- unestimated quest. Do not convert arbitrary quest points into minutes.
    if not minutes and st.cur and st.max and st.max > 0 and st.cur >= st.max then minutes = 5 end
    local urgent = id == Constants.TRACKER_RAID and UpcomingRaid(st) or false
    if st.expiresAt and st.expiresAt > time() and st.expiresAt - time() <= 7200 then urgent = true end
    reward = st.rewardIlvl or reward
    local gain = reward and (c.ilvl or 0) > 0 and math.max(0, reward - c.ilvl) or 0
    return minutes, gain, urgent
end

local function BetterAction(a, b)
    if not b then return true end
    if not not a.urgent ~= not not b.urgent then return a.urgent == true end
    -- Ten-minute bands avoid pretending these broad estimates are exact.
    local ae, be = math.ceil((a.minutes or math.huge) / 10), math.ceil((b.minutes or math.huge) / 10)
    if ae ~= be then return ae < be end
    if (a.gain or 0) ~= (b.gain or 0) then return (a.gain or 0) > (b.gain or 0) end
    if (a.score or 0) ~= (b.score or 0) then return (a.score or 0) > (b.score or 0) end
    return (a.id or "") < (b.id or "")
end

function Tooltip:Show(anchorFrame, persistent, maxCharacters)
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

    local allCharKeys = OrderedCharKeys(db, maxCharacters)
    if #allCharKeys == 0 then return end

    local charKeys = allCharKeys
    local pageCount = 1
    if persistent and #allCharKeys > WINDOW_PAGE_SIZE then
        -- Keep the logged-in character visible while paging through the alts.
        local altsPerPage = WINDOW_PAGE_SIZE - 1
        pageCount = math.ceil((#allCharKeys - 1) / altsPerPage)
        self.page = math.max(1, math.min(pageCount, self.page or 1))
        charKeys = { allCharKeys[1] }
        local firstAlt = 2 + (self.page - 1) * altsPerPage
        local lastAlt = math.min(#allCharKeys, firstAlt + altsPerPage - 1)
        for i = firstAlt, lastAlt do charKeys[#charKeys + 1] = allCharKeys[i] end
    else
        self.page = 1
    end

    -- Keep at least three physical columns so the game plan can always show
    -- Character | Next Step | Raid Plan, even when only one character is shown.
    local numCols = math.max(3, 1 + #charKeys)
    if self.tip then LibQTip:Release(self.tip); self.tip = nil end

    local just = {"LEFT"}
    for i = 2, numCols do just[#just+1] = "CENTER" end

    local tip = LibQTip:Acquire(ADDON_NAME .. "Tip", numCols, unpack(just))
    self.tip = tip
	if tip.SetBackdropColor then tip:SetBackdropColor(0.02, 0.015, 0.03, 0.96) end

    -- Title row, centered across the whole table
    local titleLine = tip:AddHeader("")
    local titleText = "WoW Weekly"
    if persistent and pageCount > 1 then
        titleText = string.format("WoW Weekly (Page %d of %d)", self.page, pageCount)
    end
    if persistent then
        tip:SetCell(titleLine, 1, Constants.COLOR_YELLOW .. titleText .. Constants.COLOR_RESET,
            nil, "CENTER", numCols - 1)
        tip:SetCell(titleLine, numCols, Constants.COLOR_WHITE .. "X" .. Constants.COLOR_RESET,
            nil, "RIGHT")
        tip:SetCellScript(titleLine, numCols, "OnMouseUp", function()
            self:Hide()
        end)
    else
        tip:SetCell(titleLine, 1, Constants.COLOR_YELLOW .. titleText .. Constants.COLOR_RESET,
            nil, "CENTER", numCols)
    end
    tip:AddSeparator(1, 1, 1, 1, 0.4)

    -- Collect enabled trackers, bucketed by their declared group
    local Config = _G[ADDON_NAME .. "Config"]
    local byGroup, ungrouped = {}, {}
    for _, t in pairs(TrackerRegistry:GetAll()) do
        local enabled = true
        if Config and Config.IsTrackerEnabled then enabled = Config:IsTrackerEnabled(t.id) end
        local visible = true
        if t.IsVisible then
            visible = false
            for _, key in ipairs(charKeys) do
                if t:IsVisible(db.chars[key]) then
                    visible = true
                    break
                end
            end
        end
        if enabled and visible then
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

    -- Select the nearest meaningful reward inside each character's goals.
    local activityForTracker = {
        [Constants.TRACKER_DELVES] = "delves",
        [Constants.TRACKER_GILDEDSTASH] = "delves",
        [Constants.TRACKER_BOUNTYMAP] = "delves",
        [Constants.TRACKER_MYTHICPLUS] = "mplus",
        [Constants.TRACKER_PROFESSION1] = "professions",
        [Constants.TRACKER_PROFESSION2] = "professions",
    }

    local function actionScore(t, c)
        local st = c.trackers[t.id] or {}
        local rank = Config and Config.GetRecommendationRank
            and Config:GetRecommendationRank(t.id) or 999
        -- Existing activity preferences break ties after urgency, effort and gear.
        local score = 100000 - rank * 100
        if t.id == Constants.TRACKER_MYTHICPLUS and st.hasRuns then
            score = score + math.min(50, st.rawProgress or 0)
        elseif t.id == Constants.TRACKER_BOUNTYMAP and st.state == "inbags" then
            score = score + 50
        elseif t.id == Constants.TRACKER_METAQUEST and (st.cur or 0) > 0 then
            score = score + math.min(50, st.cur or 0)
        elseif t.id == Constants.TRACKER_DELVES and (st.rawProgress or 0) > 0 then
            score = score + math.min(50, st.rawProgress or 0)
        elseif t.id == Constants.TRACKER_TIMEWALKING and (st.cur or 0) > 0 then
            score = score + math.min(50, st.cur or 0)
        elseif t.id == Constants.TRACKER_GILDEDSTASH and (st.looted or 0) > 0 then
            score = score + math.min(50, st.looted or 0)
        end
        local activity = activityForTracker[t.id]
        if activity then
            score = score + math.min(40, Constants.GetActivityAffinity(c, activity) * 10)
        end
        return score
    end

    local showGamePlan = not (Config and Config.IsGamePlanShown) or Config:IsGamePlanShown()
    local showNextStep = not (Config and Config.IsNextStepShown) or Config:IsNextStepShown()
    local showRaidPlan = not (Config and Config.IsRaidPlanShown) or Config:IsRaidPlanShown()
    local recs = {}
    for _, key in ipairs(OrderedCharKeys(db)) do
        local c = db.chars[key]
        local focus, goalLabel = "balanced", nil
        if Config and Config.GetCharacterGoal then focus, goalLabel = Config:GetCharacterGoal(c) end
        local function hasGoal(wanted)
            return Config and Config.HasCharacterGoal and Config:HasCharacterGoal(c, wanted) or focus == wanted
        end
        local bonusEnabled = Config and Config.IsCharacterBonusRollEnabled and Config:IsCharacterBonusRollEnabled(c)
        local best
        local bestDelveOrDungeon
        local labyrinthCandidate
        local raidPlan
        local raidNeedsWork = false
        local eligibleCount, targetMet = 0, false
        for _, t in pairs(TrackerRegistry:GetAll()) do
            if t.id == Constants.TRACKER_RAID then
                local st = c.trackers[t.id] or {}
                local calendarState = st.calendar and st.calendar.state
                local followsRaid = hasGoal("raid") or st.hasKills or calendarState == "scheduled"
                    or calendarState == "pending" or Constants.GetActivityAffinity(c, "raid") >= 0.5
                local raidTarget = Config and Config.GetVaultGoalThreshold
                    and Config:GetVaultGoalThreshold(c, t.id) or Constants.RAID_FULL_THRESHOLD
                local raidEnough = (st.count or 0) >= raidTarget
                local raidRelevant = not t.IsRecommendationRelevant or t:IsRecommendationRelevant(c)
                if hasGoal("raid") and (raidRelevant or raidEnough) then
                    eligibleCount = eligibleCount + 1
                    targetMet = targetMet or (raidEnough and not t:IsComplete(c))
                    raidNeedsWork = not raidEnough
                end
                local raidAllowed = not (Config and Config.GoalAllowsTracker) or Config:GoalAllowsTracker(c, t.id)
                raidAllowed = raidAllowed and raidRelevant
                if showRaidPlan and raidAllowed and followsRaid and not raidEnough then
                    raidPlan = (t.GetRaidGoal and t:GetRaidGoal(c))
                        or (t.GetAction and t:GetAction(c)) or t.label
                    local minutes, gain, urgent = self:PlanEffort(t.id, c)
                    local candidate = { id = t.id, text = raidPlan, minutes = minutes, gain = gain,
                        urgent = urgent, score = actionScore(t, c) }
                    if showNextStep and BetterAction(candidate, best) then best = candidate end
                end
            elseif showNextStep and t.countsForRecommend then
                local recommendEnabled = not (Config and Config.IsRecommendationEnabled)
                    or Config:IsRecommendationEnabled(t.id)
                recommendEnabled = recommendEnabled and (not (Config and Config.GoalAllowsTracker)
                    or Config:GoalAllowsTracker(c, t.id))
                local relevant = (t.IsRelevant == nil) or t:IsRelevant(c)
                -- A decaying history can make established M+ characters
                -- relevant before they begin that activity in the current week.
                local activity = activityForTracker[t.id]
                if not relevant and activity == "mplus" then
                    relevant = hasGoal("mplus") or Constants.GetActivityAffinity(c, activity) >= 0.5
                end
                local worthwhile = (t.StopIlvl == nil)
                    or Constants.VaultWorthDoing(c, t:StopIlvl(c))
                if hasGoal("delves") then worthwhile = true end
                if worthwhile and t.id == Constants.TRACKER_GILDEDSTASH
                    and Config and Config.GetMaxDelveTier
                    and Config:GetMaxDelveTier() < 11 then
                    worthwhile = false
                end
                if recommendEnabled and relevant and worthwhile then
                    eligibleCount = eligibleCount + 1
                    if t.IsGoalMet and t:IsGoalMet(c) and not t:IsComplete(c) then
                        targetMet = true
                    end
                end
                if recommendEnabled and relevant and worthwhile
                    and t.IsComplete and not t:IsComplete(c)
                    and not (t.IsGoalMet and t:IsGoalMet(c)) then
                    local score = actionScore(t, c)
                    local minutes, gain, urgent = self:PlanEffort(t.id, c)
                    local candidate = {
                            score = score,
                            minutes = minutes, gain = gain, urgent = urgent,
                            order = t.order or 999,
                            id = t.id,
                            activity = activity,
                            text = (t.GetAction and t:GetAction(c)) or t.label,
                        }
                    if BetterAction(candidate, best) then best = candidate end
					if t.id == Constants.TRACKER_DELVES and t.GetLabyrinthAction
						and t:GetLabyrinthAction(c) then labyrinthCandidate = candidate end
					if activity == "delves" or activity == "mplus" then
						if BetterAction(candidate, bestDelveOrDungeon) then
							bestDelveOrDungeon = candidate
						end
					end
                end
            end
        end
		local meta = c.trackers[Constants.TRACKER_METAQUEST] or {}
		local trailing = (not Config or not Config.IsRecommendationEnabled
			or Config:IsRecommendationEnabled(Constants.TRACKER_METAQUEST)) and not meta.done
			and (meta.qid == 98172 or meta.name == "Trailing Xal'atath")
		if trailing and best and best.id == Constants.TRACKER_METAQUEST
			and bestDelveOrDungeon then
			best = bestDelveOrDungeon
		end
		if trailing and best and (best.activity == "delves" or best.activity == "mplus") then
			local remaining = meta.cur and meta.max
				and math.max(0, meta.max - meta.cur) or 100
			best.text = string.format("%s; collect Fading Voidwhispers along the way (%d remaining)",
				best.text, remaining)
		end
        -- Prefer the Labyrinth's World progress before farming a new Bounty
        -- Map through Purging. An already-owned map keeps its normal priority.
        if labyrinthCandidate and best and best.id == Constants.TRACKER_BOUNTYMAP
            and (c.trackers[Constants.TRACKER_BOUNTYMAP] or {}).state ~= "inbags"
            and not best.urgent then
            best = labyrinthCandidate
        end
        local combinedSlots, bonusAction
        if Config and Config.GetCombinedVaultProgress then
            combinedSlots, bonusAction = Config:GetCombinedVaultProgress(c)
        end
        if not best and raidNeedsWork then
            best = { unavailable = not showRaidPlan, text = showRaidPlan and "See Raid Goals for your next step"
                or "Enable Raid Goals to see your next step" }
        end
        if bonusEnabled and not best then
            if (combinedSlots or 0) >= 3 then
                best = { text = "Selected weekly targets met", complete = true }
            elseif bonusAction then
                local minutes, gain, urgent = self:PlanEffort(bonusAction.id, c, bonusAction.remaining)
                best = { minutes = minutes, gain = gain, urgent = urgent, id = bonusAction.id,
                    text = string.format("Complete %d more %s for another Vault slot (%d/3 filled across all rows)",
                    bonusAction.remaining, bonusAction.noun, combinedSlots or 0) }
            else
                best = { unavailable = true, text = string.format("%d/3 Vault slots filled; enable a Vault activity to get suggestions", combinedSlots or 0) }
            end
        end
        recs[#recs + 1] = {
            key = key,
            name = c.name or key,
            classFile = c.classFile,
            ilvl = c.ilvl or 0,
            best = best,
            goalLabel = goalLabel,
            combinedSlots = combinedSlots,
            bonusEnabled = bonusEnabled,
            focus = focus,
            eligibleCount = eligibleCount,
            targetMet = targetMet,
            raidPlan = raidPlan,
            needsCalibration = c.playedSeason ~= Constants.MIDNIGHT_SEASON_KEY,
        }
    end
    table.sort(recs, function(a, b)
        local function status(r)
            if r.needsCalibration then return 2 end
            if r.best and not r.best.complete and not r.best.unavailable then return 1 end
            if r.best and r.best.unavailable then return 3 end
            if r.targetMet or (r.best and r.best.complete) or r.eligibleCount > 0 then return 4 end
            return 3
        end
        if status(a) ~= status(b) then return status(a) < status(b) end
        if status(a) == 1 then
            if BetterAction(a.best, b.best) then return true end
            if BetterAction(b.best, a.best) then return false end
        end
        return a.key < b.key
    end)
    -- Page the ranking independently; the status columns retain their order.
    local firstRec, lastRec = 1, #recs
    if persistent and pageCount > 1 then
        firstRec = (self.page - 1) * (WINDOW_PAGE_SIZE - 1) + 1
        lastRec = self.page == pageCount and #recs or math.min(#recs, firstRec + WINDOW_PAGE_SIZE - 2)
    elseif maxCharacters and maxCharacters > 0 then
        lastRec = math.min(#recs, maxCharacters)
    end
    if showGamePlan and (showNextStep or showRaidPlan) then
        local function addPlanHeader(title, r, g, b)
            tip:AddSeparator(2, 1, 1, 1, 0.55)
            local header = tip:AddLine()
            tip:SetCell(header, 1, Constants.COLOR_YELLOW .. title .. Constants.COLOR_RESET,
                GameFontNormal, "LEFT", numCols)
            tip:SetLineColor(header, r, g, b, 0.72)
            tip:AddSeparator(1, 1, 1, 1, 0.22)
        end

        local function addPlanRow(r, text, red, green, blue)
            local line = tip:AddLine()
            tip:SetCell(line, 1, ClassColor(r.classFile) .. r.name .. Constants.COLOR_RESET,
                nil, "LEFT")
            tip:SetCell(line, 2, text, nil, "LEFT", numCols - 1, nil,
                8, 4, 720, 360)
            SetCellVJust(line, 1, "TOP")
            SetCellVJust(line, 2, "TOP")
            tip:SetLineColor(line, red, green, blue, 0.5)
        end

        if showNextStep then
            addPlanHeader("Play Next", 0.04, 0.12, 0.20)
            for index = firstRec, lastRec do
                local r = recs[index]
                local action
                if r.needsCalibration then
                    action = Constants.COLOR_GRAY .. "Log in to calibrate recommendations" .. Constants.COLOR_RESET
                elseif r.best then
                    action = Constants.COLOR_WHITE .. r.best.text .. Constants.COLOR_RESET
                    if r.best.urgent then
                        action = action .. Constants.COLOR_YELLOW .. " (time-sensitive)" .. Constants.COLOR_RESET
                    elseif r.best.minutes then
                        action = action .. Constants.COLOR_GRAY .. string.format(" (~%d min estimated)", r.best.minutes) .. Constants.COLOR_RESET
                    elseif not r.best.complete and not r.best.unavailable then
                        action = action .. Constants.COLOR_GRAY .. " (time estimate unavailable)" .. Constants.COLOR_RESET
                    end
                elseif r.targetMet then
                    action = Constants.COLOR_GREEN .. "Weekly targets met (more Vault slots available)" .. Constants.COLOR_RESET
                elseif r.eligibleCount > 0 then
                    action = Constants.CHECK_GREEN .. " Eligible activities complete"
                else
                    action = Constants.COLOR_GRAY .. "No eligible recommendations" .. Constants.COLOR_RESET
                end
                if r.goalLabel then
                    action = Constants.COLOR_YELLOW .. r.goalLabel .. Constants.COLOR_RESET .. ": " .. action
                end
                if r.bonusEnabled and (r.combinedSlots or 0) >= 3 then
                    action = action .. Constants.COLOR_GREEN .. "; bonus-roll option unlocked for next Vault" .. Constants.COLOR_RESET
                elseif r.bonusEnabled then
                    action = action .. Constants.COLOR_GRAY .. string.format("; bonus-roll target: %d/3 slots", r.combinedSlots or 0) .. Constants.COLOR_RESET
                end
                addPlanRow(r, action, 0.025, 0.075, 0.12)
            end
        end

        if showRaidPlan then
            addPlanHeader("Raid Goals", 0.12, 0.055, 0.16)
            local raidRows = 0
            for index = firstRec, lastRec do
                local r = recs[index]
                if r.raidPlan then
                    raidRows = raidRows + 1
                    addPlanRow(r, Constants.COLOR_WHITE .. r.raidPlan .. Constants.COLOR_RESET,
                        0.075, 0.035, 0.10)
                end
            end
            if raidRows == 0 then
                local line = tip:AddLine()
                tip:SetCell(line, 1, Constants.COLOR_GRAY .. "No active raid goals" .. Constants.COLOR_RESET,
                    nil, "LEFT", numCols)
            end
        end
    end

    -- The plan is the primary value of the addon, so show it before the detailed
    -- tracker grid. The grid remains the evidence behind each recommendation.
    tip:AddSeparator(2, 1, 1, 1, 0.65)
    local statusHdr = tip:AddLine()
    tip:SetCell(statusHdr, 1, Constants.COLOR_YELLOW .. "Weekly Status" .. Constants.COLOR_RESET,
        GameFontNormal, "LEFT", numCols)
    tip:SetLineColor(statusHdr, 0.055, 0.055, 0.065, 0.72)
    tip:AddSeparator(1, 1, 1, 1, 0.22)
    local statusColumns = tip:AddLine()
    tip:SetCell(statusColumns, 1, Constants.COLOR_GRAY .. "Task" .. Constants.COLOR_RESET)
    for i, key in ipairs(charKeys) do
        local c = db.chars[key]
        local label = CharacterHeaderLabel(c, key)
        if WeeklyReset:IsWeekStale(key) then
            label = Constants.COLOR_GRAY .. label .. " (old)" .. Constants.COLOR_RESET
        else
            label = ClassColor(c.classFile) .. label .. Constants.COLOR_RESET
        end
        tip:SetCell(statusColumns, i + 1, label, GameFontNormal, "CENTER")
    end

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
        local label = grp.id == "raidprogress" and ("Raid: " .. Constants.CURRENT_RAID_NAME) or grp.label
        renderGroup(label, byGroup[grp.id] or {})
    end
    renderGroup("Other", ungrouped)

    if persistent and pageCount > 1 then
        tip:AddSeparator(2, 1, 1, 1, 0.6)
        local pager = tip:AddLine()
        local previous = self.page > 1
            and Constants.COLOR_WHITE .. "< Previous" .. Constants.COLOR_RESET
            or Constants.COLOR_GRAY .. "< Previous" .. Constants.COLOR_RESET
        local nextPage = self.page < pageCount
            and Constants.COLOR_WHITE .. "Next >" .. Constants.COLOR_RESET
            or Constants.COLOR_GRAY .. "Next >" .. Constants.COLOR_RESET
        tip:SetCell(pager, 1, previous, nil, "LEFT")
        tip:SetCell(pager, 2,
            Constants.COLOR_YELLOW .. "Page " .. self.page .. " of " .. pageCount .. Constants.COLOR_RESET,
            nil, "CENTER", numCols - 2)
        tip:SetCell(pager, numCols, nextPage, nil, "RIGHT")
        if self.page > 1 then
            tip:SetCellScript(pager, 1, "OnMouseUp", function()
                self.page = self.page - 1
                self:Show(nil, true)
            end)
        end
        if self.page < pageCount then
            tip:SetCellScript(pager, numCols, "OnMouseUp", function()
                self.page = self.page + 1
                self:Show(nil, true)
            end)
        end
    end

    -- Clickable footer that opens the tracked-characters config
    tip:AddSeparator(2, 1, 1, 1, 0.6)
    local footer = tip:AddLine()
    tip:SetCell(footer, 1,
        Constants.COLOR_GRAY .. "Click to choose tracked characters" .. Constants.COLOR_RESET,
        nil, "CENTER", numCols)
    tip:SetLineScript(footer, "OnMouseUp", function()
        self:Hide()
        local Config = _G[ADDON_NAME .. "Config"]
        if Config and Config.Open then Config:Open() end
    end)

    if persistent then
        tip:ClearAllPoints()
        tip:SetPoint("CENTER", UIParent, "CENTER")
        tip:SetClampedToScreen(true)
        tip:SetAutoHideDelay(nil)
        self.windowOpen = true
    else
        if anchorFrame then tip:SmartAnchorTo(anchorFrame) end
        tip:SetAutoHideDelay(0.25, anchorFrame)
        self.windowOpen = false
    end
    tip:Show()
end

function Tooltip:ToggleWindow()
    if self.windowOpen and self.tip and self.tip:IsShown() then
        self:Hide()
    else
        self.page = 1
        self:Show(nil, true)
    end
end

function Tooltip:HideHover()
    if not self.windowOpen then self:Hide() end
end

function Tooltip:Hide()
    if self.tip then LibQTip:Release(self.tip); self.tip = nil end
    self.windowOpen = false
end

_G[ADDON_NAME .. "Tooltip"] = Tooltip
