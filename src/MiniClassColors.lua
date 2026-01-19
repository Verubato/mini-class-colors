local green = CreateColor(0, 1, 0)
local grey = CreateColor(0.5, 0.5, 0.5)
local yellow = CreateColor(1, 1, 0)
local red = CreateColor(1, 0, 0)
local reactionFriendlyStart = 5
local reactionNeutral = 4

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

local function ColourHealthBar(hb, unit)
	if not hb or not unit then
		return
	end

	local colour = GetUnitColour(unit)

	hb:SetStatusBarDesaturated(true)
	hb:SetStatusBarColor(colour.r, colour.g, colour.b)
end

local function OnUnitFrameHealthBarUpdate(statusBar, unit)
	if not statusBar or not unit then
		return
	end

	if statusBar.unit ~= unit then
		return
	end

	ColourHealthBar(statusBar, unit)
end

local function OnHealthBarValueChanged(healthBar)
	if not healthBar or not healthBar.unit then
		return
	end

	ColourHealthBar(healthBar, healthBar.unit)
end

function Init()
	if UnitFrameHealthBar_Update then
		-- retail hook
		hooksecurefunc("UnitFrameHealthBar_Update", OnUnitFrameHealthBarUpdate)
	end

	if UnitFrameHealthBar_OnValueChanged then
		-- classic/tbc hook
		hooksecurefunc("UnitFrameHealthBar_OnValueChanged", OnHealthBarValueChanged)
	end

	if PlayerFrame and PlayerFrame.healthbar then
		-- initial colour
		ColourHealthBar(PlayerFrame.healthbar, "player")

		-- the player frame on classic and tbc doesn't go through the other hooks
		hooksecurefunc(PlayerFrame.healthbar, "SetStatusBarColor", function(self)
			if self.MiniClassColorsApplying then
				return
			end

			self.MiniClassColorsApplying = true
			ColourHealthBar(self, "player")
			self.MiniClassColorsApplying = false
		end)
	end
end

Init()
