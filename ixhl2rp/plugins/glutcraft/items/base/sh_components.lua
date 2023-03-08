
ITEM.category = "Components"

if player then
	function ITEM:PaintOver(item, w, h)
		draw.SimpleText(
			item:GetData('quantity', 1).." "..item.stackUnit, 'DermaDefault', w - 5, h - 5,
			color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, color_black
		)
	end
end

if (CLIENT) then
	function ITEM:PopulateTooltip(tooltip)
		local weight = tooltip:AddRow("weight")
		weight:SetText(self:GetData('quantity', 1).." "..self.stackUnit)
		weight:SetTextColor(Color(184, 184, 184))
		weight:SizeToContents()
	end 
end

ITEM.functions.combine = 
{
	name = "Combine",
	icon = "icon16/arrow_join.png",
	OnRun = function(item1, data)
		item2 = ix.item.instances[data[1]]
		if (item1.name == item2.name) then
			sum = item1:GetData('quantity', 1) + item2:GetData('quantity', 1)
			stackLimit = item1.stackLimit
			if (sum > stackLimit) then
				item1:SetData('quantity', stackLimit, ix.inventory.Get(item1.invID):GetReceivers())
				item2:SetData('quantity', sum - stackLimit, ix.inventory.Get(item2.invID):GetReceivers())
			else
				item1:SetData('quantity', sum, ix.inventory.Get(item1.invID):GetReceivers())
				item2:Remove()
			end
		end
	return false
	end,
	OnCanRun = function(item1, data)
		return true
	end
}


ITEM.functions.split = 
{
	name = "Split",
	icon = "icon16/arrow_divide.png",
	OnRun = function(item)
		local quantity = item:GetData('quantity', 1)
		local player = item.player
		player:RequestString('Split', 'Amount', function(amount)
            if (item.stackType == "whole") then
                amount = math.floor(tonumber(amount))
            else
                amount = math.floor(tonumber(amount) * 10 + 0.5) / 10
            end
			if (isnumber(amount) && amount < quantity && amount > 0) then
				if (!player:GetCharacter():GetInventory():AddNoStack(item.uniqueID, 1, {quantity = amount})) then
					ix.item.Spawn(item.uniqueID, player, nil, angle_zero, {quantity = amount})
				end
				item:SetData("quantity", item:GetData('quantity', 1) - amount, ix.inventory.Get(item.invID):GetReceivers())
			else
				player:Notify('Please enter a valid number') 
				return false
			end
		end, '1')
		return false
	end,
	OnCanRun = function(item)
		return true
	end
}
