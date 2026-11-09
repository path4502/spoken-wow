-- Zone and subzone lore, from SpokenPlacesAudio.
--
-- Upstream keys every zone by its modern uiMapID (1411 is Durotar). 3.3.5 has no such ids, so
-- a zone is found by its English name in the lore (Upstream/Places/Zones.lua), and a subzone by
-- its normalised name under that zone, as upstream's NormaliseAreaKey does. Data/AreaZones.lua
-- lists areas the lore keeps under a different zone than the client puts them in.
--
-- Upstream narrates an area the first time this character stands in it (its autoplayExplored
-- mode, the default). The same is done here, kept per character in SpokenCharDB.heardPlaces.

local ns = Spoken
local Places = ns:RegisterModule("Places", {})
ns.Places = Places

-- The namespace upstream's data files register into (local _, SpokenPlaces = ...).
local lore = { zones = {}, subzones = {} }
function ns:ShouldLoadLanguage(code) return code == "enUS" end
function ns:RegisterLoreData(code, kind, data)
	-- Loaded twice: master's lore, then the lore the installed pack was recorded from, which wins
	-- entry by entry (see wotlk/sync-upstream.sh).
	if code ~= "enUS" or not lore[kind] then return end
	for k, v in pairs(data) do
		if kind == "subzones" and type(lore.subzones[k]) == "table" then
			for area, entry in pairs(v) do
				if type(entry) == "table" and entry.full and entry.full ~= "" then lore.subzones[k][area] = entry end
			end
		elseif kind == "zones" and type(lore.zones[k]) == "table" and not (v.full and v.full ~= "") then
			-- keep master's
		else
			lore[kind][k] = v
		end
	end
end

function ns:NormaliseAreaKey(name)
	if type(name) ~= "string" then return nil end
	local key = name:lower()
	key = key:gsub("'", "")
	key = key:gsub("^the%s+", "")
	key = key:gsub("[^a-z0-9]+", " ")
	key = key:gsub("^%s+", "")
	key = key:gsub("%s+$", "")
	if key == "" then return nil end
	return key
end

local zoneByName -- normalised zone name -> uiMapID
local storyZoneOf -- client zone id -> area key -> zone id the story is kept under

local function BuildIndex()
	if zoneByName then return end
	zoneByName, storyZoneOf = {}, {}
	for mapID, entry in pairs(lore.zones) do
		local key = ns:NormaliseAreaKey(entry.name)
		if key and (not zoneByName[key] or mapID < zoneByName[key]) then
			zoneByName[key] = mapID
		end
	end
	for storyZone, areas in pairs(ns.AreaZones or {}) do
		for key, info in pairs(areas) do
			for _, clientZone in ipairs({ info.zone, unpack(info.also or {}) }) do
				storyZoneOf[clientZone] = storyZoneOf[clientZone] or {}
				storyZoneOf[clientZone][key] = storyZone
			end
		end
	end
end

local function Packs()
	local list = {}
	for _, registry in ipairs({ SpokenPlacesAudioPacks or {}, ZoneLoreAudioPacks or {} }) do
		for _, pack in pairs(registry) do
			if type(pack) == "table" and (pack.zones or pack.subzones) and (pack.language or "enUS") == "enUS" then
				list[#list + 1] = pack
			end
		end
	end
	return list
end

local function Clip(mapID, key)
	for _, pack in ipairs(Packs()) do
		local entry
		if key then
			entry = pack.subzones and pack.subzones[mapID] and pack.subzones[mapID][key]
		else
			entry = pack.zones and pack.zones[mapID]
		end
		if entry and entry.file then
			return "Interface\\AddOns\\" .. pack.addon .. "\\Sounds\\" .. entry.file .. ".mp3", entry.len
		end
	end
end

function Places:PackCount() return #Packs() end

--- The uiMapID and lore entry of a zone, by its name as the client writes it.
function Places:ZoneByName(name)
	BuildIndex()
	local id = zoneByName[ns:NormaliseAreaKey(name)]
	return id, id and lore.zones[id]
end

--- The story of a subzone of `zoneID` called `name`: storyZone, key, entry.
function Places:SubzoneOf(zoneID, name)
	BuildIndex()
	local key = ns:NormaliseAreaKey(name)
	key = key and ns.ForeverNames and ns.ForeverNames[key] or key
	if not zoneID or not key then return end
	local storyZone = storyZoneOf[zoneID] and storyZoneOf[zoneID][key] or zoneID
	local entry = lore.subzones[storyZone] and lore.subzones[storyZone][key]
	if entry then return storyZone, key, entry end
end

--- Every subzone story told in `zoneID`, sorted by name: { storyZone, key, entry }...
function Places:SubzonesIn(zoneID)
	BuildIndex()
	local list = {}
	for key, entry in pairs(lore.subzones[zoneID] or {}) do
		local moved = ns.AreaZones and ns.AreaZones[zoneID] and ns.AreaZones[zoneID][key]
		local hidden = ns.NotOnForever and ns.NotOnForever[zoneID] and ns.NotOnForever[zoneID][key]
		if not moved and not hidden and entry.full and entry.full ~= "" then
			list[#list + 1] = { zoneID, key, entry }
		end
	end
	for key, storyZone in pairs(storyZoneOf[zoneID] or {}) do
		local entry = lore.subzones[storyZone] and lore.subzones[storyZone][key]
		if entry and entry.full and entry.full ~= "" then list[#list + 1] = { storyZone, key, entry } end
	end
	table.sort(list, function(a, b) return (a[3].name or a[2]) < (b[3].name or b[2]) end)
	return list
end

--- How much lore loaded: zones, zones with subzone stories.
function Places:LoreCount()
	local z, s = 0, 0
	for _ in pairs(lore.zones) do z = z + 1 end
	for _ in pairs(lore.subzones) do s = s + 1 end
	return z, s
end

function Places:HasClip(mapID, key)
	return Clip(mapID, key) ~= nil
end

function Places:Heard(mapID, key)
	return ns.char.heardPlaces[key and ("s:" .. mapID .. ":" .. key) or ("z:" .. mapID)] and true or false
end


--- The zone the player is in: uiMapID, entry.
function Places:Zone()
	BuildIndex()
	local id = zoneByName[ns:NormaliseAreaKey(GetRealZoneText())]
	return id, id and lore.zones[id]
end

--- The subzone: the uiMapID its story is kept under, its key, entry.
function Places:Subzone()
	local zoneID = self:Zone()
	local name = GetSubZoneText()
	if not zoneID or not name or name == "" then return end
	local key = ns:NormaliseAreaKey(name)
	key = ns.ForeverNames and ns.ForeverNames[key] or key
	if not key then return end
	local storyZone = storyZoneOf[zoneID] and storyZoneOf[zoneID][key] or zoneID
	local entry = lore.subzones[storyZone] and lore.subzones[storyZone][key]
	if not entry then
		-- An area the lore files under a neighbouring zone (the borders moved after Cataclysm).
		for otherZone, areas in pairs(lore.subzones) do
			if areas[key] then storyZone, entry = otherZone, areas[key]; break end
		end
	end
	if entry then return storyZone, key, entry end
end

function Places:Play(mapID, key, entry, front)
	local path, len = Clip(mapID, key)
	if not path then return false, "none" end
	local id = key and ("s:" .. mapID .. ":" .. key) or ("z:" .. mapID)
	return ns.Sound:Enqueue({
		kind = "place", path = path, len = len, key = id,
		name = entry and entry.name or GetRealZoneText(), title = key and GetRealZoneText() or nil,
		text = entry and (entry.full or entry.short),
		onStart = function() ns.char.heardPlaces[id] = true end,
	}, front)
end

--- /sp place: the subzone's story where it has one, else the zone's.
--- Returns true, or false and why: "none" (no recording), "playing" or "queued".
function Places:PlayHere()
	local storyZone, key, entry = self:Subzone()
	local why
	if storyZone then
		local ok, reason = self:Play(storyZone, key, entry, true)
		if ok then return true end
		why = reason
	end
	local zoneID, zone = self:Zone()
	if zoneID then
		local ok, reason = self:Play(zoneID, nil, zone, true)
		if ok then return true end
		if reason ~= "none" or not why then why = reason end
	end
	return false, why or "none"
end

local pending
local function InCombat() return UnitAffectingCombat("player") or InCombatLockdown() end

function Places:Check()
	if not (ns.db.places and (ns.db.autoplayZones or ns.db.autoplaySubzones)) then return end
	if not ns.db.placesInCombat and InCombat() then
		pending = true
		return
	end
	pending = nil
	if ns.db.autoplayZones then
		local zoneID, zone = self:Zone()
		if zoneID and not ns.char.heardPlaces["z:" .. zoneID] then
			self:Play(zoneID, nil, zone)
		end
	end
	if ns.db.autoplaySubzones then
		local storyZone, key, entry = self:Subzone()
		if storyZone and not ns.char.heardPlaces["s:" .. storyZone .. ":" .. key] then
			self:Play(storyZone, key, entry)
		end
	end
end

-- Border crossings fire zone events in bursts; read the place once the player has stayed.
local settleTimer
local function Settle()
	if settleTimer then settleTimer:Cancel() end
	local zone, sub = GetRealZoneText(), GetSubZoneText()
	settleTimer = ns.After(2, function()
		settleTimer = nil
		if GetRealZoneText() == zone and GetSubZoneText() == sub then
			Places:Check()
		end
	end)
end

function Places:Enable()
	BuildIndex()
	ns:On("ZONE_CHANGED", Settle)
	ns:On("ZONE_CHANGED_INDOORS", Settle)
	ns:On("ZONE_CHANGED_NEW_AREA", Settle)
	ns:On("PLAYER_ENTERING_WORLD", function() ns.After(4, Settle) end)
	ns:On("PLAYER_REGEN_ENABLED", function() if pending then Settle() end end)
end
