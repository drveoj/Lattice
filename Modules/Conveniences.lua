--[[--------------------------------------------------------------------------
	AetherUI :: Conveniences

	Small things the game makes you wait for, and a switch each. All are OFF
	by default and say why in the options, because none is the kind of thing
	to do to somebody without being asked. Selling junk is here too; its code
	is the bags module's, started from here. The first two:

	  * INSTANT QUEST TEXT overrides a setting the client already has, under
	    Interface, which the player may have chosen deliberately.
	  * AUTO-REPAIR SPENDS YOUR MONEY. An addon that quietly empties a pocket
	    is not a convenience.

	Neither is clever. Instant quest text is a CVar the client reads itself -
	`instantQuestText`, "1" for instant - so all this does is set it and put it
	back when switched off. The repair is CanMerchantRepair and RepairAllItems,
	which is the same pair the client's own button uses.

	WHAT IT WILL NOT DO: repair when you cannot afford it, and repair silently.
	Both are the same rule - your money is yours and you should be able to see
	where it went - and the second is why every repair prints what it cost.
----------------------------------------------------------------------------]]

local ADDON, A = ...


local L = A.L
local CV = A:NewModule("conveniences")

local function cfg() return A.Config:Module("conveniences") end

-- What `instantQuestText` was before we touched it, so switching off is a
-- restore rather than a guess. Recorded once, on the first change, and KEPT
-- IN SAVED VARIABLES: a plain local was gone after a reload, the next one
-- recorded our own "1", and switching off left quest text instant. Account-
-- wide, as the CVar is, not per profile.
local function QuestTextWas() return A.db and A.db.global and A.db.global.questTextWas end
local function SetQuestTextWas(v) if A.db and A.db.global then A.db.global.questTextWas = v end end

-- ---------------------------------------------------------------------------
-- instant quest text
-- ---------------------------------------------------------------------------

--- The client's own setting, set for you.
--
--  Nothing is hooked and nothing is redrawn: QuestFrame reads this CVar itself
--  every time it opens a page, so writing it is the whole feature. Doing it any
--  other way - hooking the fade, forcing the alpha - would be a second owner
--  for a thing the client already decides.
function CV:ApplyQuestText()
	local want = cfg().instantQuestText and "1" or nil

	if want then
		if QuestTextWas() == nil then
			SetQuestTextWas(GetCVar("instantQuestText") or "0")
		end
		if GetCVar("instantQuestText") ~= "1" then
			pcall(SetCVar, "instantQuestText", "1")
		end
	elseif QuestTextWas() ~= nil then
		-- Back to what it was, once. A restore that runs twice would record our
		-- own value the second time and have nothing to put back.
		pcall(SetCVar, "instantQuestText", QuestTextWas())
		SetQuestTextWas(nil)
	end
end

-- ---------------------------------------------------------------------------
-- repairing
-- ---------------------------------------------------------------------------

--- Money as the client writes it, with a plain fallback.
local function Coins(amount)
	if GetCoinTextureString then
		local ok, text = pcall(GetCoinTextureString, amount)
		if ok and text then return text end
	end
	local g = math.floor(amount / 10000)
	local s = math.floor((amount % 10000) / 100)
	local c = amount % 100
	if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
	if s > 0 then return ("%ds %dc"):format(s, c) end
	return ("%dc"):format(c)
end

--- Repair everything, if this merchant can and you can afford it.
--
--  Returns what it did, which is what the suite reads: "repaired", "broke" for
--  cannot afford, or nil for nothing to do. A function that only had a side
--  effect would be testable solely through the money, and the money moving is
--  the one thing that must not happen while working it out.
function CV:Repair()
	if not cfg().autoRepair then return end
	if not (CanMerchantRepair and CanMerchantRepair()) then return end

	local cost, canRepair = GetRepairAllCost()
	if not canRepair or not cost or cost <= 0 then return end

	-- CANNOT AFFORD IT, and said so. RepairAllItems on too little money is a
	-- no-op in the client, so an addon that fired blind would look like it had
	-- repaired and leave you in a fight with a broken weapon.
	local purse = GetMoney and GetMoney() or 0
	if purse < cost then
		A:Print(A.Bad(L.conveniences.repair.enough_repairs) .. " "
			.. A.F(L.conveniences.repair.needed_on_you, Coins(cost), Coins(purse)))
		return "broke"
	end

	RepairAllItems()
	A:Print(A.F(L.conveniences.repair.repaired_s, A.Val(Coins(cost))))
	return "repaired"
end

-- ---------------------------------------------------------------------------
-- making room (issue #4)
--
-- One press clears one slot. The list and the delete are the bags module's
-- (Bags:RoomCandidates, Bags:ClearSlot), so this works with our bags off.
-- Deleting needs a click or key press, so nothing here fires by itself: a
-- full inventory only raises the question.
-- ---------------------------------------------------------------------------

function CV:Protected()
	A.db.char.makeRoomProtect = A.db.char.makeRoomProtect or {}
	return A.db.char.makeRoomProtect
end

function CV:Rules()
	A.db.global.makeRoomRules = A.db.global.makeRoomRules or {}
	return A.db.global.makeRoomRules
end

function CV:RoomList()
	local B = A:GetModule("bags")
	if not (B and B.RoomCandidates) then return {} end
	local c = cfg()
	return B:RoomCandidates({
		maxQuality = c.makeRoomQuality, soulbound = c.makeRoomSoulbound,
		guessQuest = c.makeRoomGuess, protect = self:Protected(), rules = self:Rules(),
	})
end

local function QuestTitle(questID)
	local fn = _G.C_QuestLog and _G.C_QuestLog.GetTitleForQuestID
	local ok, t = false, nil
	if fn then ok, t = pcall(fn, questID) end
	return (ok and t) or A.F(L.conveniences.make_room.quest_n, questID)
end

--- Why this one, in a few words.
function CV:RoomReason(e)
	if e.tier == 1 then
		return e.questID and A.F(L.conveniences.make_room.quest_done, QuestTitle(e.questID))
			or L.conveniences.make_room.not_needed
	elseif e.tier == 2 then return L.conveniences.make_room.junk
	elseif e.tier == 3 then return L.conveniences.make_room.no_quest_wants
	end
	return L.conveniences.make_room.cheapest
end

function CV:Clear(e)
	local B = A:GetModule("bags")
	local what = B and B:ClearSlot(e)
	if what == "sold" then
		A:Print(A.F(L.conveniences.make_room.sold, e.link, A.Val(Coins(e.worth))))
	elseif what == "deleted" then
		A:Print(A.F(L.conveniences.make_room.deleted, e.link))
	else
		A:Print(A.Bad(L.conveniences.make_room.moved))
	end
	return what
end

--- The press: the key binding or the bag window's bin. `ask` (the full-bags
--  prompt, which is an event and no press) always goes through the dialog.
function CV:MakeRoom(ask)
	if A.Widgets.ConfirmShown() then return end
	local e = self:RoomList()[1]
	if not e then
		if not ask then A:Print(L.conveniences.make_room.nothing) end
		return
	end

	local merchant = _G.MerchantFrame and _G.MerchantFrame:IsShown() and e.sellable
	if not ask and (merchant or (e.tier == 2 and not cfg().makeRoomConfirmGrey)) then
		return self:Clear(e)
	end

	A.Widgets.Confirm({
		text = A.F(L.conveniences.make_room.ask, e.link,
			e.count > 1 and (" x" .. e.count) or "", Coins(e.worth), self:RoomReason(e)),
		yes = merchant and L.conveniences.make_room.sell or L.conveniences.make_room.delete,
		no = _G.CANCEL or "Cancel", mid = L.conveniences.make_room.protect,
		onYes = function() CV:Clear(e) end,
		onMid = function()
			CV:Protected()[e.itemID] = true
			A:Print(A.F(L.conveniences.make_room.protected, e.link))
		end,
	})
end

--- The game said the bags are full: ask, at most every ten seconds, never
--  in a fight.
function CV:OnBagsFull()
	if not cfg().makeRoomPrompt then return end
	if InCombatLockdown() then return end
	local now = GetTime()
	if self._fullAt and now - self._fullAt < 10 then return end
	self._fullAt = now
	self:MakeRoom(true)
end

_G.BINDING_NAME_LATTICE_MAKEROOM = L.conveniences.make_room.binding
function _G.Lattice_MakeRoom()
	if CV.enabled then CV:MakeRoom() end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function CV:OnEnable()
	self:ApplyQuestText()

	-- (owner, event, errorType, message)
	A:RegisterEvent(self, "UI_ERROR_MESSAGE", function(_, _, _, msg)
		if msg and (msg == _G.ERR_INV_FULL or msg == _G.ERR_BAG_FULL) then CV:OnBagsFull() end
	end)

	-- MERCHANT_SHOW rather than the frame's OnShow: the event is the game
	-- saying a merchant is open, and it arrives whether or not anything has
	-- drawn a window for it yet.
	--
	-- Junk is sold by the bags module's code, which works whether or not its
	-- bags are on. Deferred a beat: SellJunk waits for MerchantFrame to be
	-- shown, and that is Blizzard's handler for the same event.
	A:RegisterEvent(self, "MERCHANT_SHOW", function()
		CV:Repair()
		local B = A:GetModule("bags")
		if not (B and B.SellJunk) then return end
		if _G.C_Timer and _G.C_Timer.After then
			_G.C_Timer.After(0.1, function() B:SellJunk() end)
		else
			B:SellJunk()
		end
	end)
	A:RegisterEvent(self, "MERCHANT_CLOSED", function()
		local B = A:GetModule("bags")
		if B and B.FinishSelling then B:FinishSelling() end
	end)
end

function CV:OnDisable()
	A:UnregisterAllEvents(self)

	-- The CVar goes back. Switching this module off is the player saying they
	-- want the game's own behaviour, and leaving the setting flipped would be
	-- the addon's last word on the subject.
	local want = cfg().instantQuestText
	cfg().instantQuestText = false
	self:ApplyQuestText()
	cfg().instantQuestText = want
end

function CV:OnConfigChanged()
	if not self.enabled then return end
	self:ApplyQuestText()
end
