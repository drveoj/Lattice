--[[--------------------------------------------------------------------------
	Lattice :: Raid frames - the weave

	Phases 1 and 2 of the raid build (sara-vault: "Lattice Raid Frames Build
	Plan"): every member of the raid as a cell, in one look, hung off its group
	bond and bonded to the player. No pins or lenses yet - phases 3 and 4.

	THE GROUP BOND (Raid.dc.html 13b-13d): a strand down the weave's left edge,
	a root node at its top, a stub across the gutter to the first row, and the
	group numbers on the bond side of each row. The weave grows away from it:
	rows extend right. It is plain textures on the weave, so a fight does not
	stop it being drawn - only the rows it measures wait.

	EIGHT HEADERS, ONE PER GROUP. Each is the client's SecureGroupHeaderTemplate
	filtered to one group of five, laid out as a row. Clicking a cell targets
	(left) or opens the unit menu (right), securely, in a fight or out. Eight
	rather than one header grouped by group because the handoff draws a gap and
	a number between groups, and those come free from eight frames we place,
	where one header would need sums on sizes the client may not tell us.

	ALL FORTY CELLS ARE MADE AT LOGIN, out of combat. A header makes a cell the
	moment a unit needs one, and a cell made mid-fight is one we cannot dress
	until the fight ends. Asking each header to start its list four places
	early makes it build all five now (SecureGroupHeaders.lua:137-170 on Era,
	141-174 on Forever: needButtons counts from startingIndex). Headers only
	do that work while visible (:61, :70), so the weave is shown, unseen, for
	the moment it takes.

	NOTHING HERE READS WHAT FOREVER HIDES. Health colour and the low-health
	number are the client's own sums on a curve (W.HealthColor,
	W.HealthPercentText); range is SetAlphaFromBoolean (W.RangeAlpha);
	debuffs you can dispel are the client's own icons in a container
	(W.CreateAuraContainer) - Joe's call, 2026-10-23, on both clients, so Era
	draws the same icons from its plain aura reads. Every size goes through
	Glass.SizeOf or W.StringWidth: cells hang off secure headers.

	IN COMBAT, NOTHING MOVES. Cells are protected. A density change or a
	re-stack of the groups asked for in a fight waits for PLAYER_REGEN_ENABLED.
----------------------------------------------------------------------------]]

local ADDON, A = ...

local L = A.L
local RF = A:NewModule("raidframes")

local W, Glass, Palette, Media = A.Widgets, A.Glass, A.Palette, A.Media

local function cfg() return A.Config:Module("raidframes") end

local GROUPS, PER_GROUP = 8, 5

-- ---------------------------------------------------------------------------
-- measurements (the handoff's table, design_handoff_raid/README.md)
-- ---------------------------------------------------------------------------

--- Density by raid size. A cell is a rounded rectangle, radius height/4.
local DENSITY = {
	{ upTo = 10, w = 120, h = 34, font = 12,   dense = false },
	{ upTo = 20, w = 112, h = 30, font = 11,   dense = false },
	{ upTo = 25, w = 96,  h = 28, font = 10.5, dense = false },
	{ upTo = 40, w = 60,  h = 24, font = 9.5,  dense = true  },
}

local function DensityFor(n)
	for _, d in ipairs(DENSITY) do
		if n <= d.upTo then return d end
	end
	return DENSITY[#DENSITY]
end
RF.DensityFor = DensityFor

local function Gaps(d)
	return {
		cell  = d.dense and 3 or 4,   -- between cells
		group = d.dense and 4 or 5,   -- between groups
		pad   = d.dense and 5 or 7,   -- inside a cell
		inner = d.dense and 3 or 5,   -- between a cell's dot, name and tag
		dot   = d.dense and 5 or 6,
	}
end

-- The bond, as the design draws it: the strand at the weave's left edge, the
-- rows 50 in, each opening with its group number in a 14-wide slot.
local BOND = 50
local NUMBER, NUMBER_GAP = 14, 5
local ROWS_X = BOND + NUMBER + NUMBER_GAP
local ROOT = 8   -- the root node, r = 4

local ICON = 12   -- a dispellable debuff, the client's own icon
local ICONS = 3

-- Fixed colours, as the handoff fixes them. Threat pulling is the danger
-- token (#ff8a4a, and Ruby moves it, as the nameplates' does); pulled is the
-- handoff's own red.
local GREEN      = { 0.50, 0.84, 0.62, 0.55 }   -- the fill's 159,232,180 -> 95,198,134 at .55, one stop
local CORAL      = { 0.94, 0.43, 0.35, 1 }      -- #f06e5a, solid below 40%
local LOW_INK    = { 1.00, 0.70, 0.65, 1 }      -- #ffb3a6
local PULLED     = { 0.94, 0.54, 0.48, 1 }      -- #f08a7a
local LOW        = 0.4

-- One stops table, kept, so the client builds its curve once.
local HEALTH_STOPS = { { 0, CORAL }, { LOW, GREEN } }

-- ---------------------------------------------------------------------------
-- Blizzard's own, out of the way
-- ---------------------------------------------------------------------------

--- The client's raid frames. Shown until now on purpose (Joe, 2026-10-23:
--  the party capsules give way to them in a raid); the weave replaces them.
--  Parked, and asked again on every roster change, because a park is refused
--  in a fight. Parked rather than deafened so the setting, or the module,
--  turned off gives them back at once (Joe, 2026-10-24).
function RF:HideBlizzard()
	if not (self.enabled and cfg().hideBlizzard) then return self:ShowBlizzard() end
	local f = _G.CompactRaidFrameContainer
	self.hideReport = f and (A:Banish(f, true) and "hidden" or "refused") or "absent"
end

function RF:ShowBlizzard()
	local f = _G.CompactRaidFrameContainer
	if f and A.homes[f] and A:Unbanish(f) then self.hideReport = "shown" end
	-- Not back into a raid tab the Toolbox has put away: their home on Era
	-- (Blizzard_CompactRaidFrameManager.lua:23), and a hidden parent.
	local p = f and f:GetParent()
	if p and A.banished[p] and not InCombatLockdown() then f:SetParent(UIParent) end
end

-- ---------------------------------------------------------------------------
-- a cell
-- ---------------------------------------------------------------------------

--- What a cell's role tag says. DPS says nothing; a secret answer (a unit
--  outside the group, which a raid member is not) says nothing either.
local function RoleLetter(unit)
	local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
	if A.IsSecret(role) then return nil end
	if role == "TANK" then return "T" end
	if role == "HEALER" then return "H" end
	return nil
end

--- The aura icons. Forever: the client's own, in a container we size and
--  bind (W.CreateAuraContainer). Era has no containers, so three squares of
--  ours filled from the plain reads - the same look, by Joe's rule.
local function InitIcon(button)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetIcon(icon)
	-- A click on an icon should reach the cell under it, which targets.
	pcall(button.SetMouseClickEnabled, button, false)
end

local function BuildIcons(cell)
	if W.AuraContainersAvailable() then
		local FD = AnchorUtil.FlowDirection
		local c, failed = W.CreateAuraContainer(cell, {
			size = ICON,
			point = { "BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3 },
			anchor = "BOTTOMRIGHT",
			growth = { FD.Left, FD.Up },
			groups = { { key = "dispel", filter = "HARMFUL|RAID", maxFrameCount = ICONS,
				layout = { elementSpacing = 1 }, init = InitIcon } },
		})
		cell.auras = c
		if failed[1] then RF.auraFailures = failed end
		return
	end
	cell.icons = {}
	for i = 1, ICONS do
		local t = cell:CreateTexture(nil, "OVERLAY")
		t:SetSize(ICON, ICON)
		t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		t:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3 - (i - 1) * (ICON + 1), 3)
		t:Hide()
		cell.icons[i] = t
	end
end

local UpdateCell

local function DressCell(cell)
	if cell.dressed then return end
	cell.dressed = true

	Glass.MakePanel(cell, { corner = 8, fill = "glass", edge = "glassEdge" })

	-- The fill, behind the row, from the left.
	local fill = CreateFrame("StatusBar", nil, cell)
	fill:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
	fill:SetStatusBarTexture(Media.texture.flat)
	fill:SetMinMaxValues(0, 1)
	fill:SetValue(1)
	fill:SetFrameLevel(cell:GetFrameLevel())
	cell.fill = fill

	-- Content rides above the fill.
	local over = CreateFrame("Frame", nil, cell)
	over:SetAllPoints(cell)
	over:SetFrameLevel(fill:GetFrameLevel() + 2)
	cell.over = over

	cell.dot = over:CreateTexture(nil, "OVERLAY")
	cell.dot:SetTexture(Media.texture.chipDisc)

	cell.name = W.Text(over, "unitName", "LEFT")
	cell.name:SetWordWrap(false)

	-- The tag in the accent at 85%: the token through W.Color, so a skin
	-- change reaches it, and the 85% as the string's own alpha.
	cell.role = W.Text(over, "unitName", "LEFT")
	W.Color(cell.role, Palette.c.accent)
	cell.role:SetAlpha(0.85)

	-- A fixed ink, written by the client below 40%: handed over through
	-- W.Color so the skin sweep leaves it alone.
	cell.low = W.Text(over, "unitName", "RIGHT")
	W.Color(cell.low, LOW_INK)

	-- Dead and offline: the name struck through.
	cell.strike = over:CreateTexture(nil, "OVERLAY", nil, 2)
	cell.strike:SetTexture(Media.texture.flat)
	cell.strike:SetHeight(1)
	cell.strike:Hide()

	-- Your target: an accent outline over the cell. Its own panel, so the
	-- cell's rim stays free for the threat edge.
	local sel = Glass.CreatePanel(cell, { corner = 8, fill = "glass", edge = "accent" })
	sel:SetAllPoints(cell)
	sel:SetFillColor({ 0, 0, 0, 0 })
	sel:SetFrameLevel(over:GetFrameLevel() + 1)
	sel:EnableMouse(false)
	sel:Hide()
	cell.sel = sel

	BuildIcons(cell)

	-- Hover: the rim at accent 60%, unless threat already owns it.
	cell:HookScript("OnEnter", function(self)
		self.hovered = true
		RF:UpdateEdge(self)
	end)
	cell:HookScript("OnLeave", function(self)
		self.hovered = nil
		RF:UpdateEdge(self)
	end)
	-- The header hands a cell its unit, in a fight or out, from secure code.
	-- Following it from here is reading, which is always allowed.
	cell:HookScript("OnAttributeChanged", function(self, name)
		if name == "unit" then UpdateCell(self) end
	end)
end

--- Lay one cell out at a density. Out of combat only: it sizes a protected
--  frame.
local function LayoutCell(cell, d)
	local g = Gaps(d)
	cell:SetSize(d.w, d.h)
	Glass.SetPanelCorner(cell, d.h / 4)
	Glass.SetPanelCorner(cell.sel, d.h / 4)

	cell.dot:ClearAllPoints()
	cell.dot:SetSize(g.dot, g.dot)
	cell.dot:SetPoint("LEFT", cell, "LEFT", g.pad, 0)

	Media:SetFont(cell.name, "unitName", d.font)
	cell.name._aetherSize = d.font
	Media:SetFont(cell.role, "unitName", d.font - 2)
	cell.role._aetherSize = d.font - 2
	Media:SetFont(cell.low, "unitName", d.font)
	cell.low._aetherSize = d.font

	cell.low:ClearAllPoints()
	cell.low:SetPoint("RIGHT", cell, "RIGHT", -g.pad, 0)

	cell.name:ClearAllPoints()
	cell.name:SetPoint("LEFT", cell.dot, "RIGHT", g.inner, 0)
	-- Room for the name: the cell less its padding, the dot, and what sits
	-- to the right of it. The number takes its own width when it shows; the
	-- tag goes after the name, inside this.
	cell.nameRoom = d.w - g.pad * 2 - g.dot - g.inner
	cell.role:ClearAllPoints()
	cell.role:SetPoint("LEFT", cell.name, "RIGHT", 3, 0)
	cell.role:SetShown(not d.dense)
	cell.dense = d.dense

	cell.strike:ClearAllPoints()
	cell.strike:SetPoint("LEFT", cell.name, "LEFT", 0, 0)
	cell.strike:SetPoint("RIGHT", cell.name, "RIGHT", 0, 0)
end

-- ---------------------------------------------------------------------------
-- what a cell shows
-- ---------------------------------------------------------------------------

function RF:UpdateEdge(cell)
	local unit = cell.unit
	local threat = unit and UnitThreatSituation and UnitThreatSituation(unit)
	if A.IsSecret(threat) then threat = nil end
	local c = Palette.c
	local colour
	if threat == 1 then colour = c.danger
	elseif threat and threat >= 2 then colour = PULLED end

	if colour then
		cell:SetEdgeColor(colour)
		cell:SetRimGlow({ colour[1], colour[2], colour[3], 0.6 })
	elseif cell.hovered then
		local a = c.accent
		cell:SetEdgeColor({ a[1], a[2], a[3], 0.6 })
		cell:SetRimGlow(nil)
	else
		cell:ApplySkin("glass", "glassEdge")
		cell:SetRimGlow(nil)
	end
end

local function UpdateHealth(cell)
	local unit = cell.unit
	if not unit then return end
	local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
	local offline = UnitIsConnected and not UnitIsConnected(unit)
	if A.IsSecret(dead) then dead = false end
	if A.IsSecret(offline) then offline = false end

	cell.fill:SetShown(not (dead or offline))
	cell.strike:SetShown(dead or offline)
	cell.name:SetAlpha((dead or offline) and 0.4 or 1)
	cell.dot:SetAlpha(offline and 0.35 or 1)
	if dead or offline then
		cell.low:SetText("")
		return
	end

	-- Written, never read: both take a secret.
	cell.fill:SetMinMaxValues(0, UnitHealthMax(unit))
	cell.fill:SetValue(UnitHealth(unit))
	W.HealthColor(cell.fill:GetStatusBarTexture(), unit, HEALTH_STOPS)
	W.HealthPercentText(cell.low, unit, LOW, LOW_INK)
end

local function UpdateIcons(cell)
	if cell.auras or not cell.icons then return end
	local unit = cell.unit
	local get = A:GetModule("auras") and A:GetModule("auras").GetAura
	local n = 0
	if unit and get then
		for i = 1, 40 do
			local name, tex = get(unit, i, "HARMFUL|RAID")
			if not name then break end
			n = n + 1
			if n > ICONS then break end
			cell.icons[n]:SetTexture(tex)
			cell.icons[n]:Show()
		end
	end
	for i = math.min(n, ICONS) + 1, ICONS do cell.icons[i]:Hide() end
end

local function UpdateName(cell)
	local unit = cell.unit
	if not unit then return end
	cell.name:SetText(UnitName(unit) or "")

	local cc = Palette:ClassColor(unit)
	if cc then
		cell.dot:SetVertexColor(cc[1], cc[2], cc[3], 1)
	else
		local t = Palette.c.textDim
		cell.dot:SetVertexColor(t[1], t[2], t[3], 1)
	end

	local letter = not cell.dense and RoleLetter(unit)
	cell.role:SetText(letter or "")
	-- The name truncates before the tag: room less the tag's own width,
	-- measured on a ruler (the cell hangs off a secure header).
	local tagW = letter and ((W.StringWidth(cell.role) or 8) + 3) or 0
	cell.name:SetWidth(math.max(10, (cell.nameRoom or 60) - tagW))
end

local function UpdateTarget(cell)
	local unit = cell.unit
	if not unit then cell.sel:Hide() return end
	W.ShowFromBoolean(cell.sel, UnitIsUnit and UnitIsUnit(unit, "target"))
end

UpdateCell = function(cell)
	local unit = cell:GetAttribute("unit")
	cell.unit = unit
	if not unit then return end
	if cell.auras then
		pcall(cell.auras.SetUnit, cell.auras, unit)
		pcall(cell.auras.UpdateAllAuras, cell.auras)
	end
	UpdateName(cell)
	UpdateHealth(cell)
	UpdateIcons(cell)
	UpdateTarget(cell)
	RF:UpdateEdge(cell)
	W.RangeAlpha(cell, unit, 0.45)
end
RF.UpdateCell = UpdateCell

--- Every dressed cell showing a unit, the live set the events walk.
function RF:Cells()
	local out = {}
	for _, h in ipairs(self.headers or {}) do
		for i = 1, PER_GROUP do
			local cell = h:GetAttribute("child" .. i)
			if cell and cell.dressed and cell.unit and cell:IsShown() then
				out[#out + 1] = cell
			end
		end
	end
	return out
end

local function ForUnit(unit, fn)
	for _, cell in ipairs(RF:Cells()) do
		if cell.unit == unit then fn(cell) end
	end
end

-- ---------------------------------------------------------------------------
-- the weave
-- ---------------------------------------------------------------------------

--- The client's group headers, one per group, inside one container that
--  carries the visibility rule and the mover's grip.
function RF:Build()
	local weave = CreateFrame("Frame", ADDON .. "Raid", UIParent)
	weave:SetSize(1, 1)
	self.weave = weave

	self.headers, self.labels = {}, {}
	for g = 1, GROUPS do
		local h = CreateFrame("Frame", ADDON .. "RaidGroup" .. g, weave, "SecureGroupHeaderTemplate")
		h:SetAttribute("template", "SecureUnitButtonTemplate")
		h:SetAttribute("groupFilter", tostring(g))
		h:SetAttribute("showRaid", true)
		h:SetAttribute("point", "LEFT")
		h:SetAttribute("unitsPerColumn", PER_GROUP)
		h:SetAttribute("maxColumns", 1)
		-- The cell's size and its clicks, set by the client as it makes each
		-- cell - which, being secure, it may do in a fight.
		h:SetAttribute("initialConfigFunction", [[
			local header = self:GetParent()
			self:SetWidth(header:GetAttribute("cellW") or 120)
			self:SetHeight(header:GetAttribute("cellH") or 34)
			self:SetAttribute("*type1", "target")
			self:SetAttribute("*type2", "togglemenu")
		]])
		h:Show()
		self.headers[g] = h

		-- The group number: accent at 50%, the token through W.Color.
		local label = W.Text(weave, "unitName", "LEFT")
		label:SetText(tostring(g))
		W.Color(label, Palette.c.accent)
		label:SetAlpha(0.5)
		self.labels[g] = label
	end

	-- The bond: accent at 45% for the strand and its stub, 100% for the root.
	local bond = {}
	bond.strand = weave:CreateTexture(nil, "BACKGROUND")
	bond.strand:SetTexture(Media.texture.flat)
	bond.strand:SetWidth(1.5)
	bond.stub = weave:CreateTexture(nil, "BACKGROUND")
	bond.stub:SetTexture(Media.texture.flat)
	bond.stub:SetHeight(1.5)
	bond.root = weave:CreateTexture(nil, "ARTWORK")
	bond.root:SetTexture(Media.texture.chipDisc)
	bond.root:SetSize(ROOT, ROOT)
	-- The strand's foot: where the bond to the player leaves it in unlock.
	bond.foot = CreateFrame("Frame", nil, weave)
	bond.foot:SetSize(1, 1)
	self.bond = bond
end

--- Lay the bond along the rows: the root and the stub on the first row's
--  centre line, the strand down to the last's. `first` and `last` are those
--  centres, measured down from the weave's top.
function RF:LayBond(first, last)
	local b, a = self.bond, Palette.c.accent
	W.Tint(b.strand, a, 0.45)
	W.Tint(b.stub, a, 0.45)
	W.Tint(b.root, a, 1)

	b.root:ClearAllPoints()
	b.root:SetPoint("CENTER", self.weave, "TOPLEFT", 0, -first)
	b.stub:ClearAllPoints()
	b.stub:SetPoint("LEFT", self.weave, "TOPLEFT", 0, -first)
	b.stub:SetWidth(BOND)
	b.strand:ClearAllPoints()
	b.strand:SetPoint("TOP", self.weave, "TOPLEFT", 0, -first)
	b.strand:SetHeight(math.max(0.01, last - first))
	b.strand:SetShown(last > first)
	b.foot:ClearAllPoints()
	b.foot:SetPoint("CENTER", self.weave, "TOPLEFT", 0, -last)
end

--- Make every cell now, out of combat: see the note at the top.
function RF:Precreate()
	if InCombatLockdown() then self.pendingPrecreate = true return end
	self.pendingPrecreate = nil
	local weave = self.weave
	if UnregisterStateDriver then UnregisterStateDriver(weave, "visibility") end
	local alpha = weave:GetAlpha()
	weave:SetAlpha(0)
	weave:Show()
	for _, h in ipairs(self.headers) do
		h:SetAttribute("startingIndex", 1 - PER_GROUP)
		h:SetAttribute("startingIndex", 1)
		for i = 1, PER_GROUP do
			local cell = h:GetAttribute("child" .. i)
			if cell then DressCell(cell) end
		end
	end
	weave:SetAlpha(alpha)
	self:DriveVisibility()
end

--- In a raid and only in a raid: the party capsules are the ≤5 frames.
function RF:DriveVisibility()
	if RegisterStateDriver then
		RegisterStateDriver(self.weave, "visibility", "[group:raid] show; hide")
	end
end

--- Size the cells for the raid, and stack the groups that have anyone in
--  them, top down. Out of combat only; asked for in a fight, it waits.
function RF:Layout()
	if InCombatLockdown() then self.pendingLayout = true return end
	self.pendingLayout = nil

	local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
	local d = DensityFor(n)
	local g = Gaps(d)
	self.density = d

	local used = {}
	if IsInRaid and IsInRaid() and GetRaidRosterInfo then
		for i = 1, n do
			local _, _, sub = GetRaidRosterInfo(i)
			if sub then used[sub] = true end
		end
	end

	local y = 0
	local first, last
	for gi, h in ipairs(self.headers) do
		h:SetAttribute("cellW", d.w)
		h:SetAttribute("cellH", d.h)
		for i = 1, PER_GROUP do
			local cell = h:GetAttribute("child" .. i)
			if cell then
				DressCell(cell)
				LayoutCell(cell, d)
			end
		end
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", self.weave, "TOPLEFT", ROWS_X, -y)
		-- Any attribute set while shown re-lays the header out.
		h:SetAttribute("xOffset", g.cell)

		local label = self.labels[gi]
		label:ClearAllPoints()
		label:SetPoint("LEFT", self.weave, "TOPLEFT", BOND, -y - d.h / 2)
		label:SetWidth(NUMBER)
		Media:SetFont(label, "unitName", d.font - 2)
		label._aetherSize = d.font - 2
		label:SetShown(used[gi] == true)

		if used[gi] then
			first = first or (y + d.h / 2)
			last = y + d.h / 2
			y = y + d.h + g.group
		end
	end

	local width = ROWS_X + PER_GROUP * d.w + (PER_GROUP - 1) * g.cell
	local height = math.max(d.h, y - g.group)
	self.weave:SetSize(width, height)
	-- No one in a group yet (out of a raid): the bond on the first row.
	self:LayBond(first or d.h / 2, last or d.h / 2)

	for _, cell in ipairs(self:Cells()) do UpdateCell(cell) end
end

-- ---------------------------------------------------------------------------
-- life
-- ---------------------------------------------------------------------------

function RF:RegisterMovers()
	-- Clear of the Toolbox trunk's stubs and labels on the left edge (they
	-- run out to about 170), where the party stack sits for the same reason.
	-- Bonded to the player (13b: "the weave bonds to the player capsule"), so
	-- it goes where the player goes. In unlock that bond is dashed, from the
	-- strand's foot, and the root node is where the handle's junction sits.
	A.Movers:Register("raid", self.weave,
		{ point = "TOPLEFT", relPoint = "TOPLEFT", x = 190, y = -220 }, L.movers.name.raid,
		{ parent = "player", bondStyle = "dashed", bondFrom = self.bond.foot,
			junctionAt = self.bond.root })
end

local rangeClock = 0
local function Tick(_, elapsed)
	rangeClock = rangeClock + (elapsed or 0.1)
	if rangeClock < 0.5 then return end
	rangeClock = 0
	for _, cell in ipairs(RF:Cells()) do W.RangeAlpha(cell, cell.unit, 0.45) end
end

function RF:RegisterEvents()
	local function unitEvent(fn)
		return function(_, _, unit) ForUnit(unit, fn) end
	end
	A:RegisterEvent(self, "UNIT_HEALTH",        unitEvent(UpdateHealth))
	A:RegisterEvent(self, "UNIT_MAXHEALTH",     unitEvent(UpdateHealth))
	A:RegisterEvent(self, "UNIT_CONNECTION",    unitEvent(UpdateHealth))
	A:RegisterEvent(self, "UNIT_FLAGS",         unitEvent(UpdateHealth))
	A:RegisterEvent(self, "UNIT_NAME_UPDATE",   unitEvent(UpdateName))
	A:RegisterEvent(self, "UNIT_AURA",          unitEvent(UpdateIcons))
	A:RegisterEvent(self, "UNIT_THREAT_SITUATION_UPDATE",
		unitEvent(function(cell) RF:UpdateEdge(cell) end))

	local function sweep()
		RF:HideBlizzard()
		RF:Layout()
	end
	A:RegisterEvent(self, "GROUP_ROSTER_UPDATE",   sweep)
	A:RegisterEvent(self, "PLAYER_ROLES_ASSIGNED", sweep)
	A:RegisterEvent(self, "PLAYER_ENTERING_WORLD", sweep)
	A:RegisterEvent(self, "PLAYER_TARGET_CHANGED", function()
		for _, cell in ipairs(RF:Cells()) do UpdateTarget(cell) end
	end)
	A:RegisterEvent(self, "PLAYER_REGEN_ENABLED", function()
		if RF.pendingPrecreate then RF:Precreate() end
		if RF.pendingLayout then RF:Layout() end
		RF:HideBlizzard()
	end)
end

function RF:OnEnable()
	if not self.weave then self:Build() end
	self:Precreate()
	self:RegisterMovers()
	self:RegisterEvents()
	self:HideBlizzard()
	self:Layout()
	A:RegisterTicker(self, Tick)
end

function RF:OnDisable()
	if not self.weave then return end
	if UnregisterStateDriver then UnregisterStateDriver(self.weave, "visibility") end
	self.weave:Hide()
	self:ShowBlizzard()
end

function RF:OnConfigChanged()
	self:HideBlizzard()
end

function RF:OnSkinChanged()
	for _, cell in ipairs(self:Cells()) do
		UpdateName(cell)
		self:UpdateEdge(cell)
	end
	if self.weave then self:Layout() end
end
