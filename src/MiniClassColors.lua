local green = CreateColor(0, 1, 0)
local grey = CreateColor(0.5, 0.5, 0.5)
local yellow = CreateColor(1, 1, 0)
local red = CreateColor(1, 0, 0)
local reactionFriendlyStart = 5
local reactionNeutral = 4

local function Notify(msg)
	local formatted = string.format("MiniClassColors - %s", msg)
	print(formatted)
end

local function GetPlayerUnitColour(unit)
	local _, className = UnitClass(unit)
	local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]

	return colour or green
end

local function GetNpcUnitColour(unit)
	-- if we're in pvp mode and the enemy faction flagged the mob
	-- then return a grey colour
	if UnitIsTapDenied(unit) then
		return grey
	end

	local reaction = UnitReaction("player", unit)

	if not reaction then
		-- not sure why this happens sometimes
		return yellow
	end

	if reaction >= reactionFriendlyStart then
		return green
	end

	if reaction == reactionNeutral then
		return yellow
	end

	-- unfriendly/hostile/hated
	return red
end

local function GetUnitColour(unit)
	return UnitIsPlayer(unit) and GetPlayerUnitColour(unit) or GetNpcUnitColour(unit)
end

local function UpdateFrame(frame, unit)
	if frame.unit ~= unit then
		return
	end

	local colour = GetUnitColour(unit)

	frame:SetStatusBarDesaturated(true)
	frame:SetStatusBarColor(colour.r, colour.g, colour.b)
end

function Init()
	if UnitFrameHealthBar_Update then
		hooksecurefunc("UnitFrameHealthBar_Update", UpdateFrame)
	else
		Notify("Missing UnitFrameHealthBar_Update.")
	end

	if not RAID_CLASS_COLORS then
		Notify("Missing RAID_CLASS_COLORS")
	end

	local playerFrame = PlayerFrame.healthbar

	if playerFrame then
		UpdateFrame(playerFrame, "player")
	else
		Notify("Missing PlayerFrame.healthbar.")
	end
end

Init()
