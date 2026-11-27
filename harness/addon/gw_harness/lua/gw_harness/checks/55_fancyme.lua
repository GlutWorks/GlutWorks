-- Fancy /me (fancyme): the chat classes are registered and read their range at send time.

GWH.Check("fancy /me chat classes are registered and read their range at send time", function(fail)
	local expected = {mey = "/MeY", ity = "/ItY", mew = "/MeW", itw = "/ItW", mel = "/MeL", itl = "/ItL"}

	for class, prefix in pairs(expected) do
		local data = ix.chat.classes[class]

		if (!data) then
			fail(class .. " is not registered")
		elseif (!table.HasValue(data.prefix or {}, prefix)) then
			fail(class .. " does not have the prefix " .. prefix)
		end
	end

	-- CanHear only needs GetPos, so plain tables stand in for the two players.
	local speaker = {GetPos = function() return Vector(0, 0, 0) end}
	local listener = {GetPos = function() return Vector(50, 0, 0) end}
	local wClass = ix.chat.classes.mew

	if (!wClass) then return end

	local original = ix.config.Get("chatActionWRange", 75)

	ix.config.Set("chatActionWRange", 75)
	if (wClass:CanHear(speaker, listener) != true) then fail("50 units is not within a 75 unit whisper range") end

	ix.config.Set("chatActionWRange", 10)
	if (wClass:CanHear(speaker, listener) != false) then fail("whisper range change was not picked up") end

	ix.config.Set("chatActionWRange", original)
end)
