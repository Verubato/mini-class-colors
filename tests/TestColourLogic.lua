-- GetUnitColour, ColourHealthBar and SameChannel are all file-local, so every case here is
-- driven through the addon's registered hooks: hooksecurefunc("UnitFrameHealthBar_Update", ...)
-- reaches any bar carrying a .unit field, not only PlayerFrame/PetFrame, which is what lets a
-- scratch StatusBar stand in for target, focus, or a mob frame without the addon ever seeing it.
--
-- The mock's issecretvalue always answers false (see build/Lua/WowMock.lua), so the secret
-- branches below swap it out for one that recognises a chosen sentinel string as the only
-- secret value, exactly where a real secret class tag or colour would arrive. A string sentinel
-- is used rather than a table one: the addon's own nil-guard calls type() on the class name
-- first, and a real secret string still reports type() == "string".

local fw = require("TestFramework")
local harness = require("AddonHarness")
local WowMock = require("WowMock")

---Overrides one or more globals for the duration of fn, restoring them even if fn raises, so
---one failing assertion can't leave a later test running against a patched global.
---@param overrides table<string, any>
---@param fn fun()
local function WithGlobals(overrides, fn)
	local reals = {}

	for name, value in pairs(overrides) do
		reals[name] = _G[name]
		_G[name] = value
	end

	local ok, err = pcall(fn)

	for name, value in pairs(reals) do
		_G[name] = value
	end

	if not ok then
		error(err, 0)
	end
end

---A bare StatusBar carrying only the .unit field the addon's global hooks read. It was never
---hooksecurefunc'd by HookFrameHealthBar, unlike PlayerFrame/PetFrame, so its SetStatusBarColor
---can be swapped out freely without unwinding a recursion guard.
---@param unit string
---@return table
local function ScratchBar(unit)
	local bar = CreateFrame("StatusBar", nil, UIParent)
	bar.unit = unit
	return bar
end

---SetStatusBarColor(r, g, b) with no fourth argument stores a as nil in this mock rather than
---defaulting it to 1 the way the real client's StatusBar widget does, which would make the
---hot-path's `a == 1` check fail forever. Patched per scratch bar rather than in build/.
---@param bar table
local function PatchAlphaDefault(bar)
	local original = bar.SetStatusBarColor

	bar.SetStatusBarColor = function(self, r, g, b, a)
		return original(self, r, g, b, a == nil and 1 or a)
	end
end

fw.describe("MiniClassColors - GetPlayerUnitColour", function()
	-- setup runs after harness.Load's own WowMock.Install, which is the only way a chosen
	-- State.Class or State.Units survives instead of being overwritten by the fresh install.
	local function ColourFor(setup, overrides)
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true

		if setup then
			setup()
		end

		local writtenR, writtenG, writtenB

		bar.SetStatusBarColor = function(_, r, g, b)
			writtenR, writtenG, writtenB = r, g, b
		end

		WithGlobals(overrides or {}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		return writtenR, writtenG, writtenB
	end

	fw.it("maps a known class to its RAID_CLASS_COLORS entry", function()
		local r, g, b = ColourFor(function()
			WowMock.SetPlayerClass("WARRIOR")
		end)
		local expected = RAID_CLASS_COLORS.WARRIOR

		fw.eq(r, expected.r, "class red channel")
		fw.eq(g, expected.g, "class green channel")
		fw.eq(b, expected.b, "class blue channel")
	end)

	fw.it("falls back to green when the class name isn't a string", function()
		-- 42 is planted as a live RAID_CLASS_COLORS key, so a type() guard that failed to
		-- fire would find a real entry there instead of falling through to green.
		local r, g, b = ColourFor(function()
			WowMock.State.Class = { "Numeric", 42, 1 }
			RAID_CLASS_COLORS[42] = { r = 0.9, g = 0.1, b = 0.1 }
		end)

		fw.eq(r, 0, "green red channel")
		fw.eq(g, 1, "green green channel")
		fw.eq(b, 0, "green blue channel")
	end)

	fw.it("routes a secret class tag through C_ClassColor rather than the RAID_CLASS_COLORS table", function()
		local sentinel = "__minitest_secret_class_token__"

		local r, g, b = ColourFor(function()
			WowMock.State.Class = { "Secret", sentinel, 1 }
		end, {
			issecretvalue = function(v)
				return v == sentinel
			end,
			C_ClassColor = {
				GetClassColor = function()
					return { r = 0.3, g = 0.6, b = 0.9 }
				end,
			},
		})

		fw.eq(r, 0.3, "used C_ClassColor's red channel")
		fw.eq(g, 0.6, "used C_ClassColor's green channel")
		fw.eq(b, 0.9, "used C_ClassColor's blue channel")
	end)
end)

fw.describe("MiniClassColors - GetNpcUnitColour", function()
	local function ColourFor(overrides)
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = false

		local writtenR, writtenG, writtenB

		bar.SetStatusBarColor = function(_, r, g, b)
			writtenR, writtenG, writtenB = r, g, b
		end

		WithGlobals(overrides or {}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		return writtenR, writtenG, writtenB
	end

	fw.it("colours a tap-denied mob grey, regardless of reaction", function()
		local r, g, b = ColourFor({
			UnitIsTapDenied = function()
				return true
			end,
		})

		fw.eq(r, 0.5, "grey red channel")
		fw.eq(g, 0.5, "grey green channel")
		fw.eq(b, 0.5, "grey blue channel")
	end)

	fw.it("colours a friendly reaction green", function()
		local r, g, b = ColourFor({
			UnitReaction = function()
				return 5
			end,
		})

		fw.eq(r, 0, "green red channel")
		fw.eq(g, 1, "green green channel")
		fw.eq(b, 0, "green blue channel")
	end)

	fw.it("colours a neutral reaction yellow", function()
		local r, g, b = ColourFor({
			UnitReaction = function()
				return 4
			end,
		})

		fw.eq(r, 1, "yellow red channel")
		fw.eq(g, 1, "yellow green channel")
		fw.eq(b, 0, "yellow blue channel")
	end)

	fw.it("colours an unfriendly/hostile reaction red", function()
		local r, g, b = ColourFor({
			UnitReaction = function()
				return 1
			end,
		})

		fw.eq(r, 1, "red red channel")
		fw.eq(g, 0, "red green channel")
		fw.eq(b, 0, "red blue channel")
	end)

	fw.it("colours an unreadable reaction yellow", function()
		local r, g, b = ColourFor({
			UnitReaction = function()
				return nil
			end,
		})

		fw.eq(r, 1, "falls back to yellow's red channel")
		fw.eq(g, 1, "falls back to yellow's green channel")
		fw.eq(b, 0, "falls back to yellow's blue channel")
	end)
end)

fw.describe("MiniClassColors - ColourHealthBar's hot path", function()
	fw.it("always writes on the first paint", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")

		local writes = 0
		bar.SetStatusBarColor = function()
			writes = writes + 1
		end

		_G.UnitFrameHealthBar_Update(bar, "target")

		fw.eq(writes, 1, "a bar this addon has never painted always gets written")
	end)

	fw.it("skips an identical repaint once the bar's alpha reads back as 1", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")
		PatchAlphaDefault(bar)

		local writes = 0
		local wrapped = bar.SetStatusBarColor
		bar.SetStatusBarColor = function(self, ...)
			writes = writes + 1
			return wrapped(self, ...)
		end

		_G.UnitFrameHealthBar_Update(bar, "target")
		fw.eq(writes, 1, "settles the bar at the class colour with alpha 1")

		writes = 0
		_G.UnitFrameHealthBar_Update(bar, "target")
		fw.eq(writes, 0, "nothing changed, so the repaint is skipped")
	end)

	fw.it("repaints once the stored colour drifts a whole byte, not on a smaller float wobble", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")
		PatchAlphaDefault(bar)

		local writes = 0
		local wrapped = bar.SetStatusBarColor
		bar.SetStatusBarColor = function(self, ...)
			writes = writes + 1
			return wrapped(self, ...)
		end

		_G.UnitFrameHealthBar_Update(bar, "target")
		local r0, g0, b0 = bar:GetStatusBarColor()
		local byte0 = math.floor(r0 * 255 + 0.5)

		writes = 0
		-- The same byte's own representative value, standing in for whatever float rounding
		-- the real client's colour pipeline might introduce without changing the 8-bit result.
		wrapped(bar, byte0 / 255, g0, b0, 1)
		_G.UnitFrameHealthBar_Update(bar, "target")
		fw.eq(writes, 0, "still the same byte, no rewrite")

		writes = 0
		-- One whole 8-bit step away: a genuinely different channel.
		wrapped(bar, (byte0 - 1) / 255, g0, b0, 1)
		_G.UnitFrameHealthBar_Update(bar, "target")
		fw.eq(writes, 1, "an adjacent byte is treated as a real change")
	end)

	fw.it("always writes when the resolved colour itself reads secret, since it can never be compared", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true

		local classSentinel = "__minitest_secret_class_token_2__"
		local colourSentinel = "__minitest_secret_colour_component__"

		WowMock.State.Class = { "Secret", classSentinel, 1 }

		local writes = 0
		bar.SetStatusBarColor = function()
			writes = writes + 1
		end

		WithGlobals({
			issecretvalue = function(v)
				return v == classSentinel or v == colourSentinel
			end,
			C_ClassColor = {
				GetClassColor = function()
					return { r = colourSentinel, g = colourSentinel, b = colourSentinel }
				end,
			},
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
			_G.UnitFrameHealthBar_Update(bar, "target")
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		fw.eq(writes, 3, "a secret colour can't be compared, so every check repaints")
	end)

	fw.it("also always writes when the bar's own current colour reads secret, not only the freshly computed one", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")

		local sentinel = "__minitest_secret_bar_colour__"

		-- Stands in for something else having written a secret value straight onto the bar,
		-- ahead of anything this addon does: the guard has to hold on the read side too.
		bar.GetStatusBarColor = function()
			return sentinel, sentinel, sentinel, 1
		end

		bar.MiniClassColorsPainted = true

		local writes = 0
		bar.SetStatusBarColor = function()
			writes = writes + 1
		end

		WithGlobals({
			issecretvalue = function(v)
				return v == sentinel
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		fw.eq(writes, 1, "the bar's own unreadable colour can't be compared either, so it repaints")
	end)
end)
