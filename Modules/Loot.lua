--[[--------------------------------------------------------------------------
	Lattice :: Loot

	Our own loot window in place of Blizzard's, on both clients. It opens where
	you put it in unlock mode, or at the mouse if you ask for that.

	Method from ElvUI's loot frame (ElvUI/Game/Shared/Modules/Misc/Loot.lua):
	unregister LootFrame's events so it never opens, draw our own rows from
	GetLootSlotInfo, and loot with LootSlot. Two things Blizzard's code reads
	off LootFrame are kept up:

	  * LootFrame.selected* fields. The master loot list reads them on Era
	    (LootFrame.lua:562), and Forever's assign-loot menu does too
	    (GroupLootFrame.lua:267). Era's list is ours to open; Forever's
	    GroupLootFrame answers OPEN_MASTER_LOOT_LIST itself.
	  * CloseLoot on hide, which is what tells the server you have stopped.
----------------------------------------------------------------------------]]

local ADDON, A = ...
local L = A.L
local Loot = A:NewModule("loot")

local W, Palette, Glass = A.Widgets, A.Palette, A.Glass

local WIDTH   = 280
local HEAD_H  = W.PANEL_HEAD_H
local PAD     = W.PANEL_PAD
local ROW_H   = 40
local ROW_GAP = 4
local SLOT    = 34

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

local function SlotInfo(i)
	local texture, item, quantity, currencyID, quality, locked, isQuestItem, questID, isActive =
		GetLootSlotInfo(i)
	-- Forever's currencies come out of a container helper, as Blizzard's own
	-- loot frame does it (Mainline/LootFrame.lua:230).
	if currencyID and _G.CurrencyContainerUtil then
		item, texture, quantity, quality = _G.CurrencyContainerUtil.GetCurrencyContainerInfo(
			currencyID, quantity, item, texture, quality)
	end
	return texture, item, quantity, quality, locked, isQuestItem, questID, isActive
end

local function RowEnter(row)
	row.wash:SetAlpha(1)
	if LootSlotHasItem(row.slot) then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetLootItem(row.slot)
		GameTooltip:Show()
		if _G.CursorUpdate then _G.CursorUpdate(row) end
	end
end

local function RowLeave(row)
	row.wash:SetAlpha(0)
	GameTooltip:Hide()
	if _G.ResetCursor then _G.ResetCursor() end
end

local function RowClick(row)
	local id = row.slot
	if IsModifiedClick() then
		if _G.HandleModifiedItemClick then _G.HandleModifiedItemClick(GetLootSlotLink(id)) end
		return
	end
	local lf = _G.LootFrame
	if lf then
		lf.selectedLootButton = row:GetName()
		lf.selectedLootFrame = row
		lf.selectedSlot = id
		lf.selectedQuality = row.quality
		lf.selectedItemName = row.name:GetText()
		lf.selectedTexture = row.icon.icon:GetTexture()
		lf.selectedItemLink = GetLootSlotLink(id)
	end
	if _G.StaticPopup_Hide then _G.StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION") end
	LootSlot(id)
end

local rowSeq = 0
local function BuildRow(frame)
	rowSeq = rowSeq + 1
	-- Named, because Era's master loot list anchors to the button by name.
	local row = CreateFrame("Button", ADDON .. "LootRow" .. rowSeq, frame)
	row:SetHeight(ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.wash = W.ChromeWash(row)

	row.icon = W.CreateSlot(row, { size = SLOT })
	row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)

	row.name = W.Text(row, "bagBag", "LEFT")
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
	row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	if row.name.SetWordWrap then row.name:SetWordWrap(false) end

	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", RowLeave)
	row:SetScript("OnClick", RowClick)
	return row
end

local function BuildFrame()
	local frame = Glass.CreatePanel(UIParent, {
		name   = ADDON .. "LootFrame",
		corner = W.PANEL_CORNER,
		shadow = A.db.profile.glass.shadow,
		fill   = "glassStrong",
	})
	frame:SetFillColor(Palette:ReadingFill())
	frame:SetWidth(WIDTH)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()

	local head = CreateFrame("Frame", nil, frame)
	head:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	head:SetHeight(HEAD_H)
	frame.head = head

	head.title = W.Text(head, "bagTitle", "LEFT")
	head.title:SetPoint("LEFT", head, "LEFT", PAD, 0)
	head.title:SetPoint("RIGHT", head, "RIGHT", -(PAD + W.CHROME_HIT + 6), 0)
	if head.title.SetWordWrap then head.title:SetWordWrap(false) end

	head.close = W.CloseButton(head, { onClick = function() frame:Hide() end })
	head.close:SetPoint("RIGHT", head, "RIGHT", -PAD + 4, 0)

	head.rule = W.Hairline(head)
	W.InsetRule(head.rule, frame, function(gap)
		head.rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", gap, 0)
		head.rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -gap, 0)
	end)

	frame.rows = {}

	frame:SetScript("OnHide", function()
		if _G.StaticPopup_Hide then _G.StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION") end
		if Loot.open then
			Loot.open = nil
			CloseLoot()
		end
		if _G.MasterLooterFrame then _G.MasterLooterFrame:Hide() end
	end)
	return frame
end

function Loot:Restyle()
	local f = self.frame
	if not f then return end
	f:ApplySkin("glassStrong")
	f:SetFillColor(Palette:ReadingFill())
	W.Color(f.head.title, Palette.c.text)
	W.RepaintClose(f.head.close)
	W.PaintHairline(f.head.rule)
end

--- Draw every slot, top to bottom; a looted slot leaves no gap.
function Loot:Layout()
	local f = self.frame
	local c = Palette.c
	local shown = 0
	for _, row in ipairs(f.rows) do
		if row:IsShown() then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 3, -(HEAD_H + PAD / 2 + shown * (ROW_H + ROW_GAP)))
			row:SetPoint("RIGHT", f, "RIGHT", -(PAD - 3), 0)
			shown = shown + 1
		end
	end
	f.empty = f.empty or W.Text(f, "bagBag", "LEFT")
	f.empty:ClearAllPoints()
	f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(HEAD_H + PAD / 2 + 12))
	f.empty:SetText(L.loot.empty)
	W.Color(f.empty, c.textDim)
	f.empty:SetShown(shown == 0)
	local n = math.max(shown, 1)
	f:SetHeight(HEAD_H + PAD / 2 + n * ROW_H + (n - 1) * ROW_GAP + PAD / 2 + 4)
end

function Loot:Fill(row, i)
	local c = Palette.c
	local texture, item, quantity, quality, locked, isQuestItem, questID, isActive = SlotInfo(i)
	row.slot = i
	row.quality = quality
	if type(item) == "string" and not A.IsSecret(item) then item = item:gsub("\n", ", ") end
	row.name:SetText(item or "")
	local q = quality and c.ttQuality and c.ttQuality[quality]
	W.Color(row.name, q or c.text)

	row.icon:SetIcon(texture)
	row.icon.count:SetText((quantity and quantity > 1) and tostring(quantity) or "")
	local e = quality and c.itemQuality and c.itemQuality[quality]
	row.icon:SetEdgeColor(e and e.edge or c.glassEdge)
	if questID or isQuestItem then
		row.icon:SetActive(true, c.accent)
	elseif e and e.glow then
		row.icon:SetActive(true, e.glow)
	else
		row.icon:SetActive(false)
	end
	row:SetAlpha(locked and 0.5 or 1)
	row:SetShown(texture ~= nil)
end

--- Where the window opens: under the mouse, or at the anchor.
function Loot:Place()
	local f = self.frame
	f:ClearAllPoints()
	if A.Config:Module("loot").underMouse then
		local x, y = GetCursorPosition()
		local s = f:GetEffectiveScale()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 40, y / s + 20)
	else
		f:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", 0, 0)
	end
end

function Loot:Title()
	if IsFishingLoot and IsFishingLoot() then return L.loot.fishing end
	if UnitExists("target") and UnitIsDead("target") and not UnitIsFriend("player", "target") then
		local name = UnitName("target")
		if type(name) == "string" and not A.IsSecret(name) then return name end
	end
	return _G.LOOT or L.loot.title
end

function Loot:Open(autoLoot)
	local f = self.frame
	local n = GetNumLootItems() or 0
	for i = 1, n do
		local row = f.rows[i] or BuildRow(f)
		f.rows[i] = row
		self:Fill(row, i)
	end
	for i = n + 1, #f.rows do f.rows[i]:Hide() end

	f.head.title:SetText(self:Title())
	self:Restyle()
	self:Layout()
	self:Place()
	self.open = true
	f:Show()
	f:Raise()
	if not f:IsShown() then
		self.open = nil
		CloseLoot(not autoLoot)
	end
end

function Loot:Close()
	if _G.StaticPopup_Hide then _G.StaticPopup_Hide("LOOT_BIND") end
	self.open = nil
	if self.frame then
		self.frame:Hide()
		for _, row in ipairs(self.frame.rows) do row:Hide() end
	end
end

-- ---------------------------------------------------------------------------
-- Blizzard's window
-- ---------------------------------------------------------------------------

-- What each client's LootFrame registers for itself: Era's OnLoad
-- (Classic/LootFrame.lua:13-19) and Forever's (Mainline/LootFrame.lua:59-60;
-- its slot events are registered on show).
local BLIZZ_EVENTS = A.isCamelot
	and { "LOOT_OPENED", "LOOT_CLOSED" }
	or { "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED",
		"LOOT_READY", "OPEN_MASTER_LOOT_LIST", "UPDATE_MASTER_LOOT_LIST" }

function Loot:SilenceBlizzard(on)
	local lf = _G.LootFrame
	if not lf then return end
	if on then
		lf:UnregisterAllEvents()
		if lf:IsShown() then lf:Hide() end
		-- Forever parents the master loot list to LootFrame, which never shows
		-- now (ElvUI's Loot.lua:392).
		local ml = _G.MasterLooterFrame
		if ml and ml:GetParent() == lf then ml:SetParent(UIParent) end
	else
		for _, e in ipairs(BLIZZ_EVENTS) do pcall(lf.RegisterEvent, lf, e) end
	end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function Loot:BuildAnchor()
	if self.anchor then return self.anchor end
	local a = CreateFrame("Frame", ADDON .. "LootAnchor", UIParent)
	a:SetSize(WIDTH, HEAD_H)
	a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 420, -200)
	self.anchor = a
	return a
end

function Loot:OnEnable()
	self:BuildAnchor()
	self.frame = self.frame or BuildFrame()
	self:SilenceBlizzard(true)

	A.Movers:Register("loot", self.anchor,
		{ point = "TOPLEFT", relPoint = "TOPLEFT", x = 420, y = -200 },
		L.movers.name.loot)

	A:RegisterEvent(self, "LOOT_OPENED", function(_, _, autoLoot) Loot:Open(autoLoot) end)
	A:RegisterEvent(self, "LOOT_SLOT_CLEARED", function(_, _, i)
		local row = Loot.frame and Loot.frame.rows[i]
		if row and Loot.frame:IsShown() then
			row:Hide()
			Loot:Layout()
		end
	end)
	A:RegisterEvent(self, "LOOT_SLOT_CHANGED", function(_, _, i)
		local row = Loot.frame and Loot.frame.rows[i]
		if row and Loot.frame:IsShown() then
			Loot:Fill(row, i)
			Loot:Layout()
		end
	end)
	A:RegisterEvent(self, "LOOT_CLOSED", function() Loot:Close() end)

	-- Era's master loot list is Blizzard's, opened from our row.
	if not A.isCamelot then
		A:RegisterEvent(self, "OPEN_MASTER_LOOT_LIST", function()
			local lf = _G.LootFrame
			if _G.MasterLooterFrame_Show and lf and lf.selectedLootButton then
				_G.MasterLooterFrame_Show(lf.selectedLootButton)
			end
		end)
		A:RegisterEvent(self, "UPDATE_MASTER_LOOT_LIST", function()
			local lf = _G.LootFrame
			if _G.MasterLooterFrame_UpdatePlayers and lf and lf.selectedLootButton then
				_G.MasterLooterFrame_UpdatePlayers()
			end
		end)
	end

	if _G.UISpecialFrames then
		local name = ADDON .. "LootFrame"
		local have
		for _, n in ipairs(_G.UISpecialFrames) do if n == name then have = true end end
		if not have then table.insert(_G.UISpecialFrames, name) end
	end
	self:OnConfigChanged()
end

function Loot:OnDisable()
	if self.frame then self.frame:Hide() end
	self:SilenceBlizzard(false)
	if self.anchor then A.Movers:Unregister("loot") end
end

function Loot:OnConfigChanged()
	if not self.frame then return end
	self.frame:SetScale(A.db.profile.scale)
	self.frame:SetShadow(A.db.profile.glass.shadow)
	self.anchor:SetScale(A.db.profile.scale)
	self:Restyle()
end

function Loot:OnSkinChanged()
	self:Restyle()
end
