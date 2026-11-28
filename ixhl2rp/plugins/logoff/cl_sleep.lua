
local PLUGIN = PLUGIN

-- How often bodies are looked over for having fallen asleep or died (seconds).
PLUGIN.scanInterval = 0.25

local function OpenSearch(body)
	net.Start("ixLogoffSearch")
		net.WriteEntity(body)
	net.SendToServer()
end

-- A sleeping body is something you can go through, like any interactive thing: tapping Use searches it, and a
-- look at it says it sleeps and what it looks like.
local asleep = {
	bInteractive = true,

	GetInteractionTap = function(body, client)
		return "Search", function()
			OpenSearch(body)
		end
	end,

	OnPopulateEntityInfo = function(body, container)
		local name = container:AddRow("name")
		name:SetImportant()
		name:SetText("Asleep")
		name:SizeToContents()

		local description = body:GetNetVar("asleep", "")

		if (description != "") then
			local row = container:AddRow("description")
			row:SetText(description)
			row:SizeToContents()
		end
	end
}

local function SetAsleep(body, bAsleep)
	body.ixLogoffAsleep = bAsleep or nil

	for key, value in pairs(asleep) do
		body[key] = bAsleep and value or nil
	end
end

-- A ragdoll's net var says when it sleeps; a dead one is a corpse like any other.
function PLUGIN:Think()
	if ((self.nextScan or 0) > CurTime()) then
		return
	end

	self.nextScan = CurTime() + self.scanInterval

	for _, body in ipairs(ents.FindByClass("prop_ragdoll")) do
		local bAsleep = body:GetNetVar("asleep") != nil

		if (bAsleep != (body.ixLogoffAsleep == true)) then
			SetAsleep(body, bAsleep)
		end
	end
end
