ITEM.name = "Book Base"
ITEM.model = "models/props_lab/bindergreen.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.description = "It's a book, duh."
ITEM.category = "Books"
ITEM.title = ""
ITEM.text = ""

local html_code = [[
<html>
     <body style="background-color: #f0f0f0; color: #000000">
<p style="text-align: center;"><span style="font-size: 
      19px;"><strong><span style="font-family: 
        'Trebuchet MS', Helvetica, sans-serif;">%s</span></strong></span></p>
<hr>
<p><br></p>
<p style="text-align: center;"><span style="font-size: 15px;"><span style='font-family: "Trebuchet MS", Helvetica, sans-serif;'>%s</span></span></p>
       <body>
<html>
]]
-- I don't know HTML, sorry.



ITEM.functions.read = { 
	name = "Read",
	icon = "icon16/book_open.png",
    
    OnClick = function(itemTable)
         local frame = vgui.Create("DFrame")
		 frame:SetSize(500, 600)
		 frame:SetTitle(itemTable.name)
		 frame:MakePopup()
		 frame:Center()
 
		 local html = vgui.Create("DHTML", frame)
		 html:SetHTML(string.format(html_code, itemTable.title, itemTable.text))
         html:Dock(FILL)
    end,

	OnRun = function()
		return false
	end
}

