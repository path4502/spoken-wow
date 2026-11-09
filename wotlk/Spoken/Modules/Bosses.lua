-- The story of a dungeon or raid boss, told when it falls, from SpokenBossesAudio.
--
-- Upstream learns of a won fight from ENCOUNTER_END, which 3.3.5 does not have. Here a boss is
-- known by its creature id (Upstream/Bosses/Creatures.lua) and its death read from the combat
-- log, which only reports deaths near the player. Each story is told once per character.

local ns = Spoken
local Bosses = ns:RegisterModule("Bosses", {})
ns.Bosses = Bosses

local byCreature -- creature id -> { map, key, name }

local function BuildIndex()
	if byCreature then return end
	byCreature = {}
	for map, bosses in pairs(SpokenBossCreatures or {}) do
		for key, info in pairs(bosses) do
			if info.creature then
				byCreature[info.creature] = { map = map, key = key }
			end
		end
	end
	for map, list in pairs(SpokenBosses and SpokenBosses.maps or {}) do
		for _, boss in ipairs(list) do
			local b = boss.key and SpokenBossCreatures and SpokenBossCreatures[map] and SpokenBossCreatures[map][boss.key]
			if b and b.creature and byCreature[b.creature] then
				byCreature[b.creature].name = boss[1]
			end
		end
	end
end

local function Packs()
	local list = {}
	for _, pack in pairs(SpokenBossesAudioPacks or {}) do
		if type(pack) == "table" and pack.bosses and (pack.language or "enUS") == "enUS" then list[#list + 1] = pack end
	end
	return list
end

function Bosses:PackCount() return #Packs() end

function Bosses:Clip(map, key)
	for _, pack in ipairs(Packs()) do
		local entry = pack.bosses[map] and pack.bosses[map][key]
		if entry and entry.file then
			return "Interface\\AddOns\\" .. pack.addon .. "\\Sounds\\" .. entry.file .. ".mp3", entry.len
		end
	end
end

local function Story(map, key)
	local s = SpokenBossStories and SpokenBossStories[map] and SpokenBossStories[map][key]
	return type(s) == "table" and s[1] or s
end

function Bosses:Tell(boss, asked)
	local id = "boss:" .. boss.map .. ":" .. boss.key
	if not asked and ns.char.heardBosses[id] then return false end
	local path, len = self:Clip(boss.map, boss.key)
	if not path then return false end
	return ns.Sound:Enqueue({
		kind = "boss", path = path, len = len, key = id,
		name = boss.name or boss.key, title = GetRealZoneText(), text = Story(boss.map, boss.key),
		npcID = boss.creature,
		onStart = function() ns.char.heardBosses[id] = true end,
	}, asked, asked)
end

--- /sp boss: the story of the boss targeted.
function Bosses:TellTarget()
	BuildIndex()
	local id = ns:CreatureID(UnitGUID("target"))
	local boss = id and byCreature[id]
	if not boss then
		ns:Print("target a dungeon or raid boss first.")
		return
	end
	boss.creature = id
	if not self:Tell(boss, true) then ns:Print("no recording of %s's story is installed.", boss.name or boss.key) end
end

function Bosses:Enable()
	ns:On("COMBAT_LOG_EVENT_UNFILTERED", function(_, _, subEvent, _, _, _, destGUID)
		if subEvent ~= "UNIT_DIED" or not (ns.db.bosses and ns.db.autoplayBosses) then return end
		BuildIndex()
		local id = ns:CreatureID(destGUID)
		local boss = id and byCreature[id]
		if boss then
			boss.creature = id
			-- After the loot window and the cheering: a beat before the story starts.
			ns.After(3, function() Bosses:Tell(boss) end)
		end
	end)
end
