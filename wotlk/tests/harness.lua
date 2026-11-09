-- A small stand-in for the 3.3.5 client API, enough to load the addon and drive its events.
-- Run from the repository root:  lua5.1 wotlk/tests/run.lua
--
-- Only functions the 3.3.5 client really has are defined here, so a call to a newer API
-- (C_Timer, SetShown, C_Map...) fails the test instead of passing silently.

local H = { calls = {}, cvars = {}, now = 1000, frames = {} }
_G.H = H

local function log(name, ...) table.insert(H.calls, { name, ... }) end

-- Lua 5.1 globals the client adds.
format = string.format
strsplit = function(sep, s, n)
	local out, start = {}, 1
	while true do
		if n and #out == n - 1 then out[#out + 1] = s:sub(start); break end
		local i = s:find(sep, start, true)
		if not i then out[#out + 1] = s:sub(start); break end
		out[#out + 1] = s:sub(start, i - 1)
		start = i + 1
	end
	return unpack(out)
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
hooksecurefunc = function(a, b, c)
	local t, name, fn = _G, a, b
	if type(a) == "table" then t, name, fn = a, b, c end
	local orig = t[name] or function() end
	t[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
geterrorhandler = function() return function(e) error(e, 0) end end
GetTime = function() return H.now end
GetLocale = function() return "enUS" end
GetCVar = function(k) return H.cvars[k] end
SetCVar = function(k, v) H.cvars[k] = tostring(v); log("SetCVar", k, tostring(v)) end
PlayMusic = function(p) log("PlayMusic", p) end
StopMusic = function() log("StopMusic") end
PlaySoundFile = function(p, ch) log("PlaySoundFile", p, ch) end
InCombatLockdown = function() return false end
IsShiftKeyDown = function() return false end
GetCursorPosition = function() return 0, 0 end
MouseIsOver = function() return false end
InterfaceOptions_AddCategory = function(p) H.panel = p end
InterfaceOptionsFrame_OpenToCategory = function() end
UIDropDownMenu_SetWidth = function() end
UIDropDownMenu_Initialize = function() end
UIDropDownMenu_SetSelectedValue = function() end
UIDropDownMenu_SetText = function() end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = function() end
GameTooltip_Hide = function() end
QuestLog_Update = function() end
QuestLog_SetSelection = function() end
GetQuestReward = function() end
SlashCmdList = {}

-- The world, set by tests.
H.units = {}
H.addons = {}
H.zone, H.subzone = "", ""
UnitGUID = function(u) return H.units[u] and H.units[u].guid end
UnitName = function(u) return H.units[u] and H.units[u].name end
UnitExists = function(u) return H.units[u] ~= nil end
UnitSex = function(u) return H.units[u] and H.units[u].sex or 2 end
UnitIsPlayer = function(u) return H.units[u] and H.units[u].player or false end
UnitRace = function() return "Human" end
UnitClass = function() return "Warrior" end
UnitAffectingCombat = function() return false end
GetRealZoneText = function() return H.zone end
GetSubZoneText = function() return H.subzone end
GetTitleText = function() return H.questTitle end
GetQuestText = function() return H.questText end
GetProgressText = function() return H.questText end
GetRewardText = function() return H.questText end
GetGreetingText = function() return H.gossipText end
GetGossipText = function() return H.gossipText end
GetNumGossipActiveQuests = function() return 0 end
GetNumGossipAvailableQuests = function() return 0 end
GetQuestLogSelection = function() return H.logSelection or 0 end
GetQuestLogTitle = function(i)
	local q = H.log and H.log[i]
	if q then return q.title, 1, nil, nil, false, false, false, false, q.id end
end
ItemTextGetText = function() return H.itemText end
ItemTextGetItem = function() return H.itemTitle end
ItemTextGetPage = function() return H.itemPage end
GetNumAddOns = function() return #H.addons end
local function addon(i) return type(i) == "number" and H.addons[i] or (function() for _, a in ipairs(H.addons) do if a.name == i then return a end end end)() end
GetAddOnInfo = function(i) local a = addon(i); if a then return a.name, a.name, "", a.enabled ~= false, true, nil end end
GetAddOnMetadata = function(i, key) local a = addon(i); return a and a.meta and a.meta[key] end
IsAddOnLoaded = function(i) local a = addon(i); return a and a.loaded end
IsAddOnLoadOnDemand = function(i) local a = addon(i); return a and a.lod end
LoadAddOn = function(name)
	local a = addon(name)
	log("LoadAddOn", name, H.cvars.checkAddonVersion)
	if a and a.load then a.load(); a.loaded = true; return 1 end
	return nil, "MISSING"
end

-- Frames: every method answers, so layout code runs; scripts and events are recorded.
local Frame = {}
local function newObject(kind, name)
	local o = { kind = kind, scripts = {}, events = {}, shown = true, text = "" }
	setmetatable(o, { __index = function(t, k)
		if Frame[k] then return Frame[k] end
		return function() end
	end })
	if name then _G[name] = o; o.name = name end
	return o
end
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, fn) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end fn(...) end end
function Frame:RegisterEvent(e) self.events[e] = true; H.frames[#H.frames + 1] = self end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:GetName() return self.name end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:GetFont() return "Fonts\\FRIZQT__.TTF", 16 end
function Frame:GetWidth() return 140 end
function Frame:GetFrameLevel() return 1 end
function Frame:GetHeight() return 10 end
function Frame:GetBottom() return 200 end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetCenter() return 0, 0 end
function Frame:GetChecked() return self.checked end
function Frame:SetChecked(v) self.checked = v end
function Frame:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Frame:CreateTexture(name) return newObject("Texture", name) end
function Frame:CreateFontString(name)
	local fs = newObject("FontString", name)
	return fs
end
CreateFrame = function(kind, name, parent, template)
	local f = newObject(kind, name)
	if name and template then
		for _, suffix in ipairs({ "Text", "Low", "High" }) do _G[name .. suffix] = newObject("FontString") end
	end
	return f
end
UIParent = newObject("Frame", "UIParent")
Minimap = newObject("Frame", "Minimap")
QuestLogFrame = newObject("Frame", "QuestLogFrame")
GameTooltip = newObject("GameTooltip", "GameTooltip")
WorldMapFrame = newObject("Frame", "WorldMapFrame")
WorldMapDetailFrame = newObject("Frame", "WorldMapDetailFrame")
WorldMapButton = newObject("Button", "WorldMapButton")
WorldMapFrameAreaLabel = newObject("FontString", "WorldMapFrameAreaLabel")
H.map = { continent = 0, zone = 0, zones = { [2] = { "Tirisfal Glades", "Elwynn Forest" } } }
GetCurrentMapContinent = function() return H.map.continent end
GetCurrentMapZone = function() return H.map.zone end
GetMapZones = function(c) return unpack(H.map.zones[c] or {}) end
GetMapContinents = function() return "Kalimdor", "Eastern Kingdoms" end
FauxScrollFrame_GetOffset = function() return 0 end
FauxScrollFrame_Update = function() end
FauxScrollFrame_OnVerticalScroll = function() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) log("print", msg) end }

function H.fire(event, ...)
	for _, f in ipairs(H.frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

-- Moves time on and runs every OnUpdate, in steps.
function H.advance(seconds, step)
	step = step or 0.05
	local target = H.now + seconds
	while H.now < target do
		H.now = H.now + step
		for _, f in ipairs(H.allFrames or {}) do end
		for _, f in pairs(H.updaters) do f.scripts.OnUpdate(f, step) end
	end
end

-- Track frames with OnUpdate scripts.
H.updaters = setmetatable({}, { __mode = "k" })
local setScript = Frame.SetScript
function Frame:SetScript(k, fn)
	setScript(self, k, fn)
	if k == "OnUpdate" then
		if fn then H.updaters[self] = self else H.updaters[self] = nil end
	end
end

--- Loads a .toc's files in order with the addon's (name, namespace) varargs.
function H.loadToc(dir, name, ns)
	ns = ns or {}
	for line in io.lines(dir .. "/" .. name .. ".toc") do
		line = line:gsub("\r", "")
		if line ~= "" and not line:match("^#") then
			local path = dir .. "/" .. line:gsub("\\", "/")
			local chunk = assert(loadfile(path))
			chunk(name, ns)
		end
	end
	return ns
end

function H.find(name, pattern)
	local found = {}
	for _, c in ipairs(H.calls) do
		if c[1] == name and (not pattern or tostring(c[2]):find(pattern, 1, true)) then found[#found + 1] = c end
	end
	return found
end

function H.reset() H.calls = {} end

return H
