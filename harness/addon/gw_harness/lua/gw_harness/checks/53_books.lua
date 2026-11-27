-- Books (books): the removed example books are gone and the rest remain.

GWH.Check("removed book items are gone and books remain", function(fail)
	for _, uniqueID in ipairs({"bookexample", "dustytestbook", "book_stillirise"}) do
		if (ix.item.list[uniqueID]) then fail(uniqueID .. " is still registered") end
	end

	local books = 0

	for _, item in pairs(ix.item.list) do
		if (item.base == "base_books") then books = books + 1 end
	end

	if (books < 50) then fail("only " .. books .. " book items remain, expected at least 50") end

	return {books = books}
end)
