-- Books, letters, plaques and the rest, from SpokenReadablesAudio.
--
-- A page is found as upstream's Reader.lua finds it: the title, the page number and a
-- checksum of the page's text (Upstream/Readables/Checksum.lua) in SpokenReadablesData.index,
-- then the checksums no other page shares, then the closest page of the same title by its
-- words. The packs register themselves into SpokenReadablesAudioPacks.

local ns = Spoken
local Readables = ns:RegisterModule("Readables", {})
ns.Readables = Readables

local function Packs()
	local list = {}
	for _, pack in pairs(SpokenReadablesAudioPacks or {}) do
		if type(pack) == "table" and pack.pages then list[#list + 1] = pack end
	end
	return list
end

function Readables:PackCount() return #Packs() end

function Readables:Clip(pageID)
	for _, pack in ipairs(Packs()) do
		local entry = pack.pages[pageID]
		if entry and entry.file then
			return "Interface\\AddOns\\" .. pack.addon .. "\\Sounds\\" .. entry.file .. ".mp3", entry.len
		end
	end
end

local function Find(data, title, number, checksum)
	local byTitle = title and data.index and data.index[title]
	local found = byTitle and byTitle[number] and byTitle[number][checksum]
	return found or (data.loose and data.loose[checksum])
end

-- The page of this title and number whose words are closest to what is on screen.
local function Closest(data, title, number, text)
	local words = ns:Words(ns:FillTokens(text))
	local byTitle = data.index and data.index[title]
	local candidates = {}
	if byTitle and byTitle[number] then
		for _, id in pairs(byTitle[number]) do candidates[#candidates + 1] = id end
	elseif byTitle then
		for _, byNumber in pairs(byTitle) do
			for _, id in pairs(byNumber) do candidates[#candidates + 1] = id end
		end
	end
	local best, bestScore
	for _, id in ipairs(candidates) do
		local page = data.pages and data.pages[id]
		if page and page.text then
			local score = ns:Similarity(words, ns:Words(ns:FillTokens(page.text)))
			if not bestScore or score > bestScore then best, bestScore = id, score end
		end
	end
	if bestScore and bestScore >= 0.6 then return best end
end

function Readables:PageOnScreen()
	local data = SpokenReadablesData
	if not data then return end
	local text = ItemTextGetText()
	if type(text) ~= "string" or text == "" then return end
	local title = ItemTextGetItem()
	local number = ItemTextGetPage() or 1
	for _, checksum in ipairs({ ns:ChecksumOf(text), ns:MarkedChecksumOf(text) }) do
		local found = Find(data, title, number, checksum)
		if found then return found end
	end
	return Closest(data, title, number, text)
end

-- The pages of a book from `pageID` on, in order.
local function PagesFrom(pageID)
	local data = SpokenReadablesData
	local page = data.pages[pageID]
	if not page or not page.book then return { pageID } end
	local list = {}
	for id, p in pairs(data.pages) do
		if p.book == page.book and (p.number or 1) >= (page.number or 1) then
			list[#list + 1] = id
		end
	end
	table.sort(list, function(a, b) return (data.pages[a].number or 1) < (data.pages[b].number or 1) end)
	return list
end

local function BookTitle(pageID)
	local data = SpokenReadablesData
	local page = data.pages[pageID]
	local book = page and page.book and data.books and data.books[page.book]
	return type(book) == "table" and (book.title or book[1]) or ItemTextGetItem()
end

function Readables:QueuePage(pageID, front)
	local path, len = self:Clip(pageID)
	if not path then return false end
	local page = SpokenReadablesData.pages[pageID]
	return ns.Sound:Enqueue({
		kind = "book", path = path, len = len, key = "page:" .. pageID,
		name = BookTitle(pageID), title = page and page.number and ("Page " .. page.number) or nil,
		text = page and page.text and ns:FillTokens(page.text) or ItemTextGetText(),
	}, front)
end

function Readables:ReadOnScreen(asked)
	local pageID = self:PageOnScreen()
	if not pageID then
		if asked then ns:Print("this page is not one Spoken knows.") end
		return
	end
	local pages = (ns.db.readWholeBook and PagesFrom(pageID)) or { pageID }
	local queued = 0
	for _, id in ipairs(pages) do
		if self:QueuePage(id) then queued = queued + 1 end
	end
	if asked and queued == 0 then
		ns:Print("no recording of this page is installed.")
	end
end

function Readables:Enable()
	ns:On("ITEM_TEXT_READY", function()
		if ns.db.readables and ns.db.autoplayReadables then
			Readables:ReadOnScreen(false)
		end
	end)
	ns:On("ITEM_TEXT_CLOSED", function()
		if ns.db.stopBookOnClose then ns.Sound:Remove(nil, "book") end
	end)
end
