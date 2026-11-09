-- The settings page (Interface > AddOns > Spoken), the minimap button, key bindings and
-- the slash commands.

local ns = Spoken
local Options = ns:RegisterModule("Options", {})

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local counter = 0
local function Name(prefix)
	counter = counter + 1
	return "SpokenOptions" .. prefix .. counter
end

local refreshers = {}

local function Check(parent, label, tip, get, set)
	local cb = CreateFrame("CheckButton", Name("Check"), parent, "InterfaceOptionsCheckButtonTemplate")
	_G[cb:GetName() .. "Text"]:SetText(label)
	cb.tooltipText = label
	cb.tooltipRequirement = tip
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	table.insert(refreshers, function() cb:SetChecked(get()) end)
	return cb
end

local function Slider(parent, label, min, max, step, fmt, get, set)
	local s = CreateFrame("Slider", Name("Slider"), parent, "OptionsSliderTemplate")
	s:SetWidth(200)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	_G[s:GetName() .. "Low"]:SetText(format(fmt, min))
	_G[s:GetName() .. "High"]:SetText(format(fmt, max))
	local text = _G[s:GetName() .. "Text"]
	s:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value / step + 0.5) * step
		text:SetText(label .. ": " .. format(fmt, value))
		if self.ready then set(value) end
	end)
	table.insert(refreshers, function()
		s.ready = nil
		s:SetValue(get())
		text:SetText(label .. ": " .. format(fmt, get()))
		s.ready = true
	end)
	return s
end

local function Dropdown(parent, label, choices, get, set)
	local dd = CreateFrame("Frame", Name("Dropdown"), parent, "UIDropDownMenuTemplate")
	local title = dd:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 3)
	title:SetText(label)
	UIDropDownMenu_SetWidth(dd, 180)
	UIDropDownMenu_Initialize(dd, function()
		for _, choice in ipairs(choices) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = choice[2]
			info.value = choice[1]
			info.checked = get() == choice[1]
			info.func = function()
				set(choice[1])
				UIDropDownMenu_SetSelectedValue(dd, choice[1])
				UIDropDownMenu_SetText(dd, choice[2])
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
	table.insert(refreshers, function()
		for _, choice in ipairs(choices) do
			if choice[1] == get() then
				UIDropDownMenu_SetSelectedValue(dd, choice[1])
				UIDropDownMenu_SetText(dd, choice[2])
			end
		end
	end)
	return dd
end

local function Header(parent, text)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetText(text)
	return fs
end

local function DB(key) return function() return ns.db[key] end, function(v) ns.db[key] = v end end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------

local panel

local function Build()
	panel = CreateFrame("Frame", "SpokenOptionsPanel", UIParent)
	panel.name = "Spoken"

	local scroll = CreateFrame("ScrollFrame", "SpokenOptionsScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local page = CreateFrame("Frame", nil, scroll)
	page:SetWidth(560); page:SetHeight(900)
	scroll:SetScrollChild(page)

	local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -10)
	title:SetText("|cffb48cffSpoken|r " .. ns.version)
	local sub = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetWidth(520)
	sub:SetJustifyH("LEFT")
	page.packs = sub

	local y = -64
	local function Place(widget, x, dy)
		widget:SetPoint("TOPLEFT", page, "TOPLEFT", x or 16, y)
		y = y - (dy or 26)
		return widget
	end

	Place(Header(page, "Narrator"), 16, 30)
	Place(Dropdown(page, "Show a line as", {
		{ "subtitles", "Subtitles" }, { "window", "Small window" }, { "voice", "Voice only" },
	}, function() return ns.db.style end, function(v)
		ns.db.style = v
		ns.Narrator:Refresh()
	end), 0, 36)
	Place(Check(page, "Type words out", "Type the subtitles in as the voice reads them, instead of showing them whole.", DB("typeWords")))
	Place(Check(page, "Show the words in the small window", nil, DB("windowShowText")))
	y = y - 14
	Place(Slider(page, "Subtitle size", 0.6, 1.6, 0.05, "%.2f", function() return ns.db.subtitleScale end, function(v)
		ns.db.subtitleScale = v
		ns.Narrator:ApplySubtitleSettings()
	end), 24, 40)
	Place(Slider(page, "Subtitle shadow", 0, 1, 0.05, "%.2f", function() return ns.db.subtitleShadow end, function(v)
		ns.db.subtitleShadow = v
		ns.Narrator:ApplySubtitleSettings()
	end), 24, 34)
	local move = CreateFrame("Button", Name("Button"), page, "UIPanelButtonTemplate")
	move:SetWidth(140); move:SetHeight(22)
	move:SetText("Move subtitles")
	move:SetScript("OnClick", function() ns.Narrator:MoveSubtitles() end)
	Place(move, 24, 34)

	Place(Header(page, "Sound"), 16, 30)
	Place(Check(page, "Play on the music channel (can be stopped)",
		"3.3.5 cannot stop a sound once it starts. Played as music, a line can be stopped and skipped; the game music fades out while it plays.",
		DB("playOnMusicChannel")))
	y = y - 14
	Place(Slider(page, "Voice volume", 0, 1, 0.05, "%.2f", function() return ns.db.volume end, function(v) ns.db.volume = v end), 24, 40)
	Place(Slider(page, "Music fade (seconds)", 0, 3, 0.25, "%.2f", function() return ns.db.fadeMusic end, function(v) ns.db.fadeMusic = v end), 24, 34)
	Place(Slider(page, "Lines waiting at most", 1, 20, 1, "%d", function() return ns.db.maxQueue end, function(v) ns.db.maxQueue = v end), 24, 34)

	Place(Header(page, "Quests and gossip"), 16, 30)
	Place(Check(page, "Quests", "Read quest text aloud when a quest window opens.", DB("autoplayQuests")))
	Place(Check(page, "Gossip", "Read what an NPC says when you talk to it.", DB("gossip")))
	y = y - 18
	Place(Dropdown(page, "Gossip is read", {
		{ "always", "Every time" }, { "questnpc", "Once per NPC with quests" }, { "npc", "Once per NPC" }, { "never", "Never" },
	}, function() return ns.db.gossipFrequency end, function(v) ns.db.gossipFrequency = v end), 0, 36)
	Place(Check(page, "Follow-up lines", "What an NPC says in chat after you accept or hand in a quest.", DB("followups")))
	Place(Check(page, "World chatter", "What NPCs say out loud around you.", DB("chatter")))
	Place(Check(page, "Stop when the window closes", nil, DB("stopOnClose")))
	Place(Check(page, "Play button in the quest log", nil, DB("questLogButton")))

	Place(Header(page, "Readables"), 16, 30)
	Place(Check(page, "Read books and letters aloud", nil, DB("autoplayReadables")))
	Place(Check(page, "Read the whole book, not just the page", nil, DB("readWholeBook")))
	Place(Check(page, "Stop when the book closes", nil, DB("stopBookOnClose")))

	Place(Header(page, "Places"), 16, 30)
	Place(Check(page, "Tell a zone's story the first time you enter it", nil, DB("autoplayZones")))
	Place(Check(page, "Tell a subzone's story the first time you enter it", nil, DB("autoplaySubzones")))
	Place(Check(page, "Also in combat", nil, DB("placesInCombat")))
	Place(Check(page, "Story panel on the world map", nil, function() return ns.db.mapPanel end, function(v)
		ns.db.mapPanel = v
		ns.MapPanel:Update()
	end))
	local forget = CreateFrame("Button", Name("Button"), page, "UIPanelButtonTemplate")
	forget:SetWidth(200); forget:SetHeight(22)
	forget:SetText("Forget places heard")
	forget:SetScript("OnClick", function()
		wipe(ns.char.heardPlaces)
		ns:Print("this character will hear every place again.")
	end)
	Place(forget, 24, 34)

	Place(Header(page, "Bosses"), 16, 30)
	Place(Check(page, "Tell a boss's story when it falls", nil, DB("autoplayBosses")))

	Place(Header(page, "Other"), 16, 30)
	Place(Check(page, "Minimap button", nil, function() return not ns.db.minimap.hide end, function(v)
		ns.db.minimap.hide = not v
		Options:UpdateMinimap()
	end))

	page:SetHeight(-y + 40)

	panel.refresh = function()
		for _, fn in ipairs(refreshers) do fn() end
		panel.UpdatePacks()
	end
	panel.default = function()
		ns:ResetSettings()
		panel.refresh()
		ns.Narrator:ApplySubtitleSettings()
		Options:UpdateMinimap()
	end
	panel.okay = function() end
	panel.cancel = function() end
	function panel.UpdatePacks()
		page.packs:SetText(Options:PackSummary())
	end
	panel:SetScript("OnShow", panel.refresh)
	InterfaceOptions_AddCategory(panel)
end

function Options:PackSummary()
	local quests = ns.Quests.DataModules:Count()
	return format("Voice packs: quests %d, readables %d, places %d, bosses %d.%s", quests,
		ns.Readables:PackCount(), ns.Places:PackCount(), ns.Bosses:PackCount(),
		quests == 0 and "\nNo quest pack loaded: install SpokenQuestsAudio* into Interface\\AddOns." or "")
end

function Options:Open()
	if not panel then Build() end
	InterfaceOptionsFrame_OpenToCategory(panel)
	InterfaceOptionsFrame_OpenToCategory(panel) -- the first call only opens the frame on 3.3.5
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

local mini

local function PlaceMini()
	local angle = math.rad(ns.db.minimap.angle or 200)
	local radius = (Minimap:GetWidth() / 2) + 10
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMini()
	mini = CreateFrame("Button", "SpokenMinimapButton", Minimap)
	mini:SetWidth(31); mini:SetHeight(31)
	mini:SetFrameStrata("MEDIUM")
	mini:SetFrameLevel(8)
	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mini:RegisterForDrag("LeftButton")
	mini:SetHighlightTexture([[Interface\Minimap\UI-Minimap-ZoomButton-Highlight]])
	local icon = mini:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture([[Interface\AddOns\Spoken\icon]])
	icon:SetWidth(20); icon:SetHeight(20)
	icon:SetPoint("TOPLEFT", 7, -5)
	local border = mini:CreateTexture(nil, "OVERLAY")
	border:SetTexture([[Interface\Minimap\MiniMap-TrackingBorder]])
	border:SetWidth(53); border:SetHeight(53)
	border:SetPoint("TOPLEFT")
	mini:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			ns.Sound:StopAll()
		elseif IsShiftKeyDown() then
			ns.Sound:Replay()
		else
			Options:Open()
		end
	end)
	mini:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			PlaceMini()
		end)
	end)
	mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	mini:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("|cffb48cffSpoken|r")
		local current = ns.Sound:Current()
		if current then
			GameTooltip:AddLine("Playing: " .. (current.name or "?"), 1, 1, 1)
			if ns.Sound:Count() > 0 then GameTooltip:AddLine(ns.Sound:Count() .. " waiting", 0.7, 0.7, 0.7) end
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click: settings", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Shift-click: replay the last line", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right-click: stop", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
	PlaceMini()
end

function Options:UpdateMinimap()
	if ns.db.minimap.hide then
		if mini then mini:Hide() end
	else
		if not mini then CreateMini() end
		mini:Show()
	end
end

--------------------------------------------------------------------------------
-- Key bindings (Bindings.xml) and slash commands
--------------------------------------------------------------------------------

BINDING_HEADER_SPOKEN = "Spoken"
BINDING_NAME_SPOKEN_STOP = "Stop the line playing"
BINDING_NAME_SPOKEN_STOPALL = "Stop everything"
BINDING_NAME_SPOKEN_REPLAY = "Replay the last line"
BINDING_NAME_SPOKEN_PLACE = "Tell the story of this place"

local HELP = {
	"/sp - settings",
	"/sp stop - stop this line   /sp stopall - stop everything",
	"/sp replay - play the last line again",
	"/sp place - the story of where you are",
	"/sp book - read the open page again",
	"/sp boss - the story of the boss you target",
	"/sp style subtitles|window|voice",
	"/sp move - move the subtitles",
	"/sp status - voice packs and what was found here",
	"/sp debug - say why a line was not found",
}

local function Status()
	ns:Print(Options:PackSummary())
	for name, why in pairs(ns.packs.failed) do
		ns:Print("  %s did not load: %s", name, why)
	end
	local zones, subzones = ns.Places:LoreCount()
	local books = 0
	for _ in pairs(SpokenReadablesData and SpokenReadablesData.pages or {}) do books = books + 1 end
	ns:Print("lore loaded: %d zones, %d with subzones, %d book pages, boss data %s", zones, subzones, books,
		SpokenBossCreatures and "yes" or "no")
	local zoneID, zone = ns.Places:Zone()
	local storyZone, key = ns.Places:Subzone()
	ns:Print("zone \"%s\" -> %s; subzone \"%s\" -> %s", GetRealZoneText() or "", zoneID and tostring(zoneID) or "no lore",
		GetSubZoneText() or "", key and (storyZone .. ":" .. key) or "no lore")
	ns:Print("narrator: %s, music channel: %s", ns.db.style, ns.db.playOnMusicChannel and "on" or "off")
end

SLASH_SPOKEN1 = "/spoken"
SLASH_SPOKEN2 = "/sp"
SlashCmdList.SPOKEN = function(input)
	local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		Options:Open()
	elseif cmd == "stop" or cmd == "skip" then
		ns.Sound:Skip()
	elseif cmd == "stopall" then
		ns.Sound:StopAll()
	elseif cmd == "replay" then
		ns.Sound:Replay()
	elseif cmd == "place" or cmd == "zone" then
		local ok, why = ns.Places:PlayHere()
		if not ok then
			if why == "playing" then
				ns:Print("this place's story is already playing.")
			elseif why == "queued" then
				ns:Print("this place's story is already waiting in the queue.")
			elseif ns.Places:PackCount() == 0 then
				ns:Print("no places voice pack is loaded (SpokenPlacesAudio).")
			else
				ns:Print("no recording for this place.")
			end
		end
	elseif cmd == "book" then
		ns.Readables:ReadOnScreen(true)
	elseif cmd == "boss" then
		ns.Bosses:TellTarget()
	elseif cmd == "style" and (rest == "subtitles" or rest == "window" or rest == "voice") then
		ns.db.style = rest
		ns.Narrator:Refresh()
		ns:Print("narrator: %s", rest)
	elseif cmd == "move" then
		ns.Narrator:MoveSubtitles()
	elseif cmd == "status" then
		Status()
	elseif cmd == "debug" then
		ns.db.debug = not ns.db.debug
		ns:Print("debug %s", ns.db.debug and "on" or "off")
	elseif cmd == "test" then
		-- A known line, for checking that sound works at all.
		local ok = ns.Quests:PlayFromLog(tonumber(rest) or 7, "accept")
		if not ok then ns:Print("no recording of quest %s is installed.", rest ~= "" and rest or "7") end
	else
		for _, line in ipairs(HELP) do ns:Print(line) end
	end
end

function Options:Enable()
	Build()
	self:UpdateMinimap()
end
