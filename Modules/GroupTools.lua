--[[--------------------------------------------------------------------------
	Lattice :: Group tools

	Running the group - marks, ready check, countdown, role check, convert,
	everyone is assistant - as the Toolbox trunk's Party branch, called Raid
	in a raid. What the client's own raid tab does (CompactRaidFrameManager,
	the tab down the left edge), in our glass.

	THE TOOLBOX OWNS IT, NOT THE FRAMES (Joe, 2026-10-24: "Toolbox-owned
	management"). It lived in the party frames module, so turning our party
	frames off took the controls with it while Blizzard's tab stayed hidden:
	no way to run a group at all. Now the party and raid modules switch frames
	and nothing else, and this switches the tab: Blizzard's is put away only
	while ours is there to use, which is while the Toolbox is on.

	THE RAID TAB IS PARKED, never deafened: on Era its events are what show
	Blizzard's raid frames (Blizzard_CompactRaidFrameManager.lua:50-60,
	:116-127, :434-436). And it adopts those frames as its child at load
	(:23), so they are moved out from under it first - whether they show is
	the raid page's call, not the tab's.

	NOT SECURE, and it does not need to be: none of these is a protected call
	on this game version.

	EXCEPT THE WORLD MARKERS, which are secure buttons (the scoping note's
	"secure button only", and EllesmereUI's method on Forever). So that the
	branch can still open, close and change height in a fight, they step out
	of it as the fight starts and come back when it ends (Joe, 2026-10-24:
	"markers out of combat only").
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L
local GT = A:NewModule("grouptools")

local W, Media = A.Widgets, A.Media

local PANEL_W   = 320
local WELL      = 34
local WELL_GAP  = 6
local ROW_H     = 30
local MARKERS   = 8
local PANEL_PAD, HEAD_H = 16, 26
local ROLE_H, ROLE_STEP = 18, 70

--- How long a countdown runs, and the choices offered.
--
--  Capped by the client's own constant rather than by a number of ours:
--  C_PartyInfo.DoCountdown refuses anything longer and says nothing about it.
local COUNTDOWNS = { 5, 10, 15, 30 }

local function Trunk() return A.Trunk:Get("toolbox") end

local function InGroup()
	return (GetNumGroupMembers and GetNumGroupMembers() or 0) > 0
end

local function InRaid() return IsInRaid and IsInRaid() or false end

--- Ours is there to use: this module and the Toolbox it hangs from.
local function Ours()
	local tb = A:GetModule("toolbox")
	return GT.enabled and tb and tb.enabled and true or false
end
GT.Ours = Ours

--- Party in a party, Raid in a raid, and back (Joe, 2026-10-24).
local function GroupName()
	if InRaid() then return _G.RAID or "Raid" end
	return _G.PARTY or "Party"
end

-- ---------------------------------------------------------------------------
-- Blizzard's raid tab
-- ---------------------------------------------------------------------------

--- Put the tab away while ours is there; give it back when it is not. In a
--  fight both are refused, and the next roster change or the fight's end
--  asks again.
function GT:Sync()
	local mgr = _G.CompactRaidFrameManager
	if not mgr or (InCombatLockdown and InCombatLockdown()) then return end
	local crf = _G.CompactRaidFrameContainer
	if Ours() then
		-- Its raid frames out first, so they do not go with it.
		if crf and crf:GetParent() == mgr then crf:SetParent(UIParent) end
		A:Banish(mgr, true)
		self.hideReport = mgr:IsVisible() and "STILL SHOWN" or "hidden"
	else
		if A.homes[mgr] then A:Unbanish(mgr) end
		-- And back under it, as the client had them, unless the raid page has
		-- them put away.
		if crf and crf:GetParent() == UIParent then crf:SetParent(mgr) end
		self.hideReport = "shown"
	end
	Trunk():Refresh()
end

-- ---------------------------------------------------------------------------
-- the branch
-- ---------------------------------------------------------------------------

function GT:PanelOpen()
	return self.panel and self.panel:IsShown() and true or false
end

--- Open or shut the branch, one branch at a time like the rest.
function GT:SetPanelOpen(open)
	if (open and true or false) ~= self:PanelOpen() then Trunk():Toggle("party") end
	return self:PanelOpen()
end

function GT:TogglePanel()
	Trunk():Toggle("party")
	return self:PanelOpen()
end

function GT:OpenPanel()
	local p = self:BuildPanel()
	self:RefreshPanel()
	if Trunk():Place("party", p) then p:Show() end
end

function GT:AttachNode()
	Trunk():AddNode("party", {
		-- After Addons and its pins (300.x), before Settings (400): Settings
		-- stays second to last, above What's new, in a group or out (Joe,
		-- 2026-10-24).
		icon = "party", label = GroupName, order = 350,
		transient = true,
		available = function() return Ours() and InGroup() end,
		isOpen = function() return GT:PanelOpen() end,
		open = function() GT:OpenPanel() end,
		close = function() if GT.panel then GT.panel:Hide() end end,
	})
	self._inGroup = InGroup()
	self._inRaid = InRaid()
end

local function MaxCountdown()
	local k = _G.Constants and _G.Constants.PartyCountdownConstants
	return (k and k.MaxCountdownSeconds) or 60
end

--- Who may press what.
--
--  READY CHECK and ROLE CHECK are the officers' (IsOfficer), CONVERT the
--  party leader's. The client refuses a party member's ready check and
--  ignores their role check, which is worse - a button that does nothing and
--  does not say so. So they are HIDDEN for a member rather than dimmed, and
--  the panel is shorter. A greyed row is a row you keep trying.
--
--  COUNTDOWN is anyone's in a party - the client's own slash command does not
--  gate it - and an officer's in a raid, as the raid tab has it.
local function IsLeader()
	local l = UnitIsGroupLeader and UnitIsGroupLeader("player")
	if A.IsSecret(l) then return false end
	return l and true or false
end

--- WHO RUNS A RAID: its leader and assistants. The raid tab gives both the
--  marks, ready check, countdown and role check, and gives a plain member
--  none of them (Blizzard_CompactRaidFrameManager.lua:174-188). Ours gave an
--  assistant only the marks and countdown (Joe's screenshot, 2026-10-24). A
--  party has no assistants, so there it is the leader.
local function IsOfficer()
	if IsLeader() then return true end
	if not InRaid() then return false end
	local a = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
	if A.IsSecret(a) then return false end
	return a and true or false
end

local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_ICON = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

--- Alive and total, for the group and for each role, counted as the raid tab
--  counts them (CRF_CountStuff, Blizzard_CompactRaidFrameManager.lua:627-652):
--  in a raid, dead is GetRaidRosterInfo's ninth answer and the role its
--  twelfth; in a party, each unit asked.
local function Count()
	local n = { alive = 0, total = 0 }
	for _, r in ipairs(ROLES) do n[r] = { alive = 0, total = 0 } end
	local function add(dead, role)
		if A.IsSecret(dead) then dead = false end
		if A.IsSecret(role) then role = nil end
		n.total = n.total + 1
		if not dead then n.alive = n.alive + 1 end
		local slot = role and n[role]
		if slot then
			slot.total = slot.total + 1
			if not dead then slot.alive = slot.alive + 1 end
		end
	end
	local function roleOf(unit)
		return UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
	end
	if InRaid() then
		for i = 1, GetNumGroupMembers() do
			local _, rank, _, _, _, _, _, _, dead, _, _, role = GetRaidRosterInfo(i)
			if not A.IsSecret(rank) and rank then add(dead, role) end
		end
	elseif InGroup() then
		add(UnitIsDeadOrGhost("player"), roleOf("player"))
		for i = 1, (GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do
			add(UnitIsDeadOrGhost("party" .. i), roleOf("party" .. i))
		end
	end
	return n
end
GT.Count = Count

local ACTIONS = {
	{
		key = "ready", label = READY_CHECK or "Ready Check",
		glyph = "tick", token = "friendly", officer = true,
		run = function()
			if C_PartyInfo and C_PartyInfo.DoReadyCheck then C_PartyInfo.DoReadyCheck() end
		end,
	},
	{
		key = "countdown", label = L.party.controls.countdown, glyph = "zen", token = "text",
		raidOfficer = true,
		run = function(self)
			local n = math.min(self.seconds or 10, MaxCountdown())
			if C_PartyInfo and C_PartyInfo.DoCountdown then C_PartyInfo.DoCountdown(n) end
		end,
	},
	{
		key = "roles", label = L.party.is_leader.key, glyph = "dps", token = "text",
		officer = true,
		run = function()
			if InitiateRolePoll then InitiateRolePoll() end
		end,
	},
	{
		-- THE GOLD ONE, because it changes the shape of the group rather than
		-- asking it a question.
		--
		-- THE BARE GLOBAL, not C_PartyInfo. This client's own right-click menu
		-- calls ConvertToRaid() - Blizzard_UnitPopup_Vanilla.toc loads
		-- Classic/UnitPopupButtons_Shared.lua, and that is what it uses. The
		-- namespaced C_PartyInfo.ConvertToRaid is the Mainline form.
		--
		-- And NOT ConfirmConvertToRaid, which was the first thing tried here
		-- on the strength of its name. It is not an ask-first version of this
		-- call: the group finder uses it inside a popup's OnAccept, after the
		-- player has already answered. Called cold it does nothing at all,
		-- silently, which is exactly what the button did.
		--
		-- A party's only: in a raid it does nothing, so it is not there.
		key = "raid", label = _G.CONVERT_TO_RAID or "Convert to Raid",
		glyph = "gear", token = "semanticGold", leader = true, party = true,
		run = function()
			if ConvertToRaid then
				ConvertToRaid()
			elseif C_PartyInfo and C_PartyInfo.ConvertToRaid then
				C_PartyInfo.ConvertToRaid()
			end
		end,
	},
}

--- One target mark well.
--
--  THE MARK GOES ON YOUR TARGET, which is the fact the brief never says and
--  the one that decides how this behaves. SetRaidTarget takes a unit, and the
--  unit is always "target" - so with nothing targeted every well here is inert,
--  and the ring showing which mark is 'active' is really showing what your
--  current target is wearing. Both follow the target rather than the party.
local function BuildWell(panel, index)
	local b = W.CreateButton(panel, { corner = 10, fill = "cardBg", edge = "cardEdge" })
	b:SetSize(WELL, WELL)
	b.index = index

	if index then
		local icon = b:CreateTexture(nil, "OVERLAY")
		icon:SetSize(WELL - 12, WELL - 12)
		icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		W.SetMarkIcon(icon, index)
		b.icon = icon
	else
		-- Clear. Its own label rather than a ninth icon, because there is no
		-- ninth mark and a crossed-out one would read as a mark you can set.
		local label = W.Text(b, "tiny", "CENTER")
		label:SetPoint("CENTER", b, "CENTER", 0, 0)
		label:SetText(_G.NONE or "Clear")
		b.label = label
	end

	b:SetScript("OnClick", function(self)
		if not UnitExists("target") or not SetRaidTarget then return end
		SetRaidTarget("target", self.index or 0)
		GT:RefreshPanel()
	end)
	b:SetScript("OnEnter", function(self) W.SetButtonState(self, self.__on, true) end)
	b:SetScript("OnLeave", function(self) W.SetButtonState(self, self.__on, false) end)
	return b
end

--- The flare on each world-marker well, in the target marks' order: skull,
--  cross, square, moon, triangle, diamond, circle, star. A flare is numbered
--  by its colour (1 blue ... 8 white), not by the symbol it wears, so the
--  wells cannot share the marks' indices. This is the client's own
--  WORLD_RAID_MARKER_ORDER (Blizzard_CompactRaidFrameManager.lua:4-12, Era),
--  and EllesmereUI's symbol map agrees (EllesmereUIQoL_RaidTools.lua:425).
local WORLD_ORDER = { 8, 4, 1, 7, 2, 3, 6, 5 }

--- The client says whether it has world markers at all, and the raid tab
--  hides its button when it does not (CompactRaidFrameManager_SetupRaid-
--  MarkerDropdown, :73-80).
local function WorldMarkersOn()
	if not IsRaidMarkerSystemEnabled then return true end
	return IsRaidMarkerSystemEnabled() and true or false
end

--- One world-marker well: the mark well's glass, on a SECURE button.
--
--  The client's own world-marker action (SECURE_ACTIONS.worldmarker,
--  SecureTemplates.lua:602 Era, :605 Forever): left places the flare where
--  you aim, right clears it. The Clear well has no flare, and a clear with
--  none clears them all - the call the raid tab's "Remove all" makes
--  (ClearRaidMarker(nil), Blizzard_CompactRaidFrameManager.lua:108-110), so
--  no slash command to localise.
--
--  On the mouse button's UP: a mouse press on a secure button acts on the
--  release whatever ActionButtonUseKeyDown says (SecureTemplates.lua:805-808).
local function BuildWorldWell(parent, world, symbol)
	local b = W.CreateButton(parent, { corner = 10, fill = "cardBg", edge = "cardEdge",
		template = "SecureActionButtonTemplate" })
	b:SetSize(WELL, WELL)
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("type", "worldmarker")
	if world then b:SetAttribute("marker", tostring(world)) end
	b:SetAttribute("action1", world and "set" or "clear")
	b:SetAttribute("action2", "clear")
	b.world = world

	if symbol then
		local icon = b:CreateTexture(nil, "OVERLAY")
		icon:SetSize(WELL - 12, WELL - 12)
		icon:SetPoint("CENTER", b, "CENTER", 0, 0)
		W.SetMarkIcon(icon, symbol)
		b.icon = icon
	else
		local label = W.Text(b, "tiny", "CENTER")
		label:SetPoint("CENTER", b, "CENTER", 0, 0)
		label:SetText(_G.NONE or "Clear")
		b.label = label
	end

	-- Hooked, not set: the template's own scripts stay as they are.
	b:HookScript("OnEnter", function(self)
		W.SetButtonState(self, false, true)
		W.Tooltip(self, "ANCHOR_RIGHT", L.party.controls.world_markers,
			self.world and L.party.controls.world_marker_tip or L.party.controls.world_clear_tip)
	end)
	b:HookScript("OnLeave", function(self)
		W.SetButtonState(self, false, false)
		W.HideTooltip()
	end)
	return b
end

--- One action row: a COMMAND (Lattice Polish Pass), in a list.
--
--  Each row drew its own box - its own corner, edge and font - and Ready Check
--  wore the selected-row tint, which reads as already on, not as press me
--  (the same misread as the quest log's filled Untrack, 2026-10-12). All four
--  are standard commands now: a utility panel has no one obvious next step.
local function BuildRow(panel, spec)
	local b = W.Command(panel, { row = true, label = spec.label,
		icon = spec.glyph, iconToken = spec.token,
		onClick = function(self) spec.run(self) end })
	b:SetHeight(ROW_H)
	b.spec = spec
	b.glyph = b.icon

	-- The inline duration picker, on the countdown row only. A picker rather
	-- than four rows: the number is a preference you set once.
	--
	-- ITS OWN BUTTON, because a FontString cannot be clicked - and it has to
	-- swallow the click, or picking 30s would also start a 10s countdown on
	-- the way past.
	if spec.key == "countdown" then
		b.seconds = 10
		local pick = W.CreateButton(b, { corner = 6, fill = "glassSoft",
			edge = "cardEdge" })
		pick:SetSize(46, 18)
		pick:SetPoint("RIGHT", b, "RIGHT", -10, 0)
		pick.text = W.Text(pick, "tiny", "CENTER")
		pick.text:SetPoint("CENTER", pick, "CENTER", 0, 0)
		pick:SetScript("OnClick", function()
			local entries = {}
			for _, n in ipairs(COUNTDOWNS) do
				if n <= MaxCountdown() then
					entries[#entries + 1] = {
						text = n .. "s",
						-- `action`, which is what W.Menu runs. This said `func`, so
						-- every pick other than the default did nothing at all.
						action = function() b.seconds = n; GT:RefreshPanel() end,
					}
				end
			end
			W.Menu(pick, entries)
		end)
		b.pick = pick
	end

	return b
end

function GT:BuildPanel()
	if self.panel then return self.panel end

	local p = Trunk():Branch("ToolboxParty", PANEL_W)
	self.panel = p

	-- Junction-and-strand headings (the panel vocabulary): the group with its
	-- count on the strand's end, then the marks.
	p.head = A.Trunk.Head(p)
	p.head:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, -PANEL_PAD)
	p.head:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PANEL_PAD, -PANEL_PAD)
	p.count = p.head.hint

	-- THE ROLES, in a raid: alive of each, as the raid tab heads its panel.
	p.roleLine = CreateFrame("Frame", nil, p)
	p.roleLine:SetHeight(ROLE_H)
	p.roleCounts = {}
	local x = 0
	for _, role in ipairs(ROLES) do
		local icon = p.roleLine:CreateTexture(nil, "OVERLAY")
		icon:SetSize(ROLE_H - 4, ROLE_H - 4)
		icon:SetPoint("LEFT", p.roleLine, "LEFT", x, 0)
		Media:SetIcon(icon, ROLE_ICON[role])
		local text = W.Text(p.roleLine, "tiny", "LEFT")
		text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
		p.roleCounts[role] = { icon = icon, text = text }
		x = x + ROLE_STEP
	end

	-- The marks: a block that comes and goes whole, so it is laid out from
	-- its own top, which RefreshPanel places.
	p.markBox = CreateFrame("Frame", nil, p)
	p.markBox:SetSize(PANEL_W - PANEL_PAD * 2, HEAD_H + 2 * (WELL + WELL_GAP))
	p.marks = A.Trunk.Head(p)
	p.marks:SetPoint("TOPLEFT", p.markBox, "TOPLEFT", 0, 0)
	p.marks:SetPoint("TOPRIGHT", p.markBox, "TOPRIGHT", 0, 0)
	p.marks:Set(_G.RAID_TARGET_ICON or "Target markers", "")

	-- FIVE ACROSS, TWO DOWN: eight marks and a Clear spanning the last two
	-- cells, which is the brief's grid and also the one that fits 320 wide.
	-- HIGHEST INDEX FIRST: skull, cross, square, moon, triangle, diamond,
	-- circle, star. That is not an arrangement, it is THE arrangement -
	-- Blizzard's own grid has read that way since the marks existed, and
	-- everybody reaches for the skull in the top-left without looking.
	p.wells = {}
	for slot = 1, MARKERS do
		local index = MARKERS + 1 - slot
		local b = BuildWell(p, index)
		local col, row = (slot - 1) % 5, math.floor((slot - 1) / 5)
		b:SetPoint("TOPLEFT", p.markBox, "TOPLEFT",
			col * (WELL + WELL_GAP), -HEAD_H - row * (WELL + WELL_GAP))
		p.wells[slot] = b
	end

	local clear = BuildWell(p, nil)
	clear:SetWidth(WELL * 2 + WELL_GAP)
	clear:SetPoint("TOPLEFT", p.markBox, "TOPLEFT",
		3 * (WELL + WELL_GAP), -HEAD_H - (WELL + WELL_GAP))
	p.clear = clear

	-- The world markers: the same block under its own heading. Its wells are
	-- secure, so they are made in GT:BuildWorld, out of a fight only.
	p.worldBox = CreateFrame("Frame", nil, p)
	p.worldBox:SetSize(PANEL_W - PANEL_PAD * 2, HEAD_H + 2 * (WELL + WELL_GAP))
	p.world = A.Trunk.Head(p)
	p.world:SetPoint("TOPLEFT", p.worldBox, "TOPLEFT", 0, 0)
	p.world:SetPoint("TOPRIGHT", p.worldBox, "TOPRIGHT", 0, 0)
	p.world:Set(L.party.controls.world_markers, "")

	p.rows = {}
	for i, spec in ipairs(ACTIONS) do
		local b = BuildRow(p, spec)
		b:SetPoint("LEFT", p, "LEFT", PANEL_PAD, 0)
		b:SetPoint("RIGHT", p, "RIGHT", -PANEL_PAD, 0)
		p.rows[i] = b
	end

	-- EVERYONE IS ASSISTANT: a state, so a toggle and not a command - the raid
	-- tab's own check box (Blizzard_CompactRaidFrameManager.xml:566-589), the
	-- raid leader's alone (.lua:209-216).
	p.assist = W.Toggle(p, { label = _G.ALL_ASSIST_LABEL_LONG or "Make Everyone Assistant",
		onClick = function(self)
			if C_PartyInfo and C_PartyInfo.SetEveryoneIsAssistant then
				C_PartyInfo.SetEveryoneIsAssistant(not self:IsOn())
			end
			self:SetOn(not self:IsOn())
		end })

	self:RefreshPanel()
	return p
end

--- The world-marker wells, made once and out of a fight: a secure button's
--  attributes cannot be written in one.
function GT:BuildWorld()
	local p = self.panel
	if not p or p.worldWells or self.fighting or InCombatLockdown() then return end
	p.worldWells = {}
	for slot = 1, MARKERS do
		p.worldWells[slot] = BuildWorldWell(p.worldBox, WORLD_ORDER[slot], MARKERS + 1 - slot)
	end
	p.worldClear = BuildWorldWell(p.worldBox, nil, nil)
	p.worldClear:SetWidth(WELL * 2 + WELL_GAP)
	self:PlaceWorld(true)
end

--- In the panel, laid out as the mark grid; or out of it, parked.
--
--  OUT AS A FIGHT STARTS, so the branch carries nothing protected and can
--  still open, close and change height in one. Parent AND anchors: a frame
--  something secure is anchored to is as locked as its parent. Done while
--  PLAYER_REGEN_DISABLED is handled, the last moment a secure frame moves;
--  on Forever InCombatLockdown already says true there, so the handler's
--  own flag decides, not that (memory: combat-start-window).
function GT:PlaceWorld(home)
	local p = self.panel
	if not (p and p.worldWells) then return end
	if not self.park then
		self.park = CreateFrame("Frame", nil, UIParent)
		self.park:Hide()
	end
	local host = home and p.worldBox or self.park
	local all = { p.worldClear }
	for _, b in ipairs(p.worldWells) do all[#all + 1] = b end
	for _, b in ipairs(all) do
		b:ClearAllPoints()
		b:SetParent(host)
	end
	if home then
		for slot, b in ipairs(p.worldWells) do
			local col, row = (slot - 1) % 5, math.floor((slot - 1) / 5)
			b:SetPoint("TOPLEFT", p.worldBox, "TOPLEFT",
				col * (WELL + WELL_GAP), -HEAD_H - row * (WELL + WELL_GAP))
		end
		p.worldClear:SetPoint("TOPLEFT", p.worldBox, "TOPLEFT",
			3 * (WELL + WELL_GAP), -HEAD_H - (WELL + WELL_GAP))
	end
	p.worldHome = home
end

--- Everything about the panel that can change while it is open.
--
--  ONE FUNCTION, called on every event that touches it. The rows that hide for
--  a member change the panel's height, so laying them out and sizing the panel
--  cannot be two places that both think they own the number.
function GT:RefreshPanel()
	local p = self.panel
	if not p then return end
	local c = A.Palette.c

	-- ALIVE OF THE WHOLE GROUP, as the raid tab heads its panel (Joe,
	-- 2026-10-24). It read online/total until then.
	local raid = InRaid()
	local officer = IsOfficer()
	local n = Count()
	p.head:Set(GroupName(), n.total > 0 and (n.alive .. "/" .. n.total) or "")
	local y = PANEL_PAD + HEAD_H

	-- The roles, a raid's.
	p.roleLine:SetShown(raid)
	if raid then
		p.roleLine:ClearAllPoints()
		p.roleLine:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, -y)
		p.roleLine:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PANEL_PAD, -y)
		for _, role in ipairs(ROLES) do
			local r = p.roleCounts[role]
			local s = n[role].alive .. "/" .. n[role].total
			if r.text:GetText() ~= s then r.text:SetText(s) end
			W.Color(r.text, c.text)
			W.Tint(r.icon, c.textDim, 1)
		end
		y = y + ROLE_H + 8
	end

	-- The marks: anyone's in a party, an officer's in a raid.
	local marks = officer or not raid
	p.markBox:SetShown(marks)
	p.marks:SetShown(marks)
	p.clear:SetShown(marks)
	for _, b in ipairs(p.wells) do b:SetShown(marks) end
	if marks then
		p.markBox:ClearAllPoints()
		p.markBox:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, -y)
		y = y + HEAD_H + 2 * (WELL + WELL_GAP) + 8
	end

	-- THE WELLS FOLLOW YOUR TARGET, not the party. Inert with nothing
	-- targeted, because SetRaidTarget has no unit to act on - and a well that
	-- looks pressable and does nothing is the worse of the two.
	local hasTarget = UnitExists and UnitExists("target")
	local on = hasTarget and GetRaidTargetIndex and GetRaidTargetIndex("target")
	-- A SECRET MARK RINGS NO WELL. Which well it matches is a comparison, and
	-- a secret cannot be compared; the wells still set marks.
	if A.IsSecret(on) then on = nil end
	-- THE DIM GOES ON LAST. A well IS its own glass surface, so
	-- W.SetButtonState writes its alpha too - setting the dim first and the
	-- state second put every well straight back to full, and the grid looked
	-- ready when there was nothing to mark.
	-- b.index, not the slot: the grid is laid out highest-first, so the two
	-- are opposites and comparing the wrong one rings the wrong well.
	for _, b in ipairs(p.wells) do
		b.__on = (on == b.index)
		W.SetButtonState(b, b.__on, false)
		b:EnableMouse(hasTarget and true or false)
		b:SetAlpha(hasTarget and 1 or 0.4)
	end
	p.clear:SetAlpha(hasTarget and 1 or 0.4)
	p.clear:EnableMouse(hasTarget and true or false)

	-- THE WORLD MARKERS: whoever has the marks, where the client has world
	-- markers, and never in a fight (they are parked then).
	local world = marks and WorldMarkersOn() and not self.fighting and not InCombatLockdown()
	if world then
		self:BuildWorld()
		if p.worldWells and not p.worldHome then self:PlaceWorld(true) end
	end
	world = world and p.worldWells ~= nil and p.worldHome
	p.worldBox:SetShown(world and true or false)
	p.world:SetShown(world and true or false)
	if world then
		p.worldBox:ClearAllPoints()
		p.worldBox:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD, -y)
		y = y + HEAD_H + 2 * (WELL + WELL_GAP) + 8
	end

	-- HIDDEN, NOT DIMMED, and then the panel shortens. A greyed row is a row
	-- you keep trying; a row that is not there is a question you do not ask.
	local leader = IsLeader()
	local any = false
	for _, b in ipairs(p.rows) do
		local s = b.spec
		if (s.leader and not leader) or (s.officer and not officer)
			or (s.raidOfficer and raid and not officer) or (s.party and raid) then
			b:Hide()
		else
			b:Show()
			b:SetPoint("TOP", p, "TOP", 0, -y)
			y = y + ROW_H + 6
			any = true
			if b.pick then
				b.pick.text:SetText((b.seconds or 10) .. "s")
				-- Full ink: a value you can change rests bright, not dim.
				W.Color(b.pick.text, c.text)
			end
		end
	end

	-- The assist toggle: a raid's, and its leader's.
	local assist = raid and leader
	p.assist:SetShown(assist)
	if assist then
		local everyone = IsEveryoneAssistant and IsEveryoneAssistant()
		if A.IsSecret(everyone) then everyone = false end
		if p.assist:IsOn() ~= (everyone and true or false) then p.assist:SetOn(everyone) end
		p.assist:ClearAllPoints()
		p.assist:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD + 4, -(y + 4))
		y = y + ROW_H + 6
		any = true
	end

	p:SetHeight(y - (any and 6 or 0) + PANEL_PAD)
	-- Its height changed, so it is placed again beside its node.
	if p:IsShown() then Trunk():Place("party", p) end
end

--- No group, no controls, and no node: the branch shuts when the last person
--  leaves, and the node comes and goes with the group - and is renamed when
--  the group becomes a raid, or a party again.
function GT:HideWithGroup()
	local inGroup, inRaid = InGroup(), InRaid()
	if not inGroup and self:PanelOpen() then self.panel:Hide() end
	if inGroup ~= self._inGroup or inRaid ~= self._inRaid then
		self._inGroup, self._inRaid = inGroup, inRaid
		Trunk():Refresh()
	end
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

function GT:RegisterEvents()
	local function sweep()
		GT:RefreshPanel()
		GT:HideWithGroup()
	end
	-- The tab comes back with the roster and cannot be sent away mid-fight,
	-- so both of those moments ask again.
	local function sweepAndSync()
		GT:Sync()
		sweep()
	end
	A:RegisterEvent(self, "GROUP_ROSTER_UPDATE",   sweepAndSync)
	-- The world markers out of the branch as a fight starts, and back after
	-- (GT:PlaceWorld). The flag, not InCombatLockdown, is what the refresh
	-- reads: on Forever the lockdown already reports on as this runs.
	A:RegisterEvent(self, "PLAYER_REGEN_DISABLED", function()
		GT.fighting = true
		GT:PlaceWorld(false)
		GT:RefreshPanel()
	end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		GT.fighting = nil
		sweepAndSync()
	end)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", sweepAndSync)
	A:RegisterEvent(self, "PARTY_LEADER_CHANGED",  sweep)
	-- A role check answers on its own event, and nothing was listening.
	A:RegisterEvent(self, "PLAYER_ROLES_ASSIGNED", sweep)
	A:RegisterEvent(self, "RAID_TARGET_UPDATE",    sweep)
	-- The marker grid follows your TARGET.
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", function() GT:RefreshPanel() end)
	-- A member coming back online does not announce itself as a unit event on
	-- that unit. These two are how the client says so.
	A:RegisterEvent(self, "PARTY_MEMBER_ENABLE",  sweep)
	A:RegisterEvent(self, "PARTY_MEMBER_DISABLE", sweep)
	-- Somebody dying or coming back changes the counts: the raid tab's own
	-- two events (Blizzard_CompactRaidFrameManager.lua:56-57). Frequent in a
	-- raid, so only while the branch is open.
	local function counts() if GT:PanelOpen() then GT:RefreshPanel() end end
	A:RegisterEvent(self, "UNIT_FLAGS",           counts)
	A:RegisterEvent(self, "PLAYER_FLAGS_CHANGED", counts)
end

function GT:OnEnable()
	self:AttachNode()
	self:RegisterEvents()
	self:Sync()
end

function GT:OnDisable()
	if self.panel then self.panel:Hide() end
	self:Sync()
end

function GT:OnSkinChanged()
	if not self.panel then return end
	A.Trunk.SkinBranch(self.panel)
	self.panel.head:Paint()
	self.panel.marks:Paint()
	self:RefreshPanel()
end
