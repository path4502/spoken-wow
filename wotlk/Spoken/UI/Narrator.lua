-- What is on screen while a line plays: subtitles low in the middle of the screen, a small
-- window with the speaker's face, or nothing (db.style "subtitles", "window" or "voice").
--
-- Subtitles: the speaker's name and the words over a soft band, at most four lines at a time.
-- A longer line turns its pages as the voice reaches them. With db.typeWords the words are
-- typed in a little ahead of the voice. Stop, Replay and Skip show on hover.

local ns = Spoken
local Narrator = ns:RegisterModule("Narrator", {})
ns.Narrator = Narrator

local TEX = [[Interface\AddOns\Spoken\Textures\]]
local MAX_LINES = 4
local WIDTH = 720

--------------------------------------------------------------------------------
-- Paging the words
--------------------------------------------------------------------------------

-- Splits text into pages of at most MAX_LINES lines, breaking between sentences where it can
-- and between words where it must. A page's size is counted in characters from the font's
-- height: measuring a hidden font string is not reliable on this client.
local function Pages(text, fontHeight)
	local pages = {}
	text = (text or ""):gsub("\r", ""):gsub("\n+", " "):gsub("%s+", " ")
	text = text:gsub("^ ", ""):gsub(" $", "")
	if text == "" then return pages end
	local perLine = math.floor(WIDTH / ((fontHeight or 16) * 0.5))
	local budget = math.floor(perLine * MAX_LINES * 0.88)
	if #text <= budget then return { text } end
	local sentences = {}
	for s in text:gmatch("[^%.!%?]+[%.!%?]*[\"']?%s*") do sentences[#sentences + 1] = s end
	if #sentences == 0 then sentences = { text } end
	local page = ""
	local function Flush()
		local p = page:gsub(" $", "")
		if p ~= "" then pages[#pages + 1] = p end
		page = ""
	end
	for _, sentence in ipairs(sentences) do
		if #page + #sentence <= budget then
			page = page .. sentence
		else
			Flush()
			if #sentence <= budget then
				page = sentence
			else
				for word in sentence:gmatch("%S+%s*") do
					if #page + #word > budget then Flush() end
					page = page .. word
				end
			end
		end
	end
	Flush()
	return pages
end

--------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------

local function GlyphButton(parent, texture, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(22); b:SetHeight(22)
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetTexture(texture)
	b.icon = t
	b:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip)
		GameTooltip:Show()
		if parent:GetScript("OnEnter") then parent:GetScript("OnEnter")(parent) end
	end)
	b:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return b
end

local function TextButton(parent, label, tip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetWidth(22); b:SetHeight(22)
	local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	fs:SetPoint("CENTER")
	fs:SetText(label)
	b:SetFontString(fs)
	b:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

--------------------------------------------------------------------------------
-- Subtitles
--------------------------------------------------------------------------------

local sub

local function CreateSubtitles()
	sub = CreateFrame("Frame", "SpokenSubtitles", UIParent)
	sub:SetFrameStrata("MEDIUM")
	sub:SetWidth(WIDTH + 80); sub:SetHeight(130)
	sub:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, ns.db.subtitleY)
	sub:EnableMouse(false)
	sub:SetMovable(true)
	sub:SetClampedToScreen(true)

	local band = sub:CreateTexture(nil, "BACKGROUND")
	band:SetTexture(TEX .. "SubtitleBand")
	band:SetPoint("TOPLEFT", -40, 10)
	band:SetPoint("BOTTOMRIGHT", 40, -10)
	sub.band = band

	local name = sub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	name:SetPoint("TOP", 0, -6)
	name:SetShadowOffset(1, -1)
	sub.nameText = name

	local text = sub:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	text:SetPoint("TOP", name, "BOTTOM", 0, -6)
	text:SetWidth(WIDTH)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("TOP")
	text:SetShadowOffset(1, -1)
	text:SetSpacing(2)
	sub.text = text

	-- Hover controls. The frame takes the mouse only where the controls are, so it never
	-- blocks clicks into the world.
	local controls = CreateFrame("Frame", nil, sub)
	controls:SetWidth(110); controls:SetHeight(26)
	controls:SetPoint("BOTTOM", sub, "TOP", 0, 2)
	controls:EnableMouse(true)
	controls:SetAlpha(0.25)
	controls:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
	controls:SetScript("OnLeave", function(self) if not MouseIsOver(self) then self:SetAlpha(0.25) end end)
	local stop = GlyphButton(controls, TEX .. "GlyphStop", "Stop (right-click: stop all)", function(_, button)
		if button == "RightButton" then ns.Sound:StopAll() else ns.Sound:Skip() end
	end)
	stop:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	stop:SetPoint("LEFT", 6, 0)
	local replay = GlyphButton(controls, TEX .. "GlyphReplay", "Replay", function() ns.Sound:Replay() end)
	replay:SetPoint("LEFT", stop, "RIGHT", 10, 0)
	local skip = TextButton(controls, ">>", "Skip to the next line", function() ns.Sound:Skip() end)
	skip:SetPoint("LEFT", replay, "RIGHT", 10, 0)
	for _, b in ipairs({ stop, replay, skip }) do
		b:HookScript("OnEnter", function() controls:SetAlpha(1) end)
		b:HookScript("OnLeave", function() if not MouseIsOver(controls) then controls:SetAlpha(0.25) end end)
	end
	sub.controls = controls
	sub:Hide()
end

function Narrator:ApplySubtitleSettings()
	if not sub then return end
	sub:SetScale(ns.db.subtitleScale or 1)
	sub.band:SetAlpha(ns.db.subtitleShadow or 0.6)
	sub:ClearAllPoints()
	sub:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, ns.db.subtitleY or 200)
end

--------------------------------------------------------------------------------
-- The small window
--------------------------------------------------------------------------------

local win

local function CreateWindow()
	win = CreateFrame("Frame", "SpokenWindow", UIParent)
	win:SetWidth(340); win:SetHeight(96)
	win:SetFrameStrata("MEDIUM")
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetClampedToScreen(true)
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, rel, x, y = self:GetPoint()
		ns.db.windowPoint = { point, rel, x, y }
	end)
	win:SetBackdrop({
		bgFile = TEX .. "MinimalBackground",
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	win:SetBackdropColor(1, 1, 1, 0.95)
	win:SetBackdropBorderColor(0.6, 0.5, 0.35, 1)

	local portraitBg = win:CreateTexture(nil, "BACKGROUND")
	portraitBg:SetTexture(TEX .. "MinimalPortraitBackground")
	portraitBg:SetWidth(78); portraitBg:SetHeight(78)
	portraitBg:SetPoint("LEFT", 9, 0)

	local model = CreateFrame("PlayerModel", nil, win)
	model:SetWidth(70); model:SetHeight(70)
	model:SetPoint("CENTER", portraitBg, "CENTER")
	win.model = model

	local ring = win:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(TEX .. "MinimalPortraitRing")
	ring:SetWidth(84); ring:SetHeight(84)
	ring:SetPoint("CENTER", portraitBg, "CENTER")

	local name = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("TOPLEFT", portraitBg, "TOPRIGHT", 10, -4)
	name:SetPoint("RIGHT", -60, 0)
	name:SetJustifyH("LEFT")
	win.nameText = name

	local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
	title:SetPoint("RIGHT", -10, 0)
	title:SetJustifyH("LEFT")
	win.titleText = title

	local text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	text:SetPoint("RIGHT", -10, 0)
	text:SetHeight(36)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	win.text = text

	local bar = CreateFrame("StatusBar", nil, win)
	bar:SetStatusBarTexture([[Interface\TargetingFrame\UI-StatusBar]])
	bar:SetStatusBarColor(0.7, 0.55, 1)
	bar:SetHeight(4)
	bar:SetPoint("BOTTOMLEFT", portraitBg, "BOTTOMRIGHT", 10, 2)
	bar:SetPoint("RIGHT", -10, 0)
	bar:SetMinMaxValues(0, 1)
	win.bar = bar

	local stop = GlyphButton(win, TEX .. "GlyphStop", "Stop (right-click: stop all)", function(_, button)
		if button == "RightButton" then ns.Sound:StopAll() else ns.Sound:Skip() end
	end)
	stop:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	stop:SetWidth(18); stop:SetHeight(18)
	stop:SetPoint("TOPRIGHT", -8, -8)
	local replay = GlyphButton(win, TEX .. "GlyphReplay", "Replay", function() ns.Sound:Replay() end)
	replay:SetWidth(18); replay:SetHeight(18)
	replay:SetPoint("RIGHT", stop, "LEFT", -4, 0)

	local count = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 2)
	win.count = count

	if ns.db.windowPoint then
		local p = ns.db.windowPoint
		win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		win:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
	win:Hide()
end

-- The face of the speaker: the unit when it is in front of us, its creature id otherwise.
local function SetFace(model, item)
	model:ClearModel()
	if item.kind == "book" or item.kind == "place" then
		model:SetModel([[Interface\Buttons\TalkToMeQuestion_White.mdx]])
		model:SetModelScale(2.5)
		model:SetPosition(0, 0, -0.5)
		return
	end
	for _, unit in ipairs({ "npc", "questnpc", "target", "mouseover" }) do
		if item.unitGUID and UnitExists(unit) and UnitGUID(unit) == item.unitGUID then
			model:SetUnit(unit)
			model:SetCamera(0)
			return
		end
	end
	if item.npcID then
		model:SetCreature(item.npcID)
		model:SetCamera(0)
	end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

local shown -- the item on screen
local pages, pageStarts, total

local function PrepareText(item)
	pages, pageStarts, total = {}, {}, 0
	if not item.text or item.text == "" then return end
	pages = Pages(item.text, select(2, sub.text:GetFont()))
	for i, p in ipairs(pages) do
		pageStarts[i] = total
		total = total + #p
	end
end

local function Show(item)
	shown = item
	local style = ns.db.style
	if style == "subtitles" then
		if not sub then CreateSubtitles(); Narrator:ApplySubtitleSettings() end
		if win then win:Hide() end
		sub.nameText:SetText(item.name or "")
		PrepareText(item)
		sub.text:SetText("")
		sub:Show()
	elseif style == "window" then
		if not win then CreateWindow() end
		if sub then sub:Hide() end
		win.nameText:SetText(item.name or "")
		win.titleText:SetText(item.title or "")
		win.text:SetText(ns.db.windowShowText and item.text or "")
		SetFace(win.model, item)
		win:Show()
	else
		if sub then sub:Hide() end
		if win then win:Hide() end
	end
end

local function Hide()
	shown = nil
	if sub then sub:Hide() end
	if win then win:Hide() end
end

local updater = CreateFrame("Frame")
local acc = 0
updater:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.05 or not shown then return end
	acc = 0
	local position, length = ns.Sound:Progress()
	local fraction = length > 0 and position / length or 0
	if sub and sub:IsShown() and #pages > 0 then
		-- Where the voice is in the words, a little ahead when typing so the eye leads.
		local at = fraction * total
		local index = 1
		for i = #pages, 1, -1 do
			if at >= pageStarts[i] then index = i; break end
		end
		local page = pages[index]
		if ns.db.typeWords then
			local into = math.floor((at - pageStarts[index]) * 1.08 + 12)
			local cut = page:sub(1, math.max(0, into))
			-- Never end in the middle of a UTF-8 character.
			cut = cut:gsub("[\192-\255][\128-\191]*$", "")
			sub.text:SetText(cut)
		else
			sub.text:SetText(page)
		end
	end
	if win and win:IsShown() then
		win.bar:SetValue(fraction)
		local waiting = ns.Sound:Count()
		win.count:SetText(waiting > 0 and (waiting .. " waiting") or "")
	end
end)

function Narrator:Refresh()
	local current = ns.Sound:Current()
	if current then
		Show(current)
	else
		Hide()
	end
end

function Narrator:Init()
	ns.Sound:Listen(function(current)
		if current ~= shown then
			if current then Show(current) else Hide() end
		end
	end)
end

--- Unlocks the subtitles so they can be dragged, for the Move button in the settings.
function Narrator:MoveSubtitles()
	if not sub then CreateSubtitles(); self:ApplySubtitleSettings() end
	if sub.moving then
		sub.moving = nil
		sub:EnableMouse(false)
		sub:SetScript("OnMouseDown", nil)
		sub:SetScript("OnMouseUp", nil)
		ns.db.subtitleY = math.floor(sub:GetBottom() * sub:GetEffectiveScale() / UIParent:GetEffectiveScale() + 0.5)
		self:ApplySubtitleSettings()
		if not shown then sub:Hide() end
		ns:Print("subtitles locked.")
		return
	end
	sub.moving = true
	sub.nameText:SetText("Spoken")
	sub.text:SetText("Drag the subtitles up or down, then type /sp move again to lock them.")
	sub:EnableMouse(true)
	sub:SetScript("OnMouseDown", function(self) self:StartMoving() end)
	sub:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
	sub:Show()
end
