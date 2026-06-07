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
            if Tooltip then Tooltip:Show(frame) end
        end,
        OnClick = function(frame, button)
            local Config = _G[ADDON_NAME .. "Config"]
            if Config and Config.Open then Config:Open() end
        end,
    })
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
