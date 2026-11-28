local PLUGIN = PLUGIN

--[[
What the intake desk takes as a name. A first and a last name (a middle one allowed), of letters only
(an apostrophe or a hyphen inside a word), each word 2 to 20 letters with a vowel and no letter three
times running, nothing on the refused list below, and not a living character's. It is written down as
names are: as typed when they've shaped it ("McKay"), else with a capital first and after each hyphen or
apostrophe ("O'Neil", "Smith-Jones").
]]

-- What's refused, a word to a line (`#` notes): a word is refused as a whole word of a name; `*word`
-- wherever it is in one; a line of two or more words, as the whole name. Real names that merely
-- contain a crude word (Hitchcock, Cockburn, Dickens) must stay possible, so keep * for what's never
-- part of one.
PLUGIN.refusedText = [[
# Crude
*fuck
*shit
*cunt
*penis
*vagina
*dildo
*poop
*boner
*jizz
cock
dick
cum
sex
anal
ass
arse
butt
boob
boobs
tits
titty
fart
pee
piss
poo
turd
crap
bitch
whore
slut
rape
rapist
porn
horny
nipple
balls
nuts
weed
bong
yolo
lol
lmao
xd
noob
sniper
gamer

# Slurs
*nigg
*fagg
fag
kike
spic
chink
gook
retard
tranny
dyke

# Joke names
mike hunt
mike oxlong
hugh jass
hugh janus
ben dover
joe mama
amanda hugginkiss
seymour butz
ivana tinkle
moe lester
phil mccracken
dixie normous

# The famous, and those who'd pretend to be them
hitler
stalin
mussolini
adolf hitler
joseph stalin
osama bin laden
jesus christ
god
satan
lucifer
donald trump
joe biden
barack obama
elon musk

# Half-Life's own people: the city has them already, or they're a joke
gordon freeman
alyx vance
eli vance
isaac kleiner
wallace breen
judith mossman
barney calhoun
g man
]]

-- Why a name is refused, and what the clerk says of it.
PLUGIN.refusals = {
	oneWord = "First and last.",
	tooMany = "Just your name. First and last.",
	notLetters = "Letters only. Your name.",
	tooShortOrLong = "That's not a name. Again.",
	notAName = "Don't waste my time. Your real name.",
	taken = "There's someone by that name already. Another."
}

-- The refused list, read once: words refused whole, words refused inside a word, and whole names.
function PLUGIN:GetRefused()
	if (self.refused) then
		return self.refused
	end

	local refused = {words = {}, inside = {}, names = {}}

	for line in self.refusedText:gmatch("[^\n]+") do
		line = string.Trim((line:match("^([^#]*)") or "")):utf8lower()

		if (line != "") then
			if (line:sub(1, 1) == "*") then
				refused.inside[#refused.inside + 1] = line:sub(2)
			elseif (line:find(" ", 1, true)) then
				refused.names[table.concat(string.Explode("%s+", line, true), " ")] = true
			else
				refused.words[line] = true
			end
		end
	end

	self.refused = refused

	return refused
end

local function IsLetter(code)
	return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		or (code >= 0xC0 and code <= 0x24F and code != 0xD7 and code != 0xF7)
end

local function IsUpper(code)
	return (code >= 65 and code <= 90) or (code >= 0xC0 and code <= 0xDE and code != 0xD7)
end

-- A word with a capital first letter, and after each hyphen or apostrophe.
local function Capitalised(lower)
	local out, up = {}, true

	for _, code in utf8.codes(lower) do
		local char = utf8.char(code)

		out[#out + 1] = up and char:utf8upper() or char
		up = (char == "-" or char == "'")
	end

	return table.concat(out)
end

--- A name as it's said at the desk, written as it's kept, or false and the refusal's key.
-- `isTaken(name)` says whether a living character has that name already.
function PLUGIN:CheckName(said, isTaken)
	local words = {}

	for word in tostring(said or ""):gmatch("%S+") do
		word = word:gsub("^[%.,!%?\"]+", ""):gsub("[%.,!%?\"]+$", "")

		if (word != "") then
			words[#words + 1] = word
		end
	end

	if (#words < 2) then
		return false, "oneWord"
	elseif (#words > 3) then
		return false, "tooMany"
	end

	local refused = self:GetRefused()
	local kept = {}

	for _, word in ipairs(words) do
		local letters, vowels, codes = 0, 0, {}

		if (!utf8.len(word)) then
			return false, "notLetters"
		end

		for _, code in utf8.codes(word) do
			codes[#codes + 1] = code
		end

		local first, last = utf8.char(codes[1]), utf8.char(codes[#codes])

		if (first == "-" or first == "'" or last == "-" or last == "'") then
			return false, "notLetters"
		end

		for _, code in ipairs(codes) do
			local char = utf8.char(code)

			if (IsLetter(code)) then
				letters = letters + 1

				if (code > 127 or ("aeiouyAEIOUY"):find(char, 1, true)) then
					vowels = vowels + 1
				end
			elseif (char != "-" and char != "'") then
				return false, "notLetters"
			end
		end

		if (letters < 2 or letters > 20) then
			return false, "tooShortOrLong"
		end

		local lower = word:utf8lower()

		if (vowels == 0 or self:ThreeRunning(lower) or refused.words[lower]) then
			return false, "notAName"
		end

		for _, inside in ipairs(refused.inside) do
			if (lower:find(inside, 1, true)) then
				return false, "notAName"
			end
		end

		-- shaped by them ("McKay"): a capital first and another later
		local shaped = IsUpper(codes[1])

		if (shaped) then
			shaped = false

			for k = 2, #codes do
				if (IsUpper(codes[k])) then
					shaped = true
					break
				end
			end
		end

		kept[#kept + 1] = shaped and word or Capitalised(lower)
	end

	local name = table.concat(kept, " ")

	if (refused.names[name:utf8lower()]) then
		return false, "notAName"
	end

	if (isTaken and isTaken(name)) then
		return false, "taken"
	end

	return name
end

-- Whether a word has any letter three times running ("Brrr", "Aaaron").
function PLUGIN:ThreeRunning(lower)
	local previous, run = nil, 0

	for _, code in utf8.codes(lower) do
		if (code == previous) then
			run = run + 1

			if (run >= 3) then
				return true
			end
		else
			previous, run = code, 1
		end
	end

	return false
end
