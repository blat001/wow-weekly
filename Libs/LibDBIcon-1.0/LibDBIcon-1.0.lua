-- LibDBIcon-1.0: Minimal stub implementation for minimap icon support
local MAJOR, MINOR = "LibDBIcon-1.0", 1
local LibDBIcon = LibStub:NewLibrary(MAJOR, MINOR)

if not LibDBIcon then return end

LibDBIcon.objects = {}

function LibDBIcon:Register(name, dataobj, db)
	self.objects[name] = { dataobj = dataobj, db = db }
	self:SetIcon(name)
end

function LibDBIcon:Unregister(name)
	self.objects[name] = nil
end

function LibDBIcon:SetIcon(name)
	local obj = self.objects[name]
	if not obj then return end

	-- Create or update minimap button
	local btn = _G["LibDBIcon_Button_" .. name]
	if not btn then
		btn = CreateFrame("Button", "LibDBIcon_Button_" .. name, Minimap)
		btn:SetSize(33, 33)
		btn:SetFrameLevel(8)

		local overlay = btn:CreateTexture(nil, "OVERLAY")
		overlay:SetSize(20, 20)
		btn.overlay = overlay

		-- Position at minimap top-right
		btn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -5, -5)

		btn:SetScript("OnClick", function(self, button)
			if obj.dataobj.OnClick then
				obj.dataobj.OnClick(self, button)
			end
		end)

		btn:SetScript("OnEnter", function(self)
			if obj.dataobj.OnEnter then
				obj.dataobj.OnEnter(self)
			end
		end)

		btn:SetScript("OnLeave", function(self)
			if obj.dataobj.OnLeave then
				obj.dataobj.OnLeave(self)
			end
		end)

		btn.Border = btn:CreateTexture(nil, "BORDER")
		btn.Border:SetSize(37, 37)
		btn.Border:SetPoint("CENTER")
		btn.Border:SetTexture("Interface/Minimap/UI-Minimap-Border")
	end

	-- Update icon
	if obj.dataobj.icon then
		btn.overlay:SetTexture(obj.dataobj.icon)
		btn.overlay:SetPoint("CENTER", btn, "CENTER", 0, 0)
	end

	if obj.db and obj.db.hide then
		btn:Hide()
	else
		btn:Show()
	end
end

_G.LibDBIcon = LibDBIcon
