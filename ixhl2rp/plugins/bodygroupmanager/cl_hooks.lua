
net.Receive("ixBodygroupView", function()
	local target = net.ReadEntity()

	if (IsValid(target)) then
		vgui.Create("ixBodygroupView"):Display(target)
	end
end)
