local PLUGIN = PLUGIN
PLUGIN.name = "Application System"
PLUGIN.author = "ZeMysticalTaco"
PLUGIN.description = "Adds an immersive and realistic IC application system."

ix.command.Add("ViewApplications", {
	description = "Review the applications submitted at application terminals.",
	adminOnly = true,
	OnRun = function(self, client)
		PLUGIN:SendApplicationList(client)
	end
})

if (CLIENT) then
	netstream.Hook("SyncApplicationDataCP", function(data)
		local ui = vgui.Create("CPApplicationMenu")
		ui.sqldata = data[1]
	end)

	-- one application's full text, requested from the list
	netstream.Hook("ApplicationDetail", function(row)
		if (!istable(row)) then
			return
		end

		local ui = vgui.Create("CPApplicationMenuViewer")
		ui.data = {
			["name"] = row.name,
			["id"] = row.cid,
			["date"] = row.date,
			["appinfo"] = row
		}
	end)

	netstream.Hook("OpenApplicationMenu", function()
		vgui.Create("CPApplicationIntro")
	end)

	-- data: response, delivered live (true) or on load (false), accepted, applicant name, application id
	netstream.Hook("ApplicationPlayerResponse", function(data)
		if (!istable(data) or !isstring(data[1]) or !isstring(data[4])) then
			return
		end

		local reason, bLive, name, appID = data[1], data[2], data[4], data[5]
		local bAccepted = reason == "!true"
		local intro, letter

		if (bLive) then
			intro = "It's been awhile since you submitted your application, but the day is finally here, in your hands you clutch the letter, the response. Not another bill like all the other letters have been, this is it. You hold in your hand a standard letter, with a UU Logo and a stamp marked 'Priority Mail' on it. You've been walking around with it in your hand but you decide now is the time to open it.\nYou carefully open the letter, careful not to damage it's casing. You think to yourself about taking the letter and putting it on a shelf.\nInside is a small letter-sized piece of paper, folded into three creases as all letter-stock papers are. You unfold it, and read:\n"
			letter = bAccepted and "Hello " .. name .. " Thank you for your interest in applying for the Combine Civil Authority, we have reviewed your application thoroughly and have come to a conclusion. With your skills, experience and expertise, we have decided to pass you for stage 1 of the application process. The next step is a face-to-face interview with a senior officer. Please take this letter to the nearest Officer and they will escort you inside The Nexus to speak with them. \nThank you for your interest in applying. \n~Combine Civil Authority Command" or "Hello " .. name .. " Thank you for your interest in applying for the Combine Civil Authority, we have reviewed your application thoroughly and have come to a conclusion. At this time you do not fit the expectations of an officer of the CCA, as such we have terminated your application and it has been denied for the reason: '" .. reason .. "', we apologize for the inconvenience. \nThank you for your interest in applying. \n~Combine Civil Authority Command"
		else
			intro = "It's been awhile since you submitted your application, time goes by and you wonder really, What is going to happen? Your mind races with the possibilites from the best, to the worst. As you are walking along skulking to yourself in anxiety about whether or not the results are positive, a courier from the Civil Workers' Union approaches you, he asks you, 'You're " .. name .. " right? I have a letter for you, from the Union, marked priority mail, just got it in today. Good luck on whatever's inside, friend."
			letter = bAccepted and "\n Before you can say a word the Courier rushes off, you stare at the letter, deciding to open it. Inside is a piece of paper, folded in standard letter stock format. It reads: 'Hello " .. name .. " and thank you for applying for the Combine Civil Authority, we have reviewed your application thoroughly and have come to a conclusion. With your skills, experience and expertise, we have decided to pass you for stage 1 of the application process. The next step is a face-to-face interview with a senior officer. Please take this letter to the nearest Officer and they will escort you inside The Nexus to speak with them. \nThank you for your interest in applying. \n~Combine Civil Authority Command" or "\n Before you can say a word the Courier rushes off, you stare at the letter, deciding to open it. Inside is a piece of paper, folded in standard letter stock format. It reads: 'Hello " .. name .. " and thank you for applying for the Combine Civil Authority, we have reviewed your application thoroughly and have come to a conclusion. At this time you do not fit the expectations of an officer of the CCA, as such we have terminated your application and it has been denied for the reason: '" .. reason .. "', we apologize for the inconvenience. \nThank you for your interest in applying. \n~Combine Civil Authority Command"
		end

		local frame = vgui.Create("DFrame")
		frame:SetSize(ScrW() / 4, ScrH() / 3)
		frame:Center()
		frame:MakePopup()
		frame:SetBackgroundBlur(true)
		frame:ShowCloseButton(false)
		frame.TitleText = frame:Add("DLabel")
		frame.TitleText:Dock(TOP)
		frame.TitleText:SetContentAlignment(5)
		frame.TitleText:SetFont("ixBigFont")
		frame.TitleText:SetText("A Passing Letter.")
		frame.TitleText:SizeToContents()
		frame.EventText = frame:Add("DLabel")
		frame.EventText:Dock(TOP)
		frame.EventText:SetWrap(true)
		frame.EventText:SetAutoStretchVertical(true)
		frame.EventText:SetText(intro)
		frame.EventText:SetFont("ixSmallFont")
		frame.PanelList = frame:Add("DPanelList")
		frame.PanelList:Dock(FILL)
		frame.PanelList:EnableVerticalScrollbar(true)
		frame.EventText2 = frame:Add("DLabel")
		frame.EventText2:Dock(TOP)
		frame.EventText2:SetWrap(true)
		frame.EventText2:SetAutoStretchVertical(true)
		frame.EventText2:SetText(letter)
		frame.EventText2:SetFont("ixSmallFont")
		frame.PanelList:AddItem(frame.EventText)
		frame.PanelList:AddItem(frame.EventText2)
		frame.AcceptButton = frame:Add("DButton")
		frame.AcceptButton:SetText("...Is this really happening?")
		frame.AcceptButton:Dock(BOTTOM)

		function frame.AcceptButton:DoClick()
			self:GetParent():Close()
			netstream.Start("ApplicationSeen", {"cp", bAccepted, appID, name})
		end
	end)
end

ix.util.Include("cl_panels.lua")
ix.util.Include("sv_plugin.lua")
