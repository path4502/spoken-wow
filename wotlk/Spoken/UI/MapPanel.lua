-- The place's story beside the world map, after upstream's Spoken_Places/UI/MapPanel.lua.
--
-- A parchment panel on the right of the map shows the story of the zone the map displays, with
-- Play and Stop, and the zone's subzones that have a story of their own. Clicking a subzone in
-- the list, or on the map itself, shows its story; "Back to <zone>" returns. A "Story" button at
-- the top of the map shows and hides the panel (db.mapPanel).

local ns = Spoken
local MapPanel = ns:RegisterModule("MapPanel", {})
ns.MapPanel = MapPanel

local Places = ns.Places
local WIDTH = 300
local ROWS = 12

local panel, toggle
local shown = {} -- { zoneID, zone, storyZone, key, entry }

local function MapZoneName()
	local continent, zone = GetCurrentMapContinent(), GetCurrentMapZone()
	if zone and zone > 0 and continent and continent > 0 then
		return (select(zone, GetMapZones(continent)))
	elseif continent and continent > 0 then
		return (select(continent, GetMapContinents()))
	end
	-- Cities and other maps outside the continent lists: the player's zone when the map is theirs.
	return GetRealZoneText()
end

local function SetStatus(mapID, key)
	if not Places:HasClip(mapID, key) then
		panel.status:SetText("|cff999999No recording installed|r")
		panel.play:Disable()
	else
		panel.play:Enable()
		panel.status:SetText(Places:Heard(mapID, key) and "|cff7fbf7fHeard|r" or "")
	end
end

local function ShowStory(title, text, mapID, key, entry)
	panel.title:SetText(title or "")
	panel.text:SetText(text and text ~= "" and text or "|cff999999No story is written for this place yet.|r")
	panel.scroll:SetVerticalScroll(0)
	panel.scroll:UpdateScrollChildRect()
	panel.mapID, panel.key, panel.entry = mapID, key, entry
	if mapID then SetStatus(mapID, key) else panel.status:SetText(""); panel.play:Disable() end
end

local function DrawList()
	local list = shown.zoneID and Places:SubzonesIn(shown.zoneID) or {}
	panel.list = list
	local offset = FauxScrollFrame_GetOffset(panel.listScroll)
	for i = 1, ROWS do
		local row = panel.rows[i]
		local item = list[i + offset]
		if item then
			row.item = item
			local heard = Places:Heard(item[1], item[2])
			local voiced = Places:HasClip(item[1], item[2])
			row.label:SetText((item[3].name or item[2]) .. (voiced and "" or " |cff999999(text)|r"))
			row.label:SetTextColor(heard and 0.55 or 0.25, heard and 0.45 or 0.18, heard and 0.35 or 0.05)
			if shown.key == item[2] then row:LockHighlight() else row:UnlockHighlight() end
			row:Show()
		else
			row.item = nil
			row:Hide()
		end
	end
	FauxScrollFrame_Update(panel.listScroll, #list, ROWS, 16)
	panel.listHeader:SetText(#list > 0 and "Places in this zone" or "")
end

function MapPanel:ShowZone()
	if not panel or not panel:IsShown() then return end
	local name = MapZoneName()
	local zoneID, entry = Places:ZoneByName(name)
	shown = { zoneID = zoneID, zone = name }
	panel.back:Hide()
	if zoneID then
		ShowStory(entry.name or name, entry.full or entry.short, zoneID, nil, entry)
	else
		ShowStory(name, nil)
	end
	DrawList()
end

function MapPanel:ShowSubzone(storyZone, key, entry)
	shown.storyZone, shown.key = storyZone, key
	ShowStory(entry.name or key, entry.full or entry.short, storyZone, key, entry)
	panel.back:SetText("< " .. (shown.zone or "Zone"))
	panel.back:Show()
	DrawList()
end

local function Button(parent, label, width)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetWidth(width); b:SetHeight(22)
	b:SetText(label)
	return b
end

local function Create()
	panel = CreateFrame("Frame", "SpokenMapStory", WorldMapDetailFrame)
	panel:SetWidth(WIDTH)
	panel:SetPoint("TOPRIGHT", WorldMapDetailFrame, "TOPRIGHT", -4, -4)
	panel:SetPoint("BOTTOMRIGHT", WorldMapDetailFrame, "BOTTOMRIGHT", -4, 4)
	panel:SetFrameLevel(WorldMapDetailFrame:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:SetBackdrop({
		bgFile = [[Interface\QuestFrame\QuestBG]],
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropBorderColor(0.6, 0.5, 0.35, 1)

	panel.back = CreateFrame("Button", nil, panel)
	panel.back:SetHeight(16)
	panel.back:SetWidth(WIDTH - 40)
	panel.back:SetPoint("TOPLEFT", 14, -10)
	local backText = panel.back:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	backText:SetPoint("LEFT")
	panel.back:SetFontString(backText)
	panel.back:SetScript("OnClick", function() MapPanel:ShowZone() end)

	local title = panel:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
	title:SetPoint("TOPLEFT", 14, -28)
	title:SetPoint("RIGHT", -14, 0)
	title:SetJustifyH("LEFT")
	title:SetTextColor(0.18, 0.12, 0.06)
	title:SetShadowColor(0, 0, 0, 0)
	panel.title = title

	panel.play = Button(panel, "Play", 70)
	panel.play:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	panel.play:SetScript("OnClick", function()
		if panel.mapID then
			local ok, why = Places:Play(panel.mapID, panel.key, panel.entry, true)
			if not ok and why == "queued" then ns:Print("already waiting in the queue.") end
		end
	end)
	panel.stop = Button(panel, "Stop", 70)
	panel.stop:SetPoint("LEFT", panel.play, "RIGHT", 4, 0)
	panel.stop:SetScript("OnClick", function() ns.Sound:Remove(nil, "place") end)
	panel.status = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	panel.status:SetPoint("LEFT", panel.stop, "RIGHT", 8, 0)

	-- The story, scrolling.
	local scroll = CreateFrame("ScrollFrame", "SpokenMapStoryScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", panel.play, "BOTTOMLEFT", 0, -10)
	scroll:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
	scroll:SetPoint("BOTTOM", panel, "BOTTOM", 0, ROWS * 16 + 40)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetWidth(WIDTH - 50); child:SetHeight(10)
	scroll:SetScrollChild(child)
	local text = child:CreateFontString(nil, "ARTWORK", "QuestFont")
	text:SetPoint("TOPLEFT")
	text:SetWidth(WIDTH - 50)
	text:SetJustifyH("LEFT")
	text:SetTextColor(0.18, 0.12, 0.06)
	text:SetSpacing(2)
	panel.text = text
	child:SetScript("OnUpdate", function(self)
		local h = text:GetHeight()
		if h and h > 0 and math.abs(self:GetHeight() - h) > 1 then
			self:SetHeight(h)
			scroll:UpdateScrollChildRect()
		end
	end)
	panel.scroll = scroll

	-- The zone's places.
	panel.listHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	panel.listHeader:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, ROWS * 16 + 14)
	panel.listHeader:SetTextColor(0.3, 0.2, 0.05)
	panel.listScroll = CreateFrame("ScrollFrame", "SpokenMapStoryList", panel, "FauxScrollFrameTemplate")
	panel.listScroll:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 10)
	panel.listScroll:SetWidth(WIDTH - 42); panel.listScroll:SetHeight(ROWS * 16)
	panel.listScroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, 16, DrawList)
	end)
	panel.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, panel)
		row:SetHeight(16)
		row:SetWidth(WIDTH - 42)
		row:SetPoint("TOPLEFT", panel.listScroll, "TOPLEFT", 4, -(i - 1) * 16)
		row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
		row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		row.label:SetPoint("LEFT", 4, 0)
		row.label:SetPoint("RIGHT", -4, 0)
		row.label:SetJustifyH("LEFT")
		row:SetScript("OnClick", function(self)
			if self.item then MapPanel:ShowSubzone(self.item[1], self.item[2], self.item[3]) end
		end)
		panel.rows[i] = row
	end

	panel:SetScript("OnShow", function() MapPanel:ShowZone() end)
	panel:Hide()
end

local function CreateToggle()
	toggle = CreateFrame("Button", "SpokenMapStoryToggle", WorldMapFrame, "UIPanelButtonTemplate")
	toggle:SetWidth(80); toggle:SetHeight(22)
	toggle:SetText("Story")
	toggle:SetPoint("BOTTOMRIGHT", WorldMapDetailFrame, "TOPRIGHT", 0, 4)
	toggle:SetFrameLevel(WorldMapDetailFrame:GetFrameLevel() + 25)
	toggle:SetScript("OnClick", function()
		ns.db.mapPanel = not ns.db.mapPanel
		MapPanel:Update()
	end)
	toggle:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("|cffb48cffSpoken|r")
		GameTooltip:AddLine("Show or hide the story of the place the map shows. Click a place on the map to read its own story.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function MapPanel:Update()
	if not panel then return end
	if ns.db.places and ns.db.mapPanel then
		panel:Show()
		self:ShowZone()
	else
		panel:Hide()
	end
	if ns.db.places then toggle:Show() else toggle:Hide() end
end

function MapPanel:Enable()
	if not WorldMapFrame or not WorldMapDetailFrame then return end
	Create()
	CreateToggle()
	self:Update()
	ns:On("WORLD_MAP_UPDATE", function()
		if WorldMapFrame:IsShown() then MapPanel:ShowZone() end
	end)
	-- Clicking a place on a zone's map shows its story; the label is what the map names there.
	if WorldMapButton then
		WorldMapButton:HookScript("OnMouseUp", function(_, button)
			if button ~= "LeftButton" or not panel:IsShown() then return end
			if (GetCurrentMapZone() or 0) == 0 then return end
			local label = WorldMapFrameAreaLabel and WorldMapFrameAreaLabel:GetText()
			if not label or label == "" then return end
			local storyZone, key, entry = Places:SubzoneOf(shown.zoneID, label)
			if storyZone then MapPanel:ShowSubzone(storyZone, key, entry) end
		end)
	end
	ns.Sound:Listen(function()
		if panel:IsShown() and panel.mapID then SetStatus(panel.mapID, panel.key); DrawList() end
	end)
end
