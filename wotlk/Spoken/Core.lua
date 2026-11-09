-- Spoken for the 3.3.5a (WotLK) client.
--
-- A port of Spoken (github.com/rusty-key/spoken-wow, MIT) to the 3.3.5 API. The modern addon
-- leans on C_Timer, C_Map, the Settings panel and sounds that can be stopped; none of those
-- exist here, so the player, the windows and the settings are written again for this client.
-- The voice packs, the game text tables and the lore data are upstream's own files, copied
-- unchanged into Upstream/ by wotlk/sync-upstream.sh, so a merge from upstream brings new
-- data along with it.

local ADDON_NAME, ns = ...
Spoken = ns
ns.name = ADDON_NAME
ns.version = GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

local BRAND = "|cffb48cffSpoken|r"

--------------------------------------------------------------------------------
-- Printing
--------------------------------------------------------------------------------

function ns:Print(fmt, ...)
	local msg = select("#", ...) > 0 and format(fmt, ...) or tostring(fmt)
	DEFAULT_CHAT_FRAME:AddMessage(BRAND .. ": " .. msg)
end

function ns:Debug(fmt, ...)
	if ns.db and ns.db.debug then
		ns:Print("|cff888888" .. (select("#", ...) > 0 and format(fmt, ...) or tostring(fmt)) .. "|r")
	end
end

--------------------------------------------------------------------------------
-- Timers (C_Timer does not exist on 3.3.5)
--------------------------------------------------------------------------------

local timers = {}
local timerFrame = CreateFrame("Frame")
local now = 0
timerFrame:SetScript("OnUpdate", function(_, elapsed)
	now = GetTime()
	local i = 1
	while i <= #timers do
		local t = timers[i]
		if t.cancelled then
			table.remove(timers, i)
		elseif now >= t.at then
			table.remove(timers, i)
			local ok, err = pcall(t.fn)
			if not ok then geterrorhandler()(err) end
		else
			i = i + 1
		end
	end
end)

--- Calls fn after `delay` seconds. Returns a handle with :Cancel().
function ns.After(delay, fn)
	local t = { at = GetTime() + (delay or 0), fn = fn }
	function t:Cancel() self.cancelled = true end
	table.insert(timers, t)
	return t
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

--- Registers fn(event, ...) for an event. Any number of handlers per event.
function ns:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		local ok, err = pcall(fn, event, ...)
		if not ok then geterrorhandler()(err) end
	end
end)

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

ns.defaults = {
	-- How a line is shown: "subtitles", "window" or "voice" (nothing on screen).
	style = "subtitles",
	-- Volume of the voice, 0..1. Lines play on the music channel (see Sound.lua).
	volume = 1,
	playOnMusicChannel = true,
	-- Seconds the game music takes to fade out before a line and back in after.
	fadeMusic = 0.5,
	-- Subtitles
	subtitleScale = 1,
	subtitleShadow = 0.6,
	typeWords = true,
	subtitleY = 200,
	-- Window
	windowPoint = nil,
	windowShowText = true,
	-- Queue
	maxQueue = 8,
	-- Quests and gossip
	quests = true,
	autoplayQuests = true,
	gossip = true,
	-- "always", "questnpc" (once per NPC that has quests), "npc" (once per NPC), "never"
	gossipFrequency = "always",
	followups = true,
	chatter = true,
	stopOnClose = false,
	questLogButton = true,
	-- Readables
	readables = true,
	autoplayReadables = true,
	readWholeBook = true,
	stopBookOnClose = false,
	-- Places
	places = true,
	autoplayZones = true,
	autoplaySubzones = true,
	mapPanel = true,
	placesInCombat = false,
	-- Bosses
	bosses = true,
	autoplayBosses = true,
	-- Minimap button
	minimap = { hide = false, angle = 200 },
	debug = false,
}

ns.charDefaults = {
	heardPlaces = {},
	heardBosses = {},
	seenGossip = {},
}

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function ns:ResetSettings()
	wipe(SpokenDB)
	CopyDefaults(ns.defaults, SpokenDB)
end

--------------------------------------------------------------------------------
-- Text helpers
--------------------------------------------------------------------------------

--- Fills the game's placeholders ($N, $C, $R, $Gmale:female;, $B) for this player.
function ns:FillTokens(text)
	if type(text) ~= "string" then return text end
	local name = UnitName("player") or ""
	local race = UnitRace("player") or ""
	local class = UnitClass("player") or ""
	local female = UnitSex("player") == 3
	text = text:gsub("%$[gG]%s*([^:;]*):([^;]*);", function(m, f) return female and f or m end)
	text = text:gsub("%$[bB]", "\n")
	text = text:gsub("%$[nN]", name)
	text = text:gsub("%$[cC]", class)
	text = text:gsub("%$[rR]", race)
	return text
end

--- The words of a text, for comparing two texts loosely: lower case, no punctuation.
function ns:Words(text)
	text = string.lower(text or "")
	text = text:gsub("\226\128\153", "'")
	text = text:gsub("%p", " ")
	text = text:gsub("%s+", " ")
	return (text:gsub("^ ", ""):gsub(" $", ""))
end

--- Jaccard similarity of two word strings.
function ns:Similarity(a, b)
	local ta, tb = {}, {}
	for w in a:gmatch("%S+") do ta[w] = true end
	for w in b:gmatch("%S+") do tb[w] = true end
	local inter, union = 0, 0
	for w in pairs(ta) do
		union = union + 1
		if tb[w] then inter = inter + 1 end
	end
	for w in pairs(tb) do
		if not ta[w] then union = union + 1 end
	end
	return union > 0 and inter / union or 0
end

--------------------------------------------------------------------------------
-- GUIDs (3.3.5 format: 0xHHHHEEEEEECCCCCC, high 16 bits type, 24 bits entry)
--------------------------------------------------------------------------------

ns.GUID = { Creature = 0xF130, Vehicle = 0xF150, GameObject = 0xF110, Pet = 0xF140 }

function ns:GUIDType(guid)
	if type(guid) ~= "string" or guid:sub(1, 2) ~= "0x" then return nil end
	return tonumber(guid:sub(3, 6), 16)
end

function ns:GUIDEntry(guid)
	local t = self:GUIDType(guid)
	if t == ns.GUID.Creature or t == ns.GUID.Vehicle or t == ns.GUID.GameObject then
		return tonumber(guid:sub(7, 12), 16)
	end
end

--- The creature id in a creature's GUID, nil for anything else.
function ns:CreatureID(guid)
	local t = self:GUIDType(guid)
	if t == ns.GUID.Creature or t == ns.GUID.Vehicle then
		return tonumber(guid:sub(7, 12), 16)
	end
end

function ns:MakeGUID(kind, id)
	return format("0x%04X%06X%06X", kind, id, 0)
end

--------------------------------------------------------------------------------
-- Voice packs
--------------------------------------------------------------------------------

-- The packs ship for the modern Classic clients and name their Interface accordingly, so the
-- 3.3.5 client calls them out of date. Load-on-demand ones (the quest packs) are loaded here
-- with the version check turned off for the call, as upstream does; the others need
-- "Load out of date AddOns" ticked, or their .toc set to 30300 (wotlk/install-packs.sh does).
local function WithOutOfDate(fn, ...)
	local prev = GetCVar("checkAddonVersion")
	SetCVar("checkAddonVersion", "0")
	local a, b = fn(...)
	SetCVar("checkAddonVersion", prev)
	return a, b
end
ns.WithOutOfDate = WithOutOfDate

ns.packs = { present = {}, failed = {} }

function ns:LoadPacks()
	for i = 1, GetNumAddOns() do
		local name, _, _, enabled, loadable, reason = GetAddOnInfo(i)
		local isQuestPack = GetAddOnMetadata(i, "X-SpokenQuests-DataModule-Version")
			or GetAddOnMetadata(i, "X-VoiceOver-DataModule-Version")
		local isSpokenPack = GetAddOnMetadata(i, "X-Child-Of")
		if isQuestPack or isSpokenPack then
			ns.packs.present[name] = true
			if not IsAddOnLoaded(name) and enabled and IsAddOnLoadOnDemand(name) then
				local ok, why = WithOutOfDate(LoadAddOn, name)
				if not ok then ns.packs.failed[name] = why or "?" end
			elseif not IsAddOnLoaded(name) then
				ns.packs.failed[name] = enabled and (reason or "NOT_LOADED") or "DISABLED"
			end
		end
	end
	for name, why in pairs(ns.packs.failed) do
		if why == "INTERFACE_VERSION" or why == "NOT_LOADED" or why == "NOT_DEMAND_LOADED" then
			ns:Print("voice pack %s did not load (%s). Tick \"Load out of date AddOns\" on the character screen, or set its .toc Interface to 30300.", name, why)
		end
	end
end

--------------------------------------------------------------------------------
-- Start up
--------------------------------------------------------------------------------

ns.modules = {}

--- A module is a table with optional :Init() (after settings load) and :Enable() (at login).
function ns:RegisterModule(name, module)
	module.name = name
	ns.modules[name] = module
	table.insert(ns.modules, module)
	return module
end

ns:On("ADDON_LOADED", function(_, addon)
	if addon ~= ADDON_NAME then return end
	SpokenDB = SpokenDB or {}
	SpokenCharDB = SpokenCharDB or {}
	CopyDefaults(ns.defaults, SpokenDB)
	CopyDefaults(ns.charDefaults, SpokenCharDB)
	ns.db, ns.char = SpokenDB, SpokenCharDB
	for _, module in ipairs(ns.modules) do
		if module.Init then module:Init() end
	end
end)

ns:On("PLAYER_LOGIN", function()
	ns:LoadPacks()
	for _, module in ipairs(ns.modules) do
		if module.Enable then module:Enable() end
	end
end)
