-- Playing a line, and the queue of lines waiting.
--
-- 3.3.5's PlaySoundFile cannot be stopped short of restarting the whole sound system. PlayMusic
-- can be: StopMusic fades it, and playing another file as music cuts it at once. So a line is
-- played as music, the way AI_VoiceOver's 3.3.5 backport (public domain) does it:
--   1. the game music fades to 0 over db.fadeMusic seconds,
--   2. Sound_EnableMusic is toggled off and on, which cuts the zone music at once,
--   3. the music volume is set to the voice volume and the line plays with PlayMusic,
--   4. when the line's length has run out, silence.wav is played as music, which cuts the
--      line before PlayMusic loops it,
--   5. when the queue is empty the music volume fades back and the player's settings return.
-- Music that was switched off is switched on only while a line plays.
-- With db.playOnMusicChannel off, a line plays as a sound and cannot be stopped.

local ns = Spoken
local Sound = ns:RegisterModule("Sound", {})
ns.Sound = Sound

local SILENCE = [[Interface\AddOns\Spoken\Sounds\silence.wav]]

--------------------------------------------------------------------------------
-- The music channel
--------------------------------------------------------------------------------

local saved -- { enable, volume } while a line holds the music channel
local slide -- { target, rate, done }

local function MusicVolume()
	return tonumber(GetCVar("Sound_MusicVolume")) or 1
end

local function Hold()
	if not saved then
		saved = { enable = GetCVar("Sound_EnableMusic"), volume = GetCVar("Sound_MusicVolume") }
		SetCVar("Sound_EnableMusic", 1)
	end
end

local function Release()
	if saved then
		SetCVar("Sound_EnableMusic", saved.enable)
		SetCVar("Sound_MusicVolume", saved.volume)
		saved = nil
	end
end

local function FadeDuration()
	if not saved or tonumber(saved.enable) == 0 or tonumber(saved.volume) == 0 then
		return 0
	end
	return ns.db.fadeMusic or 0
end

--- Slides the music volume to `target`, then calls done. Returns false when it changed at once.
local function Slide(target, done)
	local duration = FadeDuration()
	local current = MusicVolume()
	if duration <= 0 or math.abs(target - current) < 0.01 then
		slide = nil
		return false
	end
	slide = { target = target, rate = (target - current) / duration, done = done }
	return true
end

local slideFrame = CreateFrame("Frame")
slideFrame:SetScript("OnUpdate", function(_, elapsed)
	if not slide then return end
	local current = MusicVolume()
	local nextValue = current + slide.rate * elapsed
	local finished = math.abs(slide.target - current) < 0.01
		or (slide.rate < 0 and nextValue <= slide.target)
		or (slide.rate > 0 and nextValue >= slide.target)
	if finished then nextValue = slide.target end
	SetCVar("Sound_MusicVolume", nextValue)
	if finished then
		local done = slide.done
		slide = nil
		if done then done() end
	end
end)

ns:On("PLAYER_LOGOUT", function()
	slide = nil
	if saved then
		PlayMusic(SILENCE)
		StopMusic()
	end
	Release()
end)

--------------------------------------------------------------------------------
-- One line
--------------------------------------------------------------------------------

local current      -- the item playing
local cutTimer     -- cuts the line when its length runs out
local endTimer     -- moves the queue on
local onChannel    -- whether the music channel is held for lines

local function StartPlayback(item)
	item.startedAt = GetTime()
	if not ns.db.playOnMusicChannel then
		PlaySoundFile(item.path, "Master")
		return
	end
	local function Play()
		if current ~= item then return end -- skipped or stopped while the music faded
		SetCVar("Sound_EnableMusic", 0)
		SetCVar("Sound_EnableMusic", 1)
		SetCVar("Sound_MusicVolume", ns.db.volume)
		PlayMusic(item.path)
		item.startedAt = GetTime()
		cutTimer = ns.After(item.len, function() PlayMusic(SILENCE) end)
		if Sound.OnStarted then Sound:OnStarted(item) end
	end
	if not onChannel then
		onChannel = true
		Hold()
		if Slide(0, Play) then
			item.delay = FadeDuration()
			return true
		end
	end
	Play()
end

local function CutLine()
	if cutTimer then cutTimer:Cancel(); cutTimer = nil end
	if endTimer then endTimer:Cancel(); endTimer = nil end
	if ns.db.playOnMusicChannel and onChannel then
		PlayMusic(SILENCE)
	end
end

local function ReleaseChannel()
	if not onChannel then return end
	onChannel = false
	PlayMusic(SILENCE)
	SetCVar("Sound_MusicVolume", 0)
	local function Resume()
		StopMusic()
		Release()
	end
	if not Slide(tonumber(saved and saved.volume) or 1, Resume) then
		Resume()
	end
end

--------------------------------------------------------------------------------
-- The queue
--------------------------------------------------------------------------------

local queue = {}
local history -- the last item played, for Replay

Sound.queue = queue

--- An item: { path, len, key, kind ("quest", "gossip", "chatter", "book", "place", "boss"),
---   name (speaker), title, text, unitGUID, npcID, displayID, onStart(item) }.
--- `key` keeps the same line from queueing twice; it defaults to the path.
--- `front` plays it next instead of last; `interrupt` stops what is playing first.
function Sound:Enqueue(item, front, interrupt)
	if type(item.path) ~= "string" or not item.len then return false end
	item.key = item.key or item.path
	if current and current.key == item.key then return false end
	for _, queued in ipairs(queue) do
		if queued.key == item.key then return false end
	end
	if #queue >= (ns.db.maxQueue or 8) then
		table.remove(queue) -- drop the newest waiting line, never the one playing
	end
	if front then
		table.insert(queue, 1, item)
	else
		table.insert(queue, item)
	end
	if interrupt and current then
		self:Skip()
	elseif not current then
		self:Next()
	end
	self:Changed()
	return true
end

function Sound:Next()
	CutLine()
	current = table.remove(queue, 1)
	if not current then
		ReleaseChannel()
		self:Changed()
		return
	end
	history = current
	local item = current
	if item.onStart then pcall(item.onStart, item) end
	local delayed = StartPlayback(item)
	endTimer = ns.After((item.delay or 0) + item.len + 0.3, function()
		if current == item then
			Sound:Next()
		end
	end)
	if not delayed and not ns.db.playOnMusicChannel and Sound.OnStarted then
		Sound:OnStarted(item)
	end
	self:Changed()
end

--- Stops the line playing and plays the next one.
function Sound:Skip()
	if current then
		current = nil
		self:Next()
	end
end

--- Stops everything and empties the queue.
function Sound:StopAll()
	wipe(queue)
	current = nil
	CutLine()
	ReleaseChannel()
	self:Changed()
end

--- Removes one item (playing or waiting) by key, or every item of a kind.
function Sound:Remove(key, kind)
	for i = #queue, 1, -1 do
		local q = queue[i]
		if (key and q.key == key) or (kind and q.kind == kind) then
			table.remove(queue, i)
		end
	end
	if current and ((key and current.key == key) or (kind and current.kind == kind)) then
		self:Skip()
	end
	self:Changed()
end

--- Plays the last line again.
function Sound:Replay()
	if history then
		local item = {}
		for k, v in pairs(history) do item[k] = v end
		item.key = (item.key or item.path) .. "#replay" .. GetTime()
		self:Enqueue(item, true, true)
	end
end

function Sound:Current()
	return current
end

function Sound:Count()
	return #queue
end

--- Seconds into the current line, and its length.
function Sound:Progress()
	if not current or not current.startedAt then return 0, current and current.len or 0 end
	local elapsed = GetTime() - current.startedAt
	if elapsed < 0 then elapsed = 0 end
	return math.min(elapsed, current.len), current.len
end

--- Whether the line was played so it can be stopped.
function Sound:CanStop()
	return ns.db.playOnMusicChannel
end

-- Listeners: the UI redraws through these.
local listeners = {}
function Sound:Listen(fn) table.insert(listeners, fn) end
function Sound:Changed()
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, current, queue)
		if not ok then geterrorhandler()(err) end
	end
end
function Sound:OnStarted(item)
	for _, fn in ipairs(listeners) do pcall(fn, current, queue, item) end
end
