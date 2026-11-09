--[[--------------------------------------------------------------------------
	Lattice :: Version check

	Says once a session when somebody in your guild or group has a newer
	Lattice. Addon messages only reach guild, party and raid, so a player on
	their own never hears.

	Method from LibVersionCheck-1.0 (DialogKey_Numy, on WoW Forever): send our
	version on login, on joining a guild or a group, and answer a copy older
	than ours with a whisper so it hears about ours.
----------------------------------------------------------------------------]]

local ADDON, A = ...
local L = A.L

local VC = { sent = {}, answered = {} }
A.VersionCheck = VC

VC.PREFIX = "Lattice"
local THROTTLE = 60  -- seconds between sends on one channel

local function Enabled()
	return not (A.db and A.db.profile and A.db.profile.versionCheck == false)
end

local function Send(channel, target)
	if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
	-- Refused in some instances on Forever; nothing to do about it.
	pcall(C_ChatInfo.SendAddonMessage, VC.PREFIX, "V1:" .. tostring(A.version), channel, target)
end

function VC:Broadcast()
	if not Enabled() then return end
	local now = GetTime()
	local function Once(channel)
		if self.sent[channel] and now - self.sent[channel] < THROTTLE then return end
		self.sent[channel] = now
		Send(channel)
	end
	if IsInGuild and IsInGuild() then Once("GUILD") end
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		Once("INSTANCE_CHAT")
	elseif IsInRaid and IsInRaid() then
		Once("RAID")
	elseif IsInGroup and IsInGroup() then
		Once("PARTY")
	end
end

function VC:Receive(prefix, text, channel, sender)
	if A.IsSecret(prefix, text, channel, sender) then return end
	if prefix ~= VC.PREFIX or type(text) ~= "string" or type(sender) ~= "string" then return end
	local v = text:match("^V1:(%d+%.%d+[%.%d]*)$")
	if not v then return end
	if Ambiguate and Ambiguate(sender, "none") == UnitName("player") then return end

	if A:VersionNewer(v, A.version) then
		if Enabled() and (not self.told or A:VersionNewer(v, self.told)) then
			self.told = v
			A:Print(A.F(L.core.version.newer, A.Hi(v), A.Hi(tostring(A.version))))
		end
	elseif A:VersionNewer(A.version, v) and channel ~= "WHISPER"
		and Enabled() and not self.answered[sender] then
		self.answered[sender] = true
		Send("WHISPER", sender)
	end
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(VC.PREFIX)
end

A:RegisterEvent(VC, "CHAT_MSG_ADDON", function(_, _, ...) VC:Receive(...) end)
A:RegisterEvent(VC, "GROUP_JOINED", function() VC:Broadcast() end)
A:RegisterEvent(VC, "PLAYER_GUILD_UPDATE", function(_, _, unit)
	if unit == nil or unit == "player" then VC:Broadcast() end
end)
-- The guild roster is often not known yet at login, so wait a little.
A:RegisterEvent(VC, "PLAYER_ENTERING_WORLD", function(_, _, isLogin, isReload)
	if isLogin or isReload then
		C_Timer.After(10, function() VC:Broadcast() end)
	end
end)
