--[[--------------------------------------------------------------------------
	Lattice :: Raid frames - the weave

	Phases 1 to 4 of the raid build (sara-vault: "Lattice Raid Frames Build
	Plan"): every member of the raid as a cell, in one look, hung off its group
	bond and bonded to the player, with the people you watch pinned above it as
	full capsules, set up by plain settings.

	NO LENSES. The handoff bundles who is pinned, the edges, the size, rows or
	columns and the range fade into a preset chosen by role. Joe, 2026-10-24:
	"I'm not sure about the 'raid lens' concept. I don't even really
	understand it." With dispel as icons the presets barely differed, so each
	is its own setting now (Options > Raid), and the threat edge is always on.

	PINS COPY, they do not move anyone: a pinned member keeps their cell, and
	hovering the pin lights it (Joe, 2026-10-23). The pins are ONE MORE CLIENT
	HEADER, kept on its people by a list of names (nameList, sorted as listed:
	SecureGroupHeaders.lua:476-486) - so a roster that reshuffles mid-fight
	still finds them, securely. The list is written out of combat: the Main
	Tanks and tanks, the healers, then whoever you pinned by name. The boss's
	target is not a raid member, so it is its own button, on boss1target.

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

-- The pins (README, "Pin"): five at most, in a row above the weave under
-- their label, as wide as their count allows, the weave 16 below them.
local PINS = 5
local PIN_W = { 250, 250, 220, 190, 190 }
-- 44 tall: a 36 disc and 4 above and below it. Our party capsule is 52 with a
-- 38 disc, which stood too big over the cells (Joe, 2026-10-24), so a pin is
-- the capsule drawn at 44/52 - every part of it, in proportion - and given
-- the width that comes back to the handoff's on screen.
local PIN_H = 44
local PIN_GAP = 10
local PIN_LABEL_H, PIN_LABEL_GAP = 12, 10
local PIN_TO_WEAVE = 16

-- Groups as columns (a setting): each group's number in a row above it, the
-- columns side by side from the bond (Raid.dc.html 13d).
local COL_NUMBER_H, COL_NUMBER_GAP = 12, 4

local ICON = 12   -- an aura, the client's own icon
local ICONS = 3   -- in all, whatever they are

-- WHAT A CELL SHOWS (Joe, 2026-10-24): every debuff, the ones you can dispel
-- first, then the buffs you cast - HoTs and shields. Not everyone's buffs:
-- forty cells of Fortitude is noise. In this order, three at most.
local AURA_GROUPS = {
	{ key = "dispel",  filter = "HARMFUL|RAID" },
	{ key = "debuffs", filter = "HARMFUL|!RAID" },
	{ key = "mine",    filter = "HELPFUL|PLAYER" },
}

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
		-- THREE IN ALL, by the trays' method (Modules/Auras.lua, BuildTray): the
		-- groups flow along one line in their order - a group starts a new line
		-- only when told to (forceNewLine, false by default,
		-- Blizzard_AuraContainerShared.lua:161) - and whatever passes the third
		-- wraps onto a line above, outside a host that clips it.
		local host = CreateFrame("Frame", nil, cell)
		host:SetClipsChildren(true)
		host:SetSize(ICONS * (ICON + 1) - 1, ICON)
		host:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -3, 3)
		cell.auraHost = host
		local FD = AnchorUtil.FlowDirection
		local groups = {}
		for i, g in ipairs(AURA_GROUPS) do
			groups[i] = { key = g.key, filter = g.filter, maxFrameCount = ICONS,
				layout = { elementSpacing = 1, lineSpacing = 2, groupLineSpacing = 2,
					layoutIndex = i }, init = InitIcon }
		end
		local c, failed = W.CreateAuraContainer(host, {
			size = ICON,
			point = { "BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0 },
			anchor = "BOTTOMRIGHT",
			growth = { FD.Left, FD.Up },
			lineSize = ICONS * (ICON + 1) - 1,
			groups = groups,
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

	-- RIGHT-CLICK TOO. The template answers the left button alone, so the
	-- unit menu never opened from a cell (Joe, 2026-10-24). Here, at login and
	-- out of combat, where the call is allowed.
	cell:RegisterForClicks("AnyUp")

	-- The fill, behind the row, from the left, inside the rim.
	local fill = CreateFrame("StatusBar", nil, cell)
	fill:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
	fill:SetStatusBarTexture(Media.texture.flat)
	fill:SetMinMaxValues(0, 1)
	fill:SetValue(1)
	fill:SetFrameLevel(cell:GetFrameLevel())
	-- ROUNDED AS THE CELL IS, by the bars' own method (W.AddMask, as
	-- W.CreateBar): it ran square past the round corners (Joe, 2026-10-24).
	-- The mask is the density's, set again in LayoutCell.
	cell.fillMask = W.AddMask(fill:GetStatusBarTexture(), fill, Media.texture.cellMask[120], fill)
	cell.fill = fill

	-- Content rides above the fill.
	local over = CreateFrame("Frame", nil, cell)
	over:SetAllPoints(cell)
	over:SetFrameLevel(fill:GetFrameLevel() + 2)
	cell.over = over

	cell.dot = over:CreateTexture(nil, "OVERLAY")
	cell.dot:SetTexture(Media.texture.chipDisc)
	-- The raid mark, on the class dot (a setting).
	cell.mark = over:CreateTexture(nil, "OVERLAY", nil, 3)
	cell.mark:SetPoint("CENTER", cell.dot, "CENTER", 0, 0)
	cell.mark:Hide()

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
	if cell.fillMask and Media.texture.cellMask[d.w] then
		cell.fillMask:SetTexture(Media.texture.cellMask[d.w],
			"CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end

	cell.dot:ClearAllPoints()
	cell.dot:SetSize(g.dot, g.dot)
	cell.dot:SetPoint("LEFT", cell, "LEFT", g.pad, 0)
	cell.mark:SetSize(g.dot * 2 + 2, g.dot * 2 + 2)

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
	elseif cell.hovered or cell.copied then
		-- Its own hover, or its pin's: a pin copies its member, and hovering
		-- the pin lights the cell it copies (README, "Pin").
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

--- Era: the same three groups from the plain reads. It has no `!RAID`, so the
--  other debuffs are every harmful one not already shown as yours to dispel.
local function UpdateIcons(cell)
	if cell.auras or not cell.icons then return end
	local unit = cell.unit
	local get = A:GetModule("auras") and A:GetModule("auras").GetAura
	local n = 0
	local function add(tex)
		n = n + 1
		cell.icons[n]:SetTexture(tex)
		cell.icons[n]:Show()
	end
	if unit and get then
		local dispel = {}
		for i = 1, 40 do
			if n >= ICONS then break end
			local name, tex = get(unit, i, "HARMFUL|RAID")
			if not name then break end
			dispel[name] = true
			add(tex)
		end
		for i = 1, 40 do
			if n >= ICONS then break end
			local name, tex = get(unit, i, "HARMFUL")
			if not name then break end
			if not dispel[name] then add(tex) end
		end
		-- YOURS BY THE CASTER, as Blizzard's own raid frames decide it
		-- (AuraUtil.ShouldDisplayBuff, :307: you, your pet, your vehicle).
		-- The PLAYER filter alone let Thrall's Warchief's Blessing through
		-- onto a warrior's cell (Joe, 2026-10-24).
		local function yours(source)
			if not source or A.IsSecret(source) then return false end
			return source == "player" or source == "pet" or source == "vehicle"
		end
		for i = 1, 40 do
			if n >= ICONS then break end
			local name, tex, _, _, _, _, _, source = get(unit, i, "HELPFUL|PLAYER")
			if not name then break end
			if yours(source) then add(tex) end
		end
	end
	for i = n + 1, ICONS do cell.icons[i]:Hide() end
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

	-- Raid marks on the class dot, if asked for; the dot gives way to a mark.
	local marks = RF:View().marks
	local marked = marks and W.SetRaidMark(cell.mark, unit)
	if not marks then cell.mark:Hide() end
	cell.dot:SetShown(not marked)

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
	W.RangeAlpha(cell, unit, RF:FadeTo())
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
-- the pins
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- the settings
-- ---------------------------------------------------------------------------

--- The settings as one table: who is pinned, the range fade, rows or
--  columns, a size held or none, and the raid marks.
local function ViewFrom(c)
	return {
		pins = { tanks = c.pinTanks, healers = c.pinHealers, boss = c.pinBossTarget },
		fade = c.rangeFade ~= false,
		columns = c.columns and true or false,
		density = tonumber(c.cellSize),
		marks = c.raidMarks ~= false,
	}
end

--- The settings the weave was last laid out with. Taken at Layout, out of
--  combat, so a change made in a fight applies all together when it ends.
function RF:View()
	return self.view or ViewFrom(cfg())
end

--- How far a member out of range fades: 45% (README), or not at all.
function RF:FadeTo()
	return self:View().fade and 0.45 or 1
end

--- The names you pinned, one list per character. Two shapes it had before
--  are read into it: the first phase 3's `names`, which it is again, and
--  phase 4's list per lens, merged when the lenses went (2026-10-24).
local function PinStore()
	local char = A.db and A.db.char
	if not char then return {} end
	local p = char.raidPins or {}
	char.raidPins = p
	p.names = p.names or {}
	if p.byLens then
		local seen = {}
		for _, n in ipairs(p.names) do seen[n] = true end
		for _, list in pairs(p.byLens) do
			for _, n in ipairs(list) do
				if not seen[n] then
					seen[n] = true
					p.names[#p.names + 1] = n
				end
			end
		end
		p.byLens = nil
	end
	char.raidLens = nil
	return p.names
end

--- Who is pinned, in order, each once and five at most: the Main Tanks and
--  tanks, the healers, then the names you pinned who are in the raid. Read
--  from the roster, so out of combat: GetRaidRosterInfo's tenth answer is the
--  raid role (MAINTANK - what a raid leader sets on Era, where a role is
--  opt-in), its twelfth the assigned one.
function RF:PinNames(view)
	view = view or ViewFrom(cfg())
	local pins = view.pins
	local out, seen, here = {}, {}, {}
	local function add(name)
		if name and not seen[name] and #out < PINS then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	if not (IsInRaid and IsInRaid()) then return out end
	local roster = {}
	for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
		local name, _, _, _, _, _, _, _, _, role, _, assigned = GetRaidRosterInfo(i)
		if name and not A.IsSecret(name) then
			if A.IsSecret(role) then role = nil end
			if A.IsSecret(assigned) then assigned = nil end
			roster[#roster + 1] = { name = name, role = role, assigned = assigned }
			here[name] = true
		end
	end
	if pins.tanks then
		for _, r in ipairs(roster) do
			if r.role == "MAINTANK" or r.assigned == "TANK" then add(r.name) end
		end
	end
	if pins.healers then
		for _, r in ipairs(roster) do
			if r.assigned == "HEALER" then add(r.name) end
		end
	end
	for _, name in ipairs(PinStore()) do
		if here[name] then add(name) end
	end
	return out
end

function RF:IsPinned(name)
	for _, n in ipairs(PinStore()) do
		if n == name then return true end
	end
	return false
end

--- Pin or unpin someone by name, kept per character. The row is laid out
--  again out of combat; in a fight that waits, and says so.
function RF:SetPinned(name, on)
	local names = PinStore()
	for i = #names, 1, -1 do
		if names[i] == name then table.remove(names, i) end
	end
	if on then names[#names + 1] = name end
	if InCombatLockdown() then A:Print(L.raid.after_combat) end
	self:Layout()
end

--- What the row's label says: PINNED, then what pins it.
local function PinRule(view)
	local pins, parts = view.pins, {}
	if pins.tanks then parts[#parts + 1] = L.raid.pinned_tanks end
	if pins.healers then parts[#parts + 1] = L.raid.pinned_healers end
	if #PinStore() > 0 then parts[#parts + 1] = L.raid.pinned_names end
	if pins.boss then parts[#parts + 1] = L.raid.pinned_boss end
	local s = L.raid.pinned
	if parts[1] then s = s .. " \194\183 " .. table.concat(parts, " \194\183 ") end
	return s:upper()
end

--- A pin is the party capsule (Modules/PartyFrames.lua), dressed onto the
--  secure button its header - or, for the boss's target, we - made.
local function PartyModule() return A:GetModule("partyframes") end

function RF:UpdatePinEdge(pin)
	-- Pins carry the threat edge, as the cells do (README, "Pin").
	local unit = pin.unit
	local threat = unit and UnitThreatSituation and UnitThreatSituation(unit)
	if A.IsSecret(threat) then threat = nil end
	local colour
	if threat == 1 then colour = Palette.c.danger
	elseif threat and threat >= 2 then colour = PULLED end
	if colour then
		pin.glass:SetEdgeColor(colour)
		pin.glass:SetRimGlow({ colour[1], colour[2], colour[3], 0.6 })
	else
		pin.glass:SetRimGlow(nil)
	end
end

local function UpdatePin(pin)
	if not pin.dressed then return end
	if not pin.unit then pin.glass:Hide() return end
	PartyModule().UpdateAll(pin)
	RF:UpdatePinEdge(pin)
end

--- Hovering a pin lights the cell it copies. Not the boss's target's: its
--  cell cannot be found on Forever (Joe's decision, 2026-10-23).
function RF:CopyHighlight(pin, on)
	if pin.isBoss then return end
	for _, cell in ipairs(self:Cells()) do
		if cell.unit == pin.unit then
			cell.copied = on or nil
			self:UpdateEdge(cell)
		end
	end
end

local function DressPin(pin)
	if pin.dressed then return end
	pin.dressed = true
	-- Right-click too, as the cells (DressCell).
	pin:RegisterForClicks("AnyUp")
	PartyModule().BuildCapsule(pin:GetAttribute("unit"), pin)
	pin:HookScript("OnEnter", function(self) RF:CopyHighlight(self, true) end)
	pin:HookScript("OnLeave", function(self) RF:CopyHighlight(self, false) end)
	-- The header hands a pin its member, in a fight or out.
	pin:HookScript("OnAttributeChanged", function(self, name)
		if name == "unit" then
			self.unit = self:GetAttribute("unit")
			UpdatePin(self)
		end
	end)
end

--- Every dressed pin, the boss's target's last.
function RF:Pins()
	local out = {}
	local h = self.pinHeader
	for i = 1, PINS do
		local p = h and h:GetAttribute("child" .. i)
		if p and p.dressed then out[#out + 1] = p end
	end
	if self.bossPin then out[#out + 1] = self.bossPin end
	return out
end

local function ForPin(unit)
	for _, p in ipairs(RF:Pins()) do
		if p.unit == unit then UpdatePin(p) end
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
	-- With pins, the root goes to their row, and this thinner stub at 30%
	-- reaches the first row of the weave.
	bond.weaveStub = weave:CreateTexture(nil, "BACKGROUND")
	bond.weaveStub:SetTexture(Media.texture.flat)
	bond.weaveStub:SetHeight(1)
	-- The strand's foot: where the bond to the player leaves it in unlock.
	bond.foot = CreateFrame("Frame", nil, weave)
	bond.foot:SetSize(1, 1)
	self.bond = bond

	-- THE PINS: their label, one more client header kept on its people by
	-- name, and the boss's target on a button of its own.
	self.pinLabel = W.Text(weave, "label", "LEFT")
	W.Color(self.pinLabel, Palette.c.accent)
	self.pinLabel:SetAlpha(0.55)

	local ph = CreateFrame("Frame", ADDON .. "RaidPins", weave, "SecureGroupHeaderTemplate")
	ph:SetAttribute("template", "SecureUnitButtonTemplate")
	ph:SetAttribute("showRaid", true)
	-- An empty list is a list: nobody, not "everybody" (:407-408).
	ph:SetAttribute("nameList", "")
	ph:SetAttribute("sortMethod", "NAMELIST")
	ph:SetAttribute("point", "LEFT")
	ph:SetAttribute("xOffset", PIN_GAP)
	ph:SetAttribute("unitsPerColumn", PINS)
	ph:SetAttribute("maxColumns", 1)
	-- Empty, it shrinks to nothing (:122-125), so the boss's pin after it
	-- starts the row.
	ph:SetAttribute("minWidth", 0.1)
	ph:SetAttribute("minHeight", 0.1)
	ph:SetAttribute("initialConfigFunction", [[
		local header = self:GetParent()
		self:SetWidth(header:GetAttribute("pinW") or 250)
		self:SetHeight(header:GetAttribute("pinH") or 44)
		self:SetAttribute("*type1", "target")
		self:SetAttribute("*type2", "togglemenu")
	]])
	ph:Show()
	self.pinHeader = ph

	local boss = CreateFrame("Button", ADDON .. "RaidPinBoss", weave, "SecureUnitButtonTemplate")
	boss:SetAttribute("unit", "boss1target")
	boss:SetAttribute("*type1", "target")
	boss:SetAttribute("*type2", "togglemenu")
	boss:RegisterForClicks("AnyUp")
	boss:Hide()
	boss.isBoss = true
	DressPin(boss)
	self.bossPin = boss
end

--- Lay the bond along the rows. `first` and `last` are the first and last
--  rows' centres, measured down from the weave's top; `pins`, the pin row's,
--  when there is one. The root and its stub sit on the top one of those, the
--  strand runs down to the last row, and with pins a thinner stub at 30%
--  reaches the first row of the weave (README, "Group bond").
function RF:LayBond(first, last, pins)
	local b, a = self.bond, Palette.c.accent
	local top = pins or first
	W.Tint(b.strand, a, 0.45)
	W.Tint(b.stub, a, 0.45)
	W.Tint(b.root, a, 1)
	W.Tint(b.weaveStub, a, 0.3)

	b.root:ClearAllPoints()
	b.root:SetPoint("CENTER", self.weave, "TOPLEFT", 0, -top)
	b.stub:ClearAllPoints()
	b.stub:SetPoint("LEFT", self.weave, "TOPLEFT", 0, -top)
	b.stub:SetWidth(BOND)
	b.weaveStub:ClearAllPoints()
	b.weaveStub:SetPoint("LEFT", self.weave, "TOPLEFT", 0, -first)
	b.weaveStub:SetWidth(BOND)
	b.weaveStub:SetShown(pins ~= nil)
	b.strand:ClearAllPoints()
	b.strand:SetPoint("TOP", self.weave, "TOPLEFT", 0, -top)
	b.strand:SetHeight(math.max(0.01, last - top))
	b.strand:SetShown(last > top)
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
	-- The five pins too, for the same reason: a tank who joins mid-fight
	-- gets a dressed capsule.
	local ph = self.pinHeader
	ph:SetAttribute("startingIndex", 1 - PINS)
	ph:SetAttribute("startingIndex", 1)
	for i = 1, PINS do
		local pin = ph:GetAttribute("child" .. i)
		if pin then DressPin(pin) end
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

	-- THE PROFILE'S SCALE, as every frame here is drawn at, the party stack's
	-- way (PartyFrames.lua, PF:Layout). The weave had none, so the raid -
	-- pins most of all - drew a size apart from everything else (Joe,
	-- 2026-10-24). Here, out of combat: the weave carries secure frames.
	self.weave:SetScale(A.db.profile.scale or 1)

	-- THE SETTINGS, taken once, here, so all of them apply together.
	local view = ViewFrom(cfg())
	self.view = view

	local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
	-- A size held in the settings, or the one for the raid's.
	local d = DensityFor(view.density or n)
	local g = Gaps(d)
	self.density = d

	local used, members = {}, {}
	if IsInRaid and IsInRaid() and GetRaidRosterInfo then
		for i = 1, n do
			local _, _, sub = GetRaidRosterInfo(i)
			if sub then
				used[sub] = true
				members[sub] = (members[sub] or 0) + 1
			end
		end
	end

	-- THE PINS, a row above the weave under their label, as wide as their
	-- count allows; the weave starts 16 below them (README, "Pin").
	local names = self:PinNames(view)
	local bossOn = view.pins.boss and true or false
	local count = #names + (bossOn and 1 or 0)
	local ph, boss = self.pinHeader, self.bossPin
	local y, pinsY = 0, nil
	local pinsWidth = 0
	self.pinLabel:SetShown(count > 0)
	if count > 0 then
		-- In the pins' own units, at their scale k: a width and an offset
		-- given here come out k times as long on screen.
		local pH = A.Config:Module("partyframes").height
		local k = PIN_H / pH
		local pw = PIN_W[math.min(count, PINS)] / k
		self.pinLabel:SetText(PinRule(view))
		self.pinLabel:ClearAllPoints()
		self.pinLabel:SetPoint("TOPLEFT", self.weave, "TOPLEFT", BOND, 0)
		local rowY = PIN_LABEL_H + PIN_LABEL_GAP
		ph:SetScale(k)
		boss:SetScale(k)
		ph:SetAttribute("pinW", pw)
		ph:SetAttribute("pinH", pH)
		ph:SetAttribute("xOffset", PIN_GAP / k)
		for i = 1, PINS do
			local pin = ph:GetAttribute("child" .. i)
			if pin then
				pin:SetSize(pw, pH)
				PartyModule().LayCapsule(pin, pw)
			end
		end
		boss:SetSize(pw, pH)
		PartyModule().LayCapsule(boss, pw)
		ph:ClearAllPoints()
		ph:SetPoint("TOPLEFT", self.weave, "TOPLEFT", BOND / k, -rowY / k)
		boss:ClearAllPoints()
		boss:SetPoint("TOPLEFT", ph, "TOPRIGHT", #names > 0 and PIN_GAP / k or 0, 0)
		pinsY = rowY + PIN_H / 2
		pinsWidth = BOND + count * PIN_W[math.min(count, PINS)] + (count - 1) * PIN_GAP
		y = rowY + PIN_H + PIN_TO_WEAVE
	end
	-- The list last: set while the header is shown, it re-lays it out.
	ph:SetAttribute("nameList", table.concat(names, ","))
	-- The boss's target shows itself when there is one - but only if asked.
	if bossOn and RegisterUnitWatch then
		RegisterUnitWatch(boss)
	else
		if UnregisterUnitWatch then UnregisterUnitWatch(boss) end
		boss:Hide()
	end

	-- THE GROUPS: rows, each opening with its number, or - as the settings
	-- ask - columns from the bond, each under its number (Raid.dc.html 13d),
	-- growing down.
	local first, last
	local top = y
	local columns = view.columns
	local colTop = top + COL_NUMBER_H + COL_NUMBER_GAP
	local x = BOND
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
		local label = self.labels[gi]
		label:ClearAllPoints()
		Media:SetFont(label, "unitName", d.font - 2)
		label._aetherSize = d.font - 2
		label:SetShown(used[gi] == true)
		h:ClearAllPoints()
		-- Any attribute set while shown re-lays the header out.
		if columns then
			h:SetPoint("TOPLEFT", self.weave, "TOPLEFT", x, -colTop)
			h:SetAttribute("point", "TOP")
			h:SetAttribute("xOffset", 0)
			h:SetAttribute("yOffset", -g.cell)
			label:SetJustifyH("CENTER")
			label:SetWidth(d.w)
			label:SetPoint("TOP", self.weave, "TOPLEFT", x + d.w / 2, -top)
			if used[gi] then x = x + d.w + g.group end
		else
			h:SetPoint("TOPLEFT", self.weave, "TOPLEFT", ROWS_X, -y)
			h:SetAttribute("point", "LEFT")
			h:SetAttribute("yOffset", 0)
			h:SetAttribute("xOffset", g.cell)
			label:SetJustifyH("LEFT")
			label:SetWidth(NUMBER)
			label:SetPoint("LEFT", self.weave, "TOPLEFT", BOND, -y - d.h / 2)
			if used[gi] then
				first = first or (y + d.h / 2)
				last = y + d.h / 2
				y = y + d.h + g.group
			end
		end
	end

	local width, height
	if columns then
		-- The bond from the numbers' row down to the foot of the tallest column.
		local most = 1
		for _, m in pairs(members) do most = math.max(most, m) end
		local colH = most * (d.h + g.cell) - g.cell
		first = top + COL_NUMBER_H / 2
		last = colTop + colH
		width = math.max(math.max(x - g.group, BOND + d.w), pinsWidth)
		height = colTop + colH
	else
		width = math.max(ROWS_X + PER_GROUP * d.w + (PER_GROUP - 1) * g.cell, pinsWidth)
		height = math.max(top + d.h, y - g.group)
	end
	self.weave:SetSize(width, height)
	-- No one in a group yet (out of a raid): the bond on the first row.
	self:LayBond(first or (top + d.h / 2), last or (top + d.h / 2), pinsY)

	for _, cell in ipairs(self:Cells()) do UpdateCell(cell) end
	for _, pin in ipairs(self:Pins()) do UpdatePin(pin) end
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
	local fade = RF:FadeTo()
	for _, cell in ipairs(RF:Cells()) do W.RangeAlpha(cell, cell.unit, fade) end
	-- The pins as the party capsules are, on a tick - the boss's target among
	-- them, which changes with no event on the unit it names.
	for _, pin in ipairs(RF:Pins()) do
		if pin:IsVisible() then UpdatePin(pin) end
	end
end

--- PIN or UNPIN on a raid member's own right-click menu. Menu.ModifyMenu is
--  the client's way in for an addon: it runs our callback, and the click on
--  our item, each through securecallfunction (Menu.lua:2610-2611, :922), so
--  Set Focus and the marks in the same menu stay clean.
function RF:HookMenu()
	if self.menuHooked or not (Menu and Menu.ModifyMenu) then return end
	self.menuHooked = true
	local function add(_, root, ctx)
		if not (RF.enabled and IsInRaid and IsInRaid() and ctx and ctx.unit) then return end
		local name = (GetUnitName and GetUnitName(ctx.unit, true)) or UnitName(ctx.unit)
		if not name or A.IsSecret(name) then return end
		local pinned = RF:IsPinned(name)
		root:CreateDivider()
		root:CreateButton(pinned and L.raid.unpin or L.raid.pin,
			function() RF:SetPinned(name, not pinned) end)
	end
	-- A raid member's menu, whichever the client picks for them.
	for _, tag in ipairs({ "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID", "MENU_UNIT_PARTY" }) do
		Menu.ModifyMenu(tag, add)
	end
end

function RF:RegisterEvents()
	local function unitEvent(fn, pins)
		return function(_, _, unit)
			ForUnit(unit, fn)
			if pins then ForPin(unit) end
		end
	end
	A:RegisterEvent(self, "UNIT_HEALTH",        unitEvent(UpdateHealth, true))
	A:RegisterEvent(self, "UNIT_MAXHEALTH",     unitEvent(UpdateHealth, true))
	A:RegisterEvent(self, "UNIT_CONNECTION",    unitEvent(UpdateHealth, true))
	A:RegisterEvent(self, "UNIT_FLAGS",         unitEvent(UpdateHealth, true))
	A:RegisterEvent(self, "UNIT_NAME_UPDATE",   unitEvent(UpdateName, true))
	A:RegisterEvent(self, "UNIT_AURA",          unitEvent(UpdateIcons))
	A:RegisterEvent(self, "UNIT_THREAT_SITUATION_UPDATE",
		unitEvent(function(cell) RF:UpdateEdge(cell) end, true))
	A:RegisterEvent(self, "UNIT_POWER_UPDATE", function(_, _, unit) ForPin(unit) end)
	A:RegisterEvent(self, "UNIT_MAXPOWER",     function(_, _, unit) ForPin(unit) end)
	-- The boss's target: a new boss, or the boss turning to someone else.
	A:RegisterEvent(self, "UNIT_TARGET", function(_, _, unit)
		if unit == "boss1" then UpdatePin(RF.bossPin) end
	end)
	A:RegisterEvent(self, "INSTANCE_ENCOUNTER_ENGAGE_UNIT", function() UpdatePin(RF.bossPin) end)

	local function sweep()
		RF:HideBlizzard()
		RF:Layout()
	end
	A:RegisterEvent(self, "GROUP_ROSTER_UPDATE",   sweep)
	A:RegisterEvent(self, "PLAYER_ROLES_ASSIGNED", sweep)
	-- The raid marks on the dots.
	A:RegisterEvent(self, "RAID_TARGET_UPDATE", function()
		for _, cell in ipairs(RF:Cells()) do UpdateName(cell) end
	end)
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
	self:HookMenu()
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
	-- Who is pinned may have changed.
	if self.weave then self:Layout() end
end

function RF:OnSkinChanged()
	for _, cell in ipairs(self:Cells()) do
		UpdateName(cell)
		self:UpdateEdge(cell)
	end
	if self.weave then self:Layout() end
end
