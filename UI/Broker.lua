local ADDON_NAME = "WoWWeekly"
local WoWWeekly  = _G[ADDON_NAME]
local Constants  = _G[ADDON_NAME .. "Constants"]

local Broker = {}

function Broker:Initialize()
    if self.ldb then return end
    self.ldb = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON_NAME, {
        type = "data source",
        text = "WoW Weekly",
        icon = "Interface\\Icons\\inv_misc_note_01",
        label = "WoW Weekly",
        OnEnter = function(frame)
            local Tooltip = _G[ADDON_NAME .. "Tooltip"]
            local Config = _G[ADDON_NAME .. "Config"]
            local limit = Config and Config.GetHoverCharacterLimit
                and Config:GetHoverCharacterLimit() or 5
            if Tooltip then Tooltip:Show(frame, false, limit) end
        end,
        OnLeave = function()
            local Tooltip = _G[ADDON_NAME .. "Tooltip"]
            if Tooltip and Tooltip.HideHover then Tooltip:HideHover() end
        end,
        OnClick = function(frame, button)
            if button == "RightButton" then
                local Tooltip = _G[ADDON_NAME .. "Tooltip"]
                if Tooltip then Tooltip:Hide() end
                local Config = _G[ADDON_NAME .. "Config"]
                if Config and Config.Open then Config:Open() end
            else
                local Tooltip = _G[ADDON_NAME .. "Tooltip"]
                if Tooltip and Tooltip.ToggleWindow then Tooltip:ToggleWindow() end
            end
        end,
    })

    local icon = LibStub("LibDBIcon-1.0", true)
    if icon then
        local options = WoWWeekly.db.profileOptions
        options.minimap = options.minimap or { hide = true }
        icon:Register(ADDON_NAME, self.ldb, options.minimap)
        self.icon = icon
    end
end

function Broker:SetMinimapShown(shown)
    local options = WoWWeekly.db.profileOptions
    options.minimap = options.minimap or {}
    options.minimap.hide = not shown
    if not self.icon then return end
    if shown and self.icon.Show then
        self.icon:Show(ADDON_NAME)
    elseif not shown and self.icon.Hide then
        self.icon:Hide(ADDON_NAME)
    elseif self.icon.Refresh then
        self.icon:Refresh(ADDON_NAME, options.minimap)
    elseif self.icon.SetIcon then
        -- Compatibility with the bundled lightweight implementation.
        self.icon:SetIcon(ADDON_NAME)
    end
end

function Broker:UpdateText()
    if not self.ldb then return end
    local Database = _G[ADDON_NAME .. "Database"]
    local charState = Database and Database:GetCharState()
    if not charState then return end

    local TrackerRegistry = _G[ADDON_NAME .. "TrackerRegistry"]
    local delves = TrackerRegistry:GetTracker(Constants.TRACKER_DELVES)
    if delves then
        self.ldb.text = "Delves " .. delves:GetSummary(charState)
    end
end

_G[ADDON_NAME .. "Broker"] = Broker
