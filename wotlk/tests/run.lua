-- Loads the 3.3.5 addon against the stand-in API and checks each kind of line end to end.
--   lua5.1 wotlk/tests/run.lua      (from the repository root)

local H = dofile("wotlk/tests/harness.lua")
H.cvars = { Sound_EnableMusic = "1", Sound_MusicVolume = "0.4", checkAddonVersion = "1", Sound_EnableAllSound = "1" }

local failures, passes = 0, 0
local function check(cond, what)
	if cond then passes = passes + 1 else failures = failures + 1; print("FAIL: " .. what) end
end

-- A quest pack shaped as pipelines/quests/tts_cli/build.py writes it (MODULE_LUA + tables).
local function FakeQuestPack()
	local name = "SpokenQuestsAudioAlliance"
	assert(loadstring([==[
if not VoiceOver or not VoiceOver.DataModules then return end
SpokenQuestsAudioAlliance = {}
function SpokenQuestsAudioAlliance:GetSoundPath(fileName, event)
    setfenv(1, VoiceOver)
    if Enums.SoundEvent:IsQuestEvent(event) then
        return format([[generated\sounds\quests\%s.mp3]], fileName)
    elseif Enums.SoundEvent:IsGossipEvent(event) then
        return format([[generated\sounds\gossip\%s.mp3]], fileName)
    elseif Enums.SoundEvent.QuestFollowup and event == Enums.SoundEvent.QuestFollowup then
        return format([[generated\sounds\followup\%s.mp3]], fileName)
    end
end
VoiceOver.DataModules:Register("SpokenQuestsAudioAlliance", SpokenQuestsAudioAlliance)
]==]))()
	local m = SpokenQuestsAudioAlliance
	m.QuestIDLookup = {
		accept = { ["Kobold Camp Cleanup"] = 7, ["A Shared Title"] = { ["Marshal McBride"] = 783, ["Someone Else"] = 9999 } },
		complete = { ["Kobold Camp Cleanup"] = 7 },
	}
	m.NPCIDLookupByQuestID = { [7] = 197, [783] = 197 }
	m.NPCNameLookupByNPCID = { [197] = "Marshal McBride", [253] = "William Pestle" }
	m.SoundLengthLookupByFileName = {
		["7-accept"] = 12.5, ["7-complete"] = 6, ["783-accept"] = 9,
		["0123456789abcdef0123456789abcdef"] = 4.2, ["1851-human-male-standard"] = 3, ["7133-human-male-standard"] = 2.5,
	}
	m.GossipLookupByNPCID = { [197] = { ["Hey, citizen! You look like a stout one."] = "0123456789abcdef0123456789abcdef" } }
	m.FollowupLookup = { [253] = { [1851] = "1851-human-male-standard" }, [103] = { [7133] = "7133-human-male-standard" } }
	return name
end

-- The voice packs as the addon list shows them.
H.addons = {
	{ name = "Spoken", loaded = true, meta = { Version = "3.8.4-wotlk.1" } },
	{ name = "SpokenQuestsAudioAlliance", lod = true,
		meta = { ["X-SpokenQuests-DataModule-Version"] = "1", ["X-SpokenQuests-DataModule-Priority"] = "100", Version = "2.5.0", ["X-Child-Of"] = "Spoken_Quests" },
		load = FakeQuestPack },
	{ name = "SpokenPlacesAudio", loaded = true, meta = { ["X-Child-Of"] = "Spoken_Places", ["X-SpokenPlaces-Language"] = "enUS" } },
	{ name = "SpokenReadablesAudio", loaded = true, meta = { ["X-Child-Of"] = "Spoken_Readables" } },
	{ name = "SpokenBossesAudio", loaded = true, meta = { ["X-Child-Of"] = "Spoken_Bosses" } },
}

-- The addon, then the non-LoD packs (the client loads those itself, in any order).
H.loadToc("wotlk/Spoken", "Spoken", {})
assert(loadfile("addons/SpokenPlacesAudio/Data/Sounds.lua"))("SpokenPlacesAudio")
assert(loadfile("addons/SpokenReadablesAudio/Data/Sounds.lua"))("SpokenReadablesAudio")
SpokenBossesAudioPacks = { SpokenBossesAudio = { addon = "SpokenBossesAudio", language = "enUS",
	bosses = { [34] = { ["hamhock"] = { file = "34\\hamhock", len = 40 } } } } }

H.fire("ADDON_LOADED", "Spoken")
H.fire("PLAYER_LOGIN")
local S = Spoken

check(S.Quests.DataModules:Count() == 1, "the quest pack registers")
check(#H.find("LoadAddOn", "SpokenQuestsAudioAlliance") == 1 and H.find("LoadAddOn")[1][3] == "0", "the quest pack loads with the version check off")
check(H.cvars.checkAddonVersion == "1", "the version check is restored")
check(H.panel ~= nil, "the settings page is added")

-- Quest accepted from an NPC: found by title, played on the music channel.
H.reset()
H.units.npc = { guid = "0xF1300000C5000123", name = "Marshal McBride", sex = 2 }
H.questTitle, H.questText = "Kobold Camp Cleanup", "Your first task is one of cleansing, $N."
H.fire("QUEST_DETAIL")
local cur = S.Sound:Current()
check(cur and cur.questID == 7, "QUEST_DETAIL finds quest 7 by title")
check(cur and cur.path == [[Interface\AddOns\SpokenQuestsAudioAlliance\generated\sounds\quests\7-accept.mp3]], "the accept line's path: " .. tostring(cur and cur.path))
check(cur and cur.npcID == 197, "the speaker's creature id comes from the 3.3.5 GUID")
check(H.cvars.Sound_MusicVolume ~= "0.4" or #H.find("PlayMusic") == 0, "the music fades before the line")
H.advance(0.6)
check(#H.find("PlayMusic", "7-accept.mp3") == 1, "the line plays as music after the fade")
check(tonumber(H.cvars.Sound_MusicVolume) == 1, "the voice volume is set for the line")
-- The same window again (redrawn) does not queue the line twice.
H.fire("QUEST_DETAIL")
check(S.Sound:Count() == 0, "the same quest is not queued twice")
-- The line ends: silence cuts it, and the music comes back.
H.reset()
H.advance(13)
check(#H.find("PlayMusic", "silence.wav") >= 1, "silence cuts the line when it ends")
H.advance(1)
check(S.Sound:Current() == nil, "the queue is empty afterwards")
check(H.cvars.Sound_MusicVolume == "0.4" and H.cvars.Sound_EnableMusic == "1", "the music settings come back: " .. tostring(H.cvars.Sound_MusicVolume))
check(#H.find("StopMusic") == 1, "the script music is stopped so zone music returns")

-- A title several quests share: told apart by the giver's name.
H.questTitle = "A Shared Title"
H.fire("QUEST_DETAIL")
cur = S.Sound:Current()
check(cur and cur.questID == 783, "a shared title is told apart by its giver")
S.Sound:StopAll()

-- Stop during a line cuts it at once.
H.reset()
H.questTitle = "Kobold Camp Cleanup"
H.fire("QUEST_COMPLETE")
H.advance(1)
check(#H.find("PlayMusic", "7-complete.mp3") == 1, "QUEST_COMPLETE plays the complete line")
S.Sound:StopAll()
check(#H.find("PlayMusic", "silence.wav") >= 1, "Stop cuts the line")

-- Gossip, matched loosely against the pack's text.
H.reset()
H.now = H.now + 10
H.gossipText = "Hey, citizen!  You look like a stout one."
H.fire("GOSSIP_SHOW")
cur = S.Sound:Current()
check(cur and cur.kind == "gossip" and cur.path:find("gossip\\0123456789abcdef", 1, true), "gossip text finds its line")
S.Sound:StopAll()

-- Follow-up: armed by the turn-in, matched in the speaker's chat.
H.reset()
VoiceOver.FollowupLines = VoiceOver.FollowupLines or {}
S.Quests.currentQuestID = 112
GetQuestReward(1)
H.fire("CHAT_MSG_MONSTER_SAY", "This shouldn't take long...", "William Pestle")
cur = S.Sound:Current()
check(cur and cur.kind == "followup" and cur.path:find("followup\\1851", 1, true), "a follow-up line plays after the turn-in")
S.Sound:StopAll()

-- World chatter by the speaker's name.
H.now = H.now + 100
H.fire("CHAT_MSG_MONSTER_SAY", "I see those fools at the Abbey sent some fresh meat for us.", "Garrick Padfoot")
cur = S.Sound:Current()
check(cur and cur.kind == "chatter", "world chatter plays by speaker name")
S.Sound:StopAll()

-- Places: Durotar and Razor Hill by name, first visit only.
H.reset()
H.zone, H.subzone = "Durotar", "Razor Hill"
H.fire("ZONE_CHANGED_NEW_AREA")
H.advance(2.5)
cur = S.Sound:Current()
check(cur and cur.kind == "place" and cur.path:find("SpokenPlacesAudio\\Sounds\\1411\\zone.mp3", 1, true), "entering Durotar tells its story: " .. tostring(cur and cur.path))
check(S.Sound:Count() == 1, "Razor Hill waits behind it")
S.Sound:StopAll()
H.advance(1)
H.fire("ZONE_CHANGED")
H.advance(2.5)
-- StopAll dropped Razor Hill before it started, so it is still unheard and comes again; Durotar does not.
cur = S.Sound:Current()
check(cur and cur.path:find("razor-hill", 1, true) and S.Sound:Count() == 0, "a heard zone is not told again")
S.Sound:StopAll()
-- The Barrens: "The" is dropped on both sides.
H.zone, H.subzone = "The Barrens", "The Crossroads"
H.fire("ZONE_CHANGED_NEW_AREA")
H.advance(2.5)
cur = S.Sound:Current()
check(cur and cur.path:find("\\1413\\zone", 1, true), "The Barrens is found: " .. tostring(cur and cur.path))
S.Sound:StopAll()

-- Readables: a two-page letter by title, page and checksum.
H.reset()
local page = SpokenReadablesData.pages[16]
H.itemTitle, H.itemPage, H.itemText = "A Dusty Unsent Letter", 1, page.text
H.fire("ITEM_TEXT_READY")
cur = S.Sound:Current()
check(cur and cur.key == "page:16", "a page is found by its checksum")
check(S.Sound:Count() == 1 and S.Sound.queue[1].key == "page:17", "the rest of the book is queued")
S.Sound:StopAll()
-- The server's text differs a little: the closest page of the title.
H.itemText = page.text:gsub("Headmaster", "Head Master")
H.now = H.now + 10
H.fire("ITEM_TEXT_READY")
cur = S.Sound:Current()
check(cur and cur.key == "page:16", "a page with changed words is found by its words")
S.Sound:StopAll()

-- Bosses: Hamhock (Stockade, creature 1717) dies.
H.reset()
H.zone = "The Stockade"
local hamhockID
for key, info in pairs(SpokenBossCreatures[34]) do if key == "hamhock" then hamhockID = info.creature end end
H.fire("COMBAT_LOG_EVENT_UNFILTERED", 1, "UNIT_DIED", "0x0", nil, 0, format("0xF130%06X000077", hamhockID))
H.advance(3.2)
cur = S.Sound:Current()
check(cur and cur.kind == "boss" and cur.text and cur.text:find("ogre"), "a boss's story is told when it dies")
S.Sound:StopAll()

-- Subtitles: a long line pages and types out.
H.reset()
S.db.style = "subtitles"
local long = string.rep("This is a long sentence that keeps going for a while. ", 20)
S.Sound:Enqueue({ kind = "gossip", path = "x.mp3", len = 40, name = "Tester", text = long })
H.advance(1)
check(SpokenSubtitles and SpokenSubtitles.shown, "subtitles show while a line plays")
local first = SpokenSubtitles.text.text
H.advance(30)
check(SpokenSubtitles.text.text ~= first and #SpokenSubtitles.text.text > 0, "a long line turns its pages")
S.Sound:StopAll()
check(not SpokenSubtitles.shown, "subtitles hide when the queue empties")

-- Window style.
S.db.style = "window"
S.Sound:Enqueue({ kind = "quest", path = "y.mp3", len = 5, name = "Marshal McBride", text = "Hello", npcID = 197 })
H.advance(1)
check(SpokenWindow and SpokenWindow.shown and not SpokenSubtitles.shown, "the small window shows instead")
S.Sound:StopAll()

-- The story panel on the world map: Tirisfal Glades, then a click on Brill.
S.db.style = "subtitles"
H.map.continent, H.map.zone = 2, 1
SpokenMapStory:Show()
SpokenMapStory.scripts.OnShow()
check(SpokenMapStory.title.text == "Tirisfal Glades", "the map panel shows the map's zone: " .. tostring(SpokenMapStory.title.text))
check(SpokenMapStory.text.text:find("Lordaeron", 1, true), "with its story")
check(SpokenMapStory.list and #SpokenMapStory.list > 3, "and its places")
WorldMapFrameAreaLabel.text = "Brill"
WorldMapButton.scripts.OnMouseUp(WorldMapButton, "LeftButton")
check(SpokenMapStory.title.text == "Brill", "a click on a place shows its story")
SpokenMapStory.play.scripts.OnClick()
cur = S.Sound:Current()
check(cur and cur.key == "s:1420:brill", "Play reads the place shown: " .. tostring(cur and cur.key))
S.Sound:StopAll()
-- /sp place while the story already plays says so, not "no recording".
H.reset()
H.zone, H.subzone = "Tirisfal Glades", ""
SlashCmdList.SPOKEN("place")
SlashCmdList.SPOKEN("place")
check(#H.find("print", "already playing") == 1, "/sp place says when the story is already playing")
S.Sound:StopAll()

-- Slash commands do not error.
for _, cmd in ipairs({ "", "status", "help", "place", "replay", "stop", "stopall", "style voice", "debug", "debug" }) do
	SlashCmdList.SPOKEN(cmd)
end
check(S.db.style == "voice", "/sp style sets the narrator")

print(format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
