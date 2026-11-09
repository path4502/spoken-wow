-- Quest dialogue, NPC gossip, follow-up lines and world chatter, from Spoken's quest packs.
--
-- The packs (SpokenQuestsAudio*) are AI_VoiceOver data modules: Module.lua returns unless the
-- global VoiceOver.DataModules exists, then registers itself, and every generated table hangs
-- off the pack's global. This file is that VoiceOver global for 3.3.5, and the lookups that
-- turn what is on screen into a file in a pack, ported from Spoken_Quests/DataModules.lua.
--
-- 3.3.5 has no GetQuestID() at QUEST_DETAIL time, so the quest is found by its title, its
-- giver's name and its text through the packs' QuestIDLookup, as AI_VoiceOver did on old clients.

local ns = Spoken
local Quests = ns:RegisterModule("Quests", {})
ns.Quests = Quests

--------------------------------------------------------------------------------
-- The VoiceOver environment the packs and upstream's data files expect
--------------------------------------------------------------------------------

VoiceOver = VoiceOver or setmetatable({}, { __index = _G })
local VO = VoiceOver

local SoundEvent = {
	QuestAccept = 1, QuestProgress = 2, QuestComplete = 3, QuestGreeting = 4, Gossip = 5,
	QuestFollowup = 6, NPCChatter = 7,
}
function SoundEvent:IsQuestEvent(e) return e == 1 or e == 2 or e == 3 end
function SoundEvent:IsGossipEvent(e) return e == 4 or e == 5 end
function SoundEvent:GetName(e) for k, v in pairs(self) do if v == e then return k end end end
VO.Enums = VO.Enums or {}
VO.Enums.SoundEvent = SoundEvent
VO.Language = VO.Language or {
	GetClientLanguage = function() local l = GetLocale(); return l == "enGB" and "enUS" or l end,
}

local DataModules = { modules = {}, ordered = {} }
VO.DataModules = DataModules
Quests.DataModules = DataModules

function DataModules:Register(name, module)
	if self.modules[name] then return end
	module.METADATA = {
		AddonName = name,
		Priority = tonumber(GetAddOnMetadata(name, "X-SpokenQuests-DataModule-Priority")
			or GetAddOnMetadata(name, "X-VoiceOver-DataModule-Priority") or "0") or 0,
		Language = GetAddOnMetadata(name, "X-SpokenQuests-Language") or "enUS",
		Version = GetAddOnMetadata(name, "Version"),
	}
	self.modules[name] = module
	table.insert(self.ordered, module)
	table.sort(self.ordered, function(a, b)
		if a.METADATA.Priority ~= b.METADATA.Priority then return a.METADATA.Priority > b.METADATA.Priority end
		return a.METADATA.AddonName < b.METADATA.AddonName
	end)
end

function DataModules:GetModules() return ipairs(self.ordered) end
function DataModules:Count() return #self.ordered end

--------------------------------------------------------------------------------
-- Lookups (after Spoken_Quests/DataModules.lua, MIT)
--------------------------------------------------------------------------------

local GOSSIP_MATCH_FLOOR = 0.7

local function NoDoubleQuotes(text) return (string.gsub(text or "", '"', "'")) end

local function FirstWords(text, n)
	local out = {}
	for w in string.gmatch(text, "%S+") do
		out[#out + 1] = w
		if #out >= n then break end
	end
	return table.concat(out, " ")
end

local function LastWords(text, n)
	local out = {}
	for w in string.gmatch(text, "%S+") do out[#out + 1] = w end
	return table.concat(out, " ", math.max(1, #out - n + 1), #out)
end

local function BestKey(query, entries, keyText)
	local best, bestScore
	for key, value in pairs(entries) do
		local score = ns:Similarity(query, keyText and keyText(key) or key)
		if not bestScore or score > bestScore then
			best, bestScore = { value = value, text = key, similarity = score }, score
		end
	end
	return best
end

--- The quest on screen: `source` is "accept", "progress" or "complete".
function DataModules:GetQuestID(source, title, npcName, text)
	title, npcName = NoDoubleQuotes(title), NoDoubleQuotes(npcName)
	local key = NoDoubleQuotes(FirstWords(text or "", 15)) .. " " .. NoDoubleQuotes(LastWords(text or "", 15))
	local entries = {}
	for _, module in self:GetModules() do
		local data = module.QuestIDLookup and module.QuestIDLookup[source]
		local byTitle = data and data[title]
		if type(byTitle) == "number" then
			return byTitle
		elseif type(byTitle) == "table" then
			local byNPC = byTitle[npcName]
			if type(byNPC) == "number" then
				return byNPC
			elseif type(byNPC) == "table" then
				for t, id in pairs(byNPC) do entries[t] = entries[t] or id end
			elseif not npcName or npcName == "" then
				-- No giver (a quest shared or read from the log): any giver's entry.
				for _, v in pairs(byTitle) do
					if type(v) == "number" then return v end
				end
			end
		end
	end
	local best = BestKey(key, entries)
	return best and best.value
end

--- The giver of a quest: "creature"|"object"|"item", id.
function DataModules:GetQuestGiver(questID)
	for _, module in self:GetModules() do
		if module.NPCIDLookupByQuestID and module.NPCIDLookupByQuestID[questID] then
			return "creature", module.NPCIDLookupByQuestID[questID]
		elseif module.ObjectIDLookupByQuestID and module.ObjectIDLookupByQuestID[questID] then
			return "object", module.ObjectIDLookupByQuestID[questID]
		elseif module.ItemIDLookupByQuestID and module.ItemIDLookupByQuestID[questID] then
			return "item", module.ItemIDLookupByQuestID[questID]
		end
	end
end

function DataModules:GetName(kind, id)
	local tableName = kind == "creature" and "NPCNameLookupByNPCID"
		or kind == "object" and "ObjectNameLookupByObjectID"
		or kind == "item" and "ItemNameLookupByItemID"
	if not tableName then return end
	for _, module in self:GetModules() do
		local t = module[tableName]
		if t and t[id] then return t[id] end
	end
end

-- Which gossip table answers for this speaker, and under what key.
local function GossipTable(data)
	local t = ns:GUIDType(data.unitGUID)
	if t == ns.GUID.Creature or t == ns.GUID.Vehicle then
		return "GossipLookupByNPCID", ns:GUIDEntry(data.unitGUID)
	elseif t == ns.GUID.GameObject then
		return "GossipLookupByObjectID", ns:GUIDEntry(data.unitGUID)
	end
	return data.isObject and "GossipLookupByObjectName" or "GossipLookupByNPCName", data.name and NoDoubleQuotes(data.name)
end

local function Collect(tableName, key)
	local out = {}
	if key == nil then return out end
	for _, module in DataModules:GetModules() do
		local t = module[tableName]
		local lines = t and t[key]
		if lines then
			for text, file in pairs(lines) do out[text] = out[text] or file end
		end
	end
	return out
end

local function MatchShown(text, entries)
	if entries[text] then return entries[text] end
	local best = BestKey(ns:Words(text), entries, function(k) return ns:Words(ns:FillTokens(k)) end)
	return best and best.similarity >= GOSSIP_MATCH_FLOOR and best.value or nil
end

function DataModules:GetGossipFile(data)
	local tableName, key = GossipTable(data)
	local entries = Collect(tableName, key)
	if next(entries) == nil and data.name and tableName ~= "GossipLookupByNPCName" and tableName ~= "GossipLookupByObjectName" then
		-- A creature the pack knows by name but not by id (a respawned copy, a Forever id).
		entries = Collect(data.isObject and "GossipLookupByObjectName" or "GossipLookupByNPCName", NoDoubleQuotes(data.name))
	end
	if next(entries) == nil then return nil end
	return MatchShown(data.text or "", entries)
end

local function QuestFile(data, moment)
	local stem = format("%d-%s", data.questID, moment)
	local text = data.text ~= "" and data.text or nil
	local wordings = text and Collect("QuestWordingLookup", stem)
	if not wordings or next(wordings) == nil then return stem end
	return MatchShown(text, wordings) or stem
end

local FILE_FOR_EVENT = {
	[SoundEvent.QuestAccept] = function(d) return QuestFile(d, "accept") end,
	[SoundEvent.QuestProgress] = function(d) return QuestFile(d, "progress") end,
	[SoundEvent.QuestComplete] = function(d) return QuestFile(d, "complete") end,
	[SoundEvent.QuestGreeting] = function(d) return DataModules:GetGossipFile(d) end,
	[SoundEvent.Gossip] = function(d) return DataModules:GetGossipFile(d) end,
}

-- The sex the speaker is drawn as (UnitSex: 2 male, 3 female), when it is a unit we can see.
local function SexOf(guid)
	for _, unit in ipairs({ "npc", "questnpc", "target", "mouseover", "focus" }) do
		if UnitExists(unit) and UnitGUID(unit) == guid then
			return UnitSex(unit)
		end
	end
end

-- The file in the speaker's own voice, where the packs split a line by giver or by sex.
local function OwnFile(data, line)
	local guid = data.unitGUID
	local t = ns:GUIDType(guid)
	local id = guid and ns:GUIDEntry(guid)
	if not id then return end
	local quest = SoundEvent:IsQuestEvent(data.event)
	local creature = t == ns.GUID.Creature or t == ns.GUID.Vehicle
	local sex = creature and SexOf(guid)
	for _, module in DataModules:GetModules() do
		local file
		if creature and sex then
			if quest then
				local byLine = module.QuestFileLookupByNPCSex and module.QuestFileLookupByNPCSex[line]
				file = byLine and byLine[id] and byLine[id][sex]
			else
				local byNPC = module.GossipFileLookupByNPCSex and module.GossipFileLookupByNPCSex[id]
				file = byNPC and byNPC[sex] and byNPC[sex][line]
			end
		end
		if not file and quest then
			local tableName = creature and "QuestFileLookupByNPCID" or "QuestFileLookupByObjectID"
			local byLine = module[tableName] and module[tableName][line]
			file = byLine and byLine[id]
		end
		if file then return file end
	end
end

local function GreetingOfVoice(fileName)
	local _, _, hash = string.find(fileName or "", "^(" .. string.rep("%x", 32) .. ")%-")
	return hash
end

local function Gendered(fileName)
	local sex = UnitSex("player")
	return (sex == 2 and "m-" or sex == 3 and "f-" or "") .. fileName
end

--- Fills data.path/len for data.fileName (or `instead`) from whichever pack has it.
function DataModules:Resolve(data, instead)
	local candidates = {}
	for _, name in ipairs({ data.fileName, instead }) do
		candidates[#candidates + 1] = name
		local aliases = VO.GossipAliases and VO.GossipAliases[name]
		if aliases then
			for _, alias in ipairs(aliases) do candidates[#candidates + 1] = alias end
		end
	end
	for _, wanted in ipairs(candidates) do
		local gendered = Gendered(wanted)
		for _, module in self:GetModules() do
			local lengths = module.SoundLengthLookupByFileName
			if lengths then
				local fileName, len = gendered, lengths[gendered]
				if not len then fileName, len = wanted, lengths[wanted] end
				if len then
					local rel = module.GetSoundPath and module:GetSoundPath(fileName, data.event) or fileName
					data.fileName = fileName
					data.path = format([[Interface\AddOns\%s\%s]], module.METADATA.AddonName, rel)
					data.len = len
					return true
				end
			end
		end
	end
	return false
end

--- Finds the recording for a quest or gossip line. Returns true when one was found.
function DataModules:Prepare(data)
	local line = FILE_FOR_EVENT[data.event](data)
	if not line then return false end
	data.fileName = line
	local own = OwnFile(data, line)
	if own then
		data.fileName = own
		if self:Resolve(data, line) then return true end
	end
	data.fileName = line
	return self:Resolve(data, GreetingOfVoice(line))
end

--------------------------------------------------------------------------------
-- What is on screen
--------------------------------------------------------------------------------

local function NPC()
	local guid = UnitGUID("questnpc") or UnitGUID("npc")
	local name = UnitName("questnpc") or UnitName("npc")
	local t = ns:GUIDType(guid)
	local isObject = not guid or t == ns.GUID.GameObject
	local isPlayer = guid and UnitIsPlayer("npc")
	return guid, name, isObject, isPlayer
end

local KIND_OF_EVENT = {
	[SoundEvent.QuestAccept] = "accept", [SoundEvent.QuestProgress] = "progress",
	[SoundEvent.QuestComplete] = "complete", [SoundEvent.QuestGreeting] = "gossip", [SoundEvent.Gossip] = "gossip",
}

Quests.currentQuestID = nil
local currentItem   -- the line the open quest or gossip window started
local lastHandled = {}

local function Queue(data, title)
	local item = {
		kind = SoundEvent:IsQuestEvent(data.event) and "quest" or "gossip",
		moment = KIND_OF_EVENT[data.event],
		path = data.path, len = data.len, key = data.fileName,
		name = data.name, title = title, text = ns:FillTokens(data.text),
		unitGUID = data.unitGUID, npcID = ns:CreatureID(data.unitGUID), questID = data.questID,
		onStart = data.onStart,
	}
	if ns.Sound:Enqueue(item) then
		currentItem = item
		return item
	end
end

-- The same window refreshing (a gossip page redrawn, a quest re-shown) does not queue twice.
local function Recently(key)
	local t = GetTime()
	if lastHandled[key] and t - lastHandled[key] < 3 then return true end
	lastHandled[key] = t
end

function Quests:OnQuestEvent(event, source, text)
	if not (ns.db.quests and ns.db.autoplayQuests) then return end
	local guid, name, isObject, isPlayer = NPC()
	local title = GetTitleText()
	local questID
	if isPlayer then
		questID = DataModules:GetQuestID(source, title, "", text)
		name = nil
	else
		questID = DataModules:GetQuestID(source, title, name, text)
	end
	if not questID then
		ns:Debug("no quest id for \"%s\" (%s, %s)", tostring(title), source, tostring(name))
		return
	end
	self.currentQuestID = questID
	if not guid or isPlayer then
		local kind, id = DataModules:GetQuestGiver(questID)
		if kind == "creature" then
			guid = ns:MakeGUID(ns.GUID.Creature, id)
		elseif kind == "object" then
			guid = ns:MakeGUID(ns.GUID.GameObject, id)
		end
		name = id and DataModules:GetName(kind, id) or name
	end
	if Recently(source .. questID) then return end
	local data = { event = event, questID = questID, name = name, text = text, unitGUID = guid, isObject = isObject }
	if DataModules:Prepare(data) then
		Queue(data, title)
	else
		ns:Debug("quest %d %s: no recording", questID, source)
	end
end

local function ShouldPlayGossip(guid)
	local freq = ns.db.gossipFrequency
	if freq == "never" then return false end
	local key = guid or "unknown"
	local seen = ns.char.seenGossip[key]
	if freq == "npc" and seen then return false end
	if freq == "questnpc" and seen and ((GetNumGossipActiveQuests() or 0) > 0 or (GetNumGossipAvailableQuests() or 0) > 0) then
		return false
	end
	return true, key
end

function Quests:OnGossip(event, text)
	if not (ns.db.quests and ns.db.gossip) then return end
	local guid, name, isObject = NPC()
	if not guid and not name then return end
	if not text or text == "" then return end
	local play, key = ShouldPlayGossip(guid)
	if not play then return end
	if Recently((guid or name) .. text) then return end
	local data = { event = event, name = name, text = text, unitGUID = guid, isObject = isObject,
		onStart = function() ns.char.seenGossip[key] = true end }
	if DataModules:Prepare(data) then
		Queue(data, nil)
	else
		ns:Debug("gossip of %s: no recording", tostring(name))
	end
end

--- Plays a quest's accept (or complete) line from the quest log.
function Quests:PlayFromLog(questID, moment)
	moment = moment or "accept"
	local kind, id = DataModules:GetQuestGiver(questID)
	local guid = kind == "creature" and ns:MakeGUID(ns.GUID.Creature, id)
		or kind == "object" and ns:MakeGUID(ns.GUID.GameObject, id) or nil
	local event = moment == "complete" and SoundEvent.QuestComplete or SoundEvent.QuestAccept
	local text = SpokenQuestsText and SpokenQuestsText[questID] and SpokenQuestsText[questID][moment] or ""
	local data = { event = event, questID = questID, unitGUID = guid, text = "",
		name = id and DataModules:GetName(kind, id) or "" }
	if DataModules:Prepare(data) then
		data.text = text
		local item = Queue(data, (GetQuestLogTitle(GetQuestLogSelection())))
		return item ~= nil
	end
	return false
end

function Quests:HasRecording(questID, moment)
	local data = { event = moment == "complete" and SoundEvent.QuestComplete or SoundEvent.QuestAccept,
		questID = questID, text = "" }
	return DataModules:Prepare(data)
end

--------------------------------------------------------------------------------
-- Follow-up lines and world chatter
--------------------------------------------------------------------------------

-- Follow-up: what an NPC says in chat after a quest is accepted or turned in
-- (VoiceOver.FollowupLines, from upstream's FollowupLines.lua). Armed for a minute.
local armed = {}
local heardChatter = {}
local chatterByName

local function Render(text, female)
	return ns:FillTokens(text)
end

function Quests:Arm(questID, when)
	local lines = VO.FollowupLines and VO.FollowupLines[when] and VO.FollowupLines[when][questID]
	if not lines then return end
	for _, line in ipairs(lines) do
		table.insert(armed, { line = line, questID = questID, until_ = GetTime() + 60 + (line.delay or 0) })
	end
end

local function FollowupFile(speaker, lineID, guid)
	local sex = guid and SexOf(guid)
	for _, module in DataModules:GetModules() do
		local bySex = sex and module.FollowupLookupByNPCSex and module.FollowupLookupByNPCSex[speaker]
		local stem = bySex and bySex[lineID] and bySex[lineID][sex]
		local byLine = module.FollowupLookup and module.FollowupLookup[speaker]
		stem = stem or (byLine and byLine[lineID])
		if stem then
			local data = { event = SoundEvent.QuestFollowup, fileName = stem }
			if DataModules:Resolve(data) then return data end
		end
	end
end

local function SameWords(a, b)
	a, b = ns:Words(a), ns:Words(b)
	return a == b or ns:Similarity(a, b) >= 0.85
end

local function PlayLine(speaker, lineID, message, sender, guid, kind)
	local data = FollowupFile(speaker, lineID, guid)
	if not data then return false end
	return ns.Sound:Enqueue({
		kind = kind, path = data.path, len = data.len, key = data.fileName .. ":" .. (sender or ""),
		name = sender, text = message, unitGUID = guid or ns:MakeGUID(ns.GUID.Creature, speaker), npcID = speaker,
	})
end

function Quests:OnMonsterChat(message, sender, guid)
	if not ns.db.quests then return end
	local t = GetTime()
	-- Follow-ups first: they belong to a quest just accepted or handed in.
	if ns.db.followups then
		for i = #armed, 1, -1 do
			local entry = armed[i]
			if entry.until_ < t then
				table.remove(armed, i)
			else
				local line = entry.line
				local said = line.male or line.female or line.text
				if (said and SameWords(message, Render(said))) or (line.female and SameWords(message, Render(line.female))) then
					-- One outcome of a step: the rest of it will not be said.
					for j = #armed, 1, -1 do
						local other = armed[j]
						if other.questID == entry.questID and other.line.step == line.step then
							table.remove(armed, j)
						end
					end
					PlayLine(line.speaker or ns:CreatureID(guid) or 0, line.id, message, sender, guid, "followup")
					return
				end
			end
		end
	end
	if not ns.db.chatter or not VO.ChatterLines then return end
	if not chatterByName then
		chatterByName = {}
		for id, lines in pairs(VO.ChatterLines) do
			if lines.name then
				chatterByName[lines.name] = chatterByName[lines.name] or {}
				table.insert(chatterByName[lines.name], id)
			end
		end
	end
	local ids = {}
	local fromGuid = ns:CreatureID(guid)
	if fromGuid then ids[1] = fromGuid end
	for _, id in ipairs(sender and chatterByName[sender] or {}) do
		if id ~= fromGuid then ids[#ids + 1] = id end
	end
	for _, id in ipairs(ids) do
		for _, line in ipairs(VO.ChatterLines[id] or {}) do
			if line.text and SameWords(message, Render(line.text)) then
				local key = id .. ":" .. line.id
				if heardChatter[key] and t - heardChatter[key] < 60 then return end
				if PlayLine(id, line.id, message, sender, guid, "chatter") then
					heardChatter[key] = t
					return
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Quest log button
--------------------------------------------------------------------------------

local logButton

local function SelectedQuestID()
	local index = GetQuestLogSelection()
	if not index or index == 0 then return end
	local title, _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
	if isHeader then return end
	return questID
end

local function UpdateLogButton()
	if not logButton then return end
	local questID = SelectedQuestID()
	if ns.db.quests and ns.db.questLogButton and questID and Quests:HasRecording(questID, "accept") then
		logButton.questID = questID
		logButton:Show()
	else
		logButton:Hide()
	end
end

local function CreateLogButton()
	if logButton or not QuestLogFrame then return end
	logButton = CreateFrame("Button", "SpokenQuestLogPlayButton", QuestLogFrame, "UIPanelButtonTemplate")
	logButton:SetWidth(70); logButton:SetHeight(20)
	logButton:SetText("Play")
	if QuestLogFrameShowMapButton then
		logButton:SetPoint("RIGHT", QuestLogFrameShowMapButton, "LEFT", -4, 0)
	else
		logButton:SetPoint("TOPRIGHT", QuestLogFrame, "TOPRIGHT", -40, -44)
	end
	logButton:SetScript("OnClick", function(self)
		if self.questID then
			if not Quests:PlayFromLog(self.questID, "accept") then
				ns:Print("no recording for this quest.")
			end
		end
	end)
	logButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Spoken")
		GameTooltip:AddLine("Read this quest aloud.", 1, 1, 1)
		GameTooltip:Show()
	end)
	logButton:SetScript("OnLeave", GameTooltip_Hide)
	logButton:Hide()
	hooksecurefunc("QuestLog_Update", UpdateLogButton)
	if QuestLog_SetSelection then hooksecurefunc("QuestLog_SetSelection", UpdateLogButton) end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

function Quests:Enable()
	ns:On("QUEST_GREETING", function() Quests:OnGossip(SoundEvent.QuestGreeting, GetGreetingText()) end)
	ns:On("GOSSIP_SHOW", function() Quests:OnGossip(SoundEvent.Gossip, GetGossipText()) end)
	ns:On("QUEST_DETAIL", function() Quests:OnQuestEvent(SoundEvent.QuestAccept, "accept", GetQuestText()) end)
	ns:On("QUEST_PROGRESS", function() Quests:OnQuestEvent(SoundEvent.QuestProgress, "progress", GetProgressText()) end)
	ns:On("QUEST_COMPLETE", function() Quests:OnQuestEvent(SoundEvent.QuestComplete, "complete", GetRewardText()) end)
	local function Closed(kind)
		if ns.db.stopOnClose and currentItem and currentItem.kind == kind then
			ns.Sound:Remove(currentItem.key)
		end
		currentItem = nil
	end
	ns:On("QUEST_FINISHED", function() Closed("quest") end)
	ns:On("GOSSIP_CLOSED", function() Closed("gossip") end)

	-- Follow-ups: armed when a quest is accepted or handed in.
	ns:On("QUEST_ACCEPTED", function(_, index)
		local questID = index and select(9, GetQuestLogTitle(index))
		if questID then Quests:Arm(questID, "start") end
	end)
	hooksecurefunc("GetQuestReward", function()
		if Quests.currentQuestID then Quests:Arm(Quests.currentQuestID, "end") end
	end)
	for _, event in ipairs({ "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_RAID_BOSS_WHISPER" }) do
		ns:On(event, function(_, message, sender, _, _, _, _, _, _, _, _, _, guid)
			Quests:OnMonsterChat(message, sender, guid)
		end)
	end

	CreateLogButton()
end
