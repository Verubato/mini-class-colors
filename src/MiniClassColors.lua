local green = CreateColor(0, 1, 0)
local grey = CreateColor(0.5, 0.5, 0.5)
local yellow = CreateColor(1, 1, 0)
local red = CreateColor(1, 0, 0)
local reactionFriendlyStart = 5
local reactionNeutral = 4

local generation = 1
local listener
local paintedBars = {}
local identityEvents = {
	"PLAYER_ENTERING_WORLD",
	"PLAYER_TARGET_CHANGED",
	"PLAYER_FOCUS_CHANGED",
	"GROUP_ROSTER_UPDATE",
	"UNIT_TARGET",
	"UNIT_PET",
	"UNIT_ENTERED_VEHICLE",
	"UNIT_EXITED_VEHICLE",
}
local EnsureColourHook

local function IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

---Whether two colour channels land on the same 8-bit value. The widget keeps its colour as a
---float and the getter can quantise on the way back out, so neither an exact compare nor a
---fixed epsilon is dependable. The screen only shows 8 bits either way.
local function SameChannel(a, b)
	return math.floor(a * 255 + 0.5) == math.floor(b * 255 + 0.5)
end

local function GetPlayerUnitColour(unit)
	local _, className = UnitClass(unit)

	-- type() is one of the few things allowed on a secret, so it stands in for
	-- a plain nil check
	if type(className) ~= "string" then
		return green, false
	end

	-- retail hands back a secret class name for units we're not allowed to
	-- identify, and a secret can't index a lua table. C_ClassColor takes one,
	-- but it ignores any addon that recolours RAID_CLASS_COLORS, so keep the
	-- table for every other unit.
	if issecretvalue and issecretvalue(className) then
		local colour = C_ClassColor.GetClassColor(className)

		if colour then
			return colour, true
		end

		return green, false
	end

	local colour = RAID_CLASS_COLORS and RAID_CLASS_COLORS[className]

	if colour then
		return colour, true
	end

	return green, false
end

local function GetNpcUnitColour(unit)
	-- if we're in pvp mode and the enemy faction flagged the mob
	-- then return a grey colour
	if UnitIsTapDenied(unit) then
		return grey, false
	end

	local reaction = UnitReaction("player", unit)

	if not reaction then
		-- not sure why this happens sometimes
		return yellow, false
	end

	if reaction >= reactionFriendlyStart then
		return green, false
	end

	if reaction == reactionNeutral then
		return yellow, false
	end

	-- unfriendly/hostile/hated
	return red, false
end

local function GetUnitColour(unit)
	if UnitIsPlayer(unit) or unit == "pet" then
		return GetPlayerUnitColour(unit == "pet" and "player" or unit)
	end
	return GetNpcUnitColour(unit)
end

local function ColourHealthBar(hb, unit)
	if not hb or not unit then
		return
	end

	-- a reaction colour can turn without an event, so only a class colour is held between them
	if hb.MiniClassColorsGeneration == generation and hb.MiniClassColorsGenerationUnit == unit then
		return
	end

	local colour, fromClass = GetUnitColour(unit)

	-- Read back off the bar rather than remembered, so a foreign repaint is still corrected.
	-- Arithmetic on a secret errors.
	if hb.MiniClassColorsPainted and not IsSecret(colour.r) then
		local r, g, b, a = hb:GetStatusBarColor()

		if
			r
			and not IsSecret(r)
			and a == 1
			and SameChannel(r, colour.r)
			and SameChannel(g, colour.g)
			and SameChannel(b, colour.b)
		then
			hb.MiniClassColorsGeneration = fromClass and generation or nil
			hb.MiniClassColorsGenerationUnit = fromClass and unit or nil
			return
		end
	end

	-- Re-asserted on every write rather than once per bar: a texture swap takes desaturation
	-- with it, and writes are rare now.
	hb.MiniClassColorsApplying = true
	hb:SetStatusBarDesaturated(true)
	hb:SetStatusBarColor(colour.r, colour.g, colour.b)
	hb.MiniClassColorsApplying = false
	hb.MiniClassColorsPainted = true
	hb.MiniClassColorsGeneration = fromClass and generation or nil
	hb.MiniClassColorsGenerationUnit = fromClass and unit or nil
	EnsureColourHook(hb)
end

EnsureColourHook = function(hb)
	if hb.MiniClassColorsHooked then
		return
	end

	hb.MiniClassColorsHooked = true

	-- blizzard's unit frames are permanent and around twenty, so a plain array is bounded
	paintedBars[#paintedBars + 1] = hb

	hooksecurefunc(hb, "SetStatusBarColor", function(self)
		if self.MiniClassColorsApplying then
			return
		end

		self.MiniClassColorsGeneration = nil
		self.MiniClassColorsGenerationUnit = nil
		ColourHealthBar(self, self.unit)
	end)
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

local function HookFrameHealthBar(frame, unit)
	if not frame or not frame.healthbar then
		return
	end

	EnsureColourHook(frame.healthbar)
	ColourHealthBar(frame.healthbar, unit)
end

local function OnIdentityEvent(_, event, arg1)
	-- in a raid this fires for every member, and none of those move a bar here
	if event == "UNIT_TARGET" and arg1 ~= "target" and arg1 ~= "focus" then
		return
	end

	-- likewise every group member's pet, when only the player's own pet bar takes a class colour
	if event == "UNIT_PET" and arg1 ~= "player" then
		return
	end

	generation = generation + 1

	-- blizzard registered these events before us and has already run its update, so the bar
	-- only repaints if this does it
	for _, hb in ipairs(paintedBars) do
		ColourHealthBar(hb, hb.unit)
	end
end

local function Init()
	if UnitFrameHealthBar_Update then
		-- retail hook
		hooksecurefunc("UnitFrameHealthBar_Update", OnUnitFrameHealthBarUpdate)
	end

	if UnitFrameHealthBar_OnValueChanged then
		-- classic/tbc hook
		hooksecurefunc("UnitFrameHealthBar_OnValueChanged", OnHealthBarValueChanged)
	end

	HookFrameHealthBar(PlayerFrame, "player")
	HookFrameHealthBar(PetFrame, "pet")

	listener = CreateFrame("Frame")
	listener:SetScript("OnEvent", OnIdentityEvent)

	for _, event in ipairs(identityEvents) do
		listener:RegisterEvent(event)
	end
end

Init()
