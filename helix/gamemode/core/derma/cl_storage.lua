
local PANEL = {}

AccessorFunc(PANEL, "money", "Money", FORCE_NUMBER)

function PANEL:Init()
	self:DockPadding(1, 1, 1, 1)
	self:SetTall(64)
	self:Dock(BOTTOM)

	self.moneyLabel = self:Add("DLabel")
	self.moneyLabel:Dock(TOP)
	self.moneyLabel:SetFont("ixGenericFont")
	self.moneyLabel:SetText("")
	self.moneyLabel:SetTextInset(2, 0)
	self.moneyLabel:SizeToContents()
	self.moneyLabel.Paint = function(panel, width, height)
		derma.SkinFunc("DrawImportantBackground", 0, 0, width, height, ix.config.Get("color"))
	end

	self.amountEntry = self:Add("ixTextEntry")
	self.amountEntry:Dock(FILL)
	self.amountEntry:SetFont("ixGenericFont")
	self.amountEntry:SetNumeric(true)
	self.amountEntry:SetValue("0")

	self.transferButton = self:Add("DButton")
	self.transferButton:SetFont("ixIconsMedium")
	self:SetLeft(false)
	self.transferButton.DoClick = function()
		local amount = math.max(0, math.Round(tonumber(self.amountEntry:GetValue()) or 0))
		self.amountEntry:SetValue("0")

		if (amount != 0) then
			self:OnTransfer(amount)
		end
	end

	self.bNoBackgroundBlur = true
end

function PANEL:SetLeft(bValue)
	if (bValue) then
		self.transferButton:Dock(LEFT)
		self.transferButton:SetText("s")
	else
		self.transferButton:Dock(RIGHT)
		self.transferButton:SetText("t")
	end
end

function PANEL:SetMoney(money)
	local name = string.gsub(ix.util.ExpandCamelCase(ix.currency.plural), "%s", "")

	self.money = math.max(math.Round(tonumber(money) or 0), 0)
	self.moneyLabel:SetText(string.format("%s: %d", name, money))
end

function PANEL:OnTransfer(amount)
end

function PANEL:Paint(width, height)
	derma.SkinFunc("PaintBaseFrame", self, width, height)
end

vgui.Register("ixStorageMoney", PANEL, "EditablePanel")

DEFINE_BASECLASS("Panel")
PANEL = {}

AccessorFunc(PANEL, "fadeTime", "FadeTime", FORCE_NUMBER)
AccessorFunc(PANEL, "frameMargin", "FrameMargin", FORCE_NUMBER)
AccessorFunc(PANEL, "storageID", "StorageID", FORCE_NUMBER)

function PANEL:Init()
	if (IsValid(ix.gui.openedStorage)) then
		ix.gui.openedStorage:Remove()
	end

	ix.gui.openedStorage = self

	self:SetSize(ScrW(), ScrH())
	self:SetPos(0, 0)
	self:SetFadeTime(0.25)
	self:SetFrameMargin(4)

	self.storageInventory = self:Add("ixInventory")
	self.storageInventory.bNoBackgroundBlur = true
	self.storageInventory:ShowCloseButton(true)
	self.storageInventory:SetTitle("Storage")
	self.storageInventory.Close = function(this)
		net.Start("ixStorageClose")
		net.SendToServer()
		self:Remove()
	end

	self.storageMoney = self.storageInventory:Add("ixStorageMoney")
	self.storageMoney:SetVisible(false)
	self.storageMoney.OnTransfer = function(_, amount)
		net.Start("ixStorageMoneyTake")
			net.WriteUInt(self.storageID, 32)
			net.WriteUInt(amount, 32)
		net.SendToServer()
	end

	-- Its own reference to the player's inventory panel: ix.gui.inv1 is a global that the next storage view, or the
	-- Tab menu, points at a panel of its own.
	self.localInventory = self:Add("ixInventory")
	ix.gui.inv1 = self.localInventory
	self.localInventory.bNoBackgroundBlur = true
	self.localInventory:ShowCloseButton(true)
	self.localInventory.Close = function(this)
		net.Start("ixStorageClose")
		net.SendToServer()
		self:Remove()
	end

	self.localMoney = self.localInventory:Add("ixStorageMoney")
	self.localMoney:SetVisible(false)
	self.localMoney:SetLeft(true)
	self.localMoney.OnTransfer = function(_, amount)
		net.Start("ixStorageMoneyGive")
			net.WriteUInt(self.storageID, 32)
			net.WriteUInt(amount, 32)
		net.SendToServer()
	end

	self:SetAlpha(0)
	self:AlphaTo(255, self:GetFadeTime())

	self.storageInventory:MakePopup()
	self.localInventory:MakePopup()
end

function PANEL:OnChildAdded(panel)
	panel:SetPaintedManually(true)
end

function PANEL:SetLocalInventory(inventory)
	if (IsValid(self.localInventory) and !IsValid(ix.gui.menu)) then
		self.localInventory:SetInventory(inventory)
		self.localInventory:SetPos(
			self:GetWide() / 2 + self:GetFrameMargin() / 2, self:GetTall() / 2 - self.localInventory:GetTall() / 2
		)
	end
end

function PANEL:SetLocalMoney(money)
	if (!self.localMoney:IsVisible()) then
		self.localMoney:SetVisible(true)
		self.localInventory:SetTall(self.localInventory:GetTall() + self.localMoney:GetTall() + 2)
	end

	self.localMoney:SetMoney(money)
end

function PANEL:SetStorageTitle(title)
	self.storageInventory:SetTitle(title)
end

function PANEL:SetStorageInventory(inventory)
	self.storageInventory:SetInventory(inventory)
	self.storageInventory:SetPos(
		self:GetWide() / 2 - self.storageInventory:GetWide() - 2,
		self:GetTall() / 2 - self.storageInventory:GetTall() / 2
	)

	ix.gui["inv" .. inventory:GetID()] = self.storageInventory
end

function PANEL:SetStorageMoney(money)
	if (!self.storageMoney:IsVisible()) then
		self.storageMoney:SetVisible(true)
		self.storageInventory:SetTall(self.storageInventory:GetTall() + self.storageMoney:GetTall() + 2)
	end

	self.storageMoney:SetMoney(money)
end

function PANEL:Paint(width, height)
	ix.util.DrawBlurAt(0, 0, width, height)

	for _, v in ipairs(self:GetChildren()) do
		v:PaintManual()
	end
end

function PANEL:Remove()
	self:SetAlpha(255)
	self:AlphaTo(0, self:GetFadeTime(), 0, function()
		BaseClass.Remove(self)
	end)
end

function PANEL:OnRemove()
	-- Both inventory panels are popups (MakePopup), so they don't go with the view: remove them here, and only these
	-- two. Remove fades for 0.25 s first, and by the time this runs ix.gui.inv1 can be the next storage view's panel
	-- (the server closes one storage when another opens) or the Tab menu's.
	if (IsValid(self.storageInventory)) then
		self.storageInventory:Remove()
	end

	if (IsValid(self.localInventory)) then
		self.localInventory:Remove()
	end
end

vgui.Register("ixStorageView", PANEL, "Panel")
