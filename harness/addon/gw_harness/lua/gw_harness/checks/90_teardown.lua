-- Teardown, after every feature file: kicks the second bot (GWH.hygieneBot) that the doors, writing, admin tools,
-- mynotes and schema checks share. A check that runs after this and needs it again gets a new one.

GWH.Check("hygiene: teardown", function()
	if (IsValid(GWH.hygieneBot)) then
		GWH.hygieneBot:Kick("hygiene checks finished")
		GWH.hygieneBot = nil
	end
end)
