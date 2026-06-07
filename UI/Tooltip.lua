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

    -- Title row, centered across the whole table
    local titleLine = tip:AddHeader("")
    tip:SetCell(titleLine, 1, Constants.COLOR_YELLOW .. "WoW Weekly" .. Constants.COLOR_RESET, nil, "CENTER", numCols)
    tip:AddSeparator(1, 1, 1, 1, 0.4)

    -- Column-header row: "Task" label + each character in class color
    local hdr = tip:AddLine()
    tip:SetCell(hdr, 1, Constants.COLOR_GRAY .. "Task" .. Constants.COLOR_RESET)
    for i, key in ipairs(charKeys) do
        local c = db.chars[key]
        local label = c.name or key
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

    for _, grp in ipairs(Constants.GROUPS) do
        renderGroup(grp.label, byGroup[grp.id] or {})
    end
    -- Any tracker without a recognized group falls into a trailing "Other" section
    renderGroup("Other", ungrouped)

    -- Recommended: who to play next and what's left. For each character, collect
    -- incomplete weekly *goals* (trackers flagged countsForRecommend that are
    -- relevant to that character), then rank by unfinished vault slots, then ilvl.
    local recs = {}
    for _, key in ipairs(charKeys) do
        local c = db.chars[key]
        local vaultIncomplete = 0
        -- First pass: find every qualifying incomplete tracker for this char.
        local incByTracker, incList = {}, {}
        for _, t in pairs(TrackerRegistry:GetAll()) do
            if t.countsForRecommend then
                local enabled = true
                if Config and Config.IsTrackerEnabled then enabled = Config:IsTrackerEnabled(t.id) end
                local relevant = (t.IsRelevant == nil) or t:IsRelevant(c)
                -- Skip vault gear the character has outgeared (avg ilvl based)
                local worthwhile = (t.StopIlvl == nil)
                    or Constants.VaultWorthDoing(c, t:StopIlvl(c))
                if enabled and relevant and worthwhile and t.IsComplete and not t:IsComplete(c) then
                    incByTracker[t.id] = t
                    incList[#incList + 1] = t
                    if t.group == "vault" then vaultIncomplete = vaultIncomplete + 1 end
                end
            end
        end
        -- Second pass: build the to-do strings. Collapse REC_GROUPS members
        -- (e.g. delves) into one "Label (a, b, c)" entry listing only the
        -- incomplete ones; everything else stays standalone via GetAction.
        local remaining, grouped = {}, {}
        for _, rg in ipairs(Constants.REC_GROUPS or {}) do
            local shorts, seen = {}, {}
            local function addShort(s)
                if s and not seen[s] then seen[s] = true; shorts[#shorts + 1] = s end
            end
            for _, m in ipairs(rg.members) do
                local t = incByTracker[m.id]
                if t then
                    grouped[m.id] = true
                    -- RecTags-driven members (professions) contribute deduped
                    -- sub-task tags; fixed-short members (delves) contribute one.
                    if t.RecTags then
                        for _, tag in ipairs(t:RecTags(c)) do addShort(tag) end
                    else
                        addShort(m.short)
                    end
                end
            end
            if #shorts > 0 then
                remaining[#remaining + 1] = rg.label .. " (" .. table.concat(shorts, ", ") .. ")"
            end
        end
        for _, t in ipairs(incList) do
            if not grouped[t.id] then
                remaining[#remaining + 1] = (t.GetAction and t:GetAction(c)) or t.label
            end
        end
        recs[#recs + 1] = {
            name = c.name or key, classFile = c.classFile, ilvl = c.ilvl or 0,
            remaining = remaining, vaultIncomplete = vaultIncomplete,
        }
    end
    table.sort(recs, function(a, b)
        if a.vaultIncomplete ~= b.vaultIncomplete then return a.vaultIncomplete > b.vaultIncomplete end
        local ar, br = #a.remaining > 0, #b.remaining > 0
        if ar ~= br then return ar end                 -- chars with work above finished ones
        if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
        return a.name < b.name
    end)

    tip:AddSeparator(2, 1, 1, 1, 0.6)
    local recHdr = tip:AddLine()
    tip:SetCell(recHdr, 1, Constants.COLOR_YELLOW .. "Recommended" .. Constants.COLOR_RESET,
        GameFontNormal, "LEFT", numCols)
    tip:AddSeparator(1, 1, 1, 1, 0.25)
    for idx, r in ipairs(recs) do
        local line = tip:AddLine()
        -- Mark the single top pick (only if it actually has work to do)
        local lead = (idx == 1 and #r.remaining > 0)
            and (Constants.COLOR_YELLOW .. "> " .. Constants.COLOR_RESET) or "  "
        tip:SetCell(line, 1, lead .. ClassColor(r.classFile) .. r.name .. Constants.COLOR_RESET)
        local todo
        if #r.remaining == 0 then
            todo = Constants.COLOR_GREEN .. "all done" .. Constants.COLOR_RESET
        else
            todo = Constants.COLOR_WHITE .. table.concat(r.remaining, ", ") .. Constants.COLOR_RESET
        end
        tip:SetCell(line, 2, todo, nil, "LEFT", numCols - 1)
    end

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
