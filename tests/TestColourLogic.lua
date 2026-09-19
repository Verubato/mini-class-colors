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

		-- the gate never holds an NPC bar clean, so the read-back guard still runs on every update
		local bar = ScratchBar("target")
		WowMock.State.Units.target = false
		PatchAlphaDefault(bar)

		local writes = 0
		local wrapped = bar.SetStatusBarColor
		bar.SetStatusBarColor = function(self, ...)
			writes = writes + 1
			return wrapped(self, ...)
		end

		WithGlobals({
			UnitReaction = function()
				return 1
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
			fw.eq(writes, 1, "settles the bar at the reaction colour with alpha 1")

			writes = 0
			_G.UnitFrameHealthBar_Update(bar, "target")
			fw.eq(writes, 0, "nothing changed, so the repaint is skipped")

			local r, g, b = bar:GetStatusBarColor()

			writes = 0
			-- a faded bar is a different bar on screen, whatever its channels read back as
			wrapped(bar, r, g, b, 0.5)
			_G.UnitFrameHealthBar_Update(bar, "target")
			fw.eq(writes, 1, "the same channels at a lower alpha are still repainted")
		end)
	end)

	fw.it("repaints once the stored colour drifts a whole byte, not on a smaller float wobble", function()
		harness.Load("MiniClassColors")

		-- the gate never holds an NPC bar clean, so the read-back guard still runs on every update
		local bar = ScratchBar("target")
		WowMock.State.Units.target = false
		PatchAlphaDefault(bar)

		local writes = 0
		local wrapped = bar.SetStatusBarColor
		bar.SetStatusBarColor = function(self, ...)
			writes = writes + 1
			return wrapped(self, ...)
		end

		WithGlobals({
			UnitIsTapDenied = function()
				return true
			end,
		}, function()
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
	end)

	fw.it("writes a secret class colour once, then holds the bar clean by generation", function()
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
			fw.eq(writes, 1, "a secret colour can't be compared, so the first pass writes")

			_G.UnitFrameHealthBar_Update(bar, "target")
			_G.UnitFrameHealthBar_Update(bar, "target")
			fw.eq(writes, 1, "the colour came from the class, so generation holds the bar clean")
		end)
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

	fw.it("calls C_ClassColor.GetClassColor once across ten updates, not once per health tick", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true

		local classSentinel = "__minitest_secret_class_token_3__"
		WowMock.State.Class = { "Secret", classSentinel, 1 }

		local calls = 0

		WithGlobals({
			issecretvalue = function(v)
				return v == classSentinel
			end,
			C_ClassColor = {
				GetClassColor = function()
					calls = calls + 1
					return { r = 0.3, g = 0.6, b = 0.9 }
				end,
			},
		}, function()
			for _ = 1, 10 do
				_G.UnitFrameHealthBar_Update(bar, "target")
			end
		end)

		fw.eq(calls, 1, "a clean bar's generation gate keeps the allocation to the first pass")
	end)

	fw.it("the gate returns before UnitClass runs, unlike the read-back guard it sits in front of", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")

		_G.UnitFrameHealthBar_Update(bar, "target")

		local calls = 0
		local originalUnitClass = _G.UnitClass

		WithGlobals({
			UnitClass = function(...)
				calls = calls + 1
				return originalUnitClass(...)
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		fw.eq(calls, 0, "a clean bar returns at the gate, before the colour is worked out at all")
	end)

	fw.it("a rebind to a different unit still repaints, even within the same generation", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")

		_G.UnitFrameHealthBar_Update(bar, "target")

		-- UnitFrame_SetUnit rebinds .unit and runs an update with no identity event in between
		bar.unit = "focus"
		WowMock.State.Units.focus = false

		WithGlobals({
			UnitReaction = function()
				return 1
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "focus")
		end)

		local r, g, b = bar:GetStatusBarColor()

		fw.eq(r, 1, "red red channel")
		fw.eq(g, 0, "red green channel")
		fw.eq(b, 0, "red blue channel")
	end)

	fw.it("a foreign write to the bar self-heals back to the class colour", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")

		_G.UnitFrameHealthBar_Update(bar, "target")

		bar:SetStatusBarColor(0, 1, 0, 1)

		local r, g, b = bar:GetStatusBarColor()
		local expected = RAID_CLASS_COLORS.WARRIOR

		fw.eq(r, expected.r, "self-heal red channel")
		fw.eq(g, expected.g, "self-heal green channel")
		fw.eq(b, expected.b, "self-heal blue channel")
	end)

	fw.it("the recursion guard stops a secret bar's self-heal from looping forever", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true

		local classSentinel = "__minitest_secret_class_token_4__"
		local colourSentinel = "__minitest_secret_colour_component_2__"
		WowMock.State.Class = { "Secret", classSentinel, 1 }

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

			local writes = 0
			local wrapped = bar.SetStatusBarColor
			bar.SetStatusBarColor = function(self, ...)
				writes = writes + 1
				-- A secret colour always takes the write branch, so a missing applying
				-- guard would recurse without ever unwinding.
				if writes > 5 then
					error("runaway recolour loop")
				end
				return wrapped(self, ...)
			end

			bar:SetStatusBarColor(0, 1, 0, 1)

			fw.eq(writes, 2, "the foreign write and the one correction it triggers, nothing beyond that")
		end)
	end)

	fw.it("an NPC bar is never gated, so a reaction change repaints without any event", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = false

		WithGlobals({
			UnitReaction = function()
				return 5
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		WithGlobals({
			UnitReaction = function()
				return 1
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		local r, g, b = bar:GetStatusBarColor()

		fw.eq(r, 1, "red red channel")
		fw.eq(g, 0, "red green channel")
		fw.eq(b, 0, "red blue channel")
	end)

	fw.it("a class name that isn't a string leaves the bar dirty, so a late class still lands", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.State.Class = { "Numeric", 42, 1 }
		PatchAlphaDefault(bar)

		_G.UnitFrameHealthBar_Update(bar, "target")

		local r0, g0, b0 = bar:GetStatusBarColor()

		fw.eq(r0, 0, "green red channel while the class name is unusable")
		fw.eq(g0, 1, "green green channel while the class name is unusable")
		fw.eq(b0, 0, "green blue channel while the class name is unusable")

		WowMock.SetPlayerClass("WARRIOR")
		_G.UnitFrameHealthBar_Update(bar, "target")

		local r, g, b = bar:GetStatusBarColor()
		local expected = RAID_CLASS_COLORS.WARRIOR

		fw.eq(r, expected.r, "the real class colour lands with no event fired")
		fw.eq(g, expected.g, "the real class colour lands with no event fired")
		fw.eq(b, expected.b, "the real class colour lands with no event fired")
	end)

	fw.it("a secret class the colour api cannot resolve leaves the bar dirty", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		PatchAlphaDefault(bar)

		local classSentinel = "__minitest_secret_class_token_5__"
		WowMock.State.Class = { "Secret", classSentinel, 1 }

		local resolved

		WithGlobals({
			issecretvalue = function(v)
				return v == classSentinel
			end,
			C_ClassColor = {
				GetClassColor = function()
					return resolved
				end,
			},
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")

			local r0, g0, b0 = bar:GetStatusBarColor()

			fw.eq(r0, 0, "green red channel while the lookup comes back empty")
			fw.eq(g0, 1, "green green channel while the lookup comes back empty")
			fw.eq(b0, 0, "green blue channel while the lookup comes back empty")

			resolved = { r = 0.25, g = 0.78, b = 0.92 }
			_G.UnitFrameHealthBar_Update(bar, "target")

			local r, g, b = bar:GetStatusBarColor()

			fw.eq(r, 0.25, "the class colour lands once the lookup answers")
			fw.eq(g, 0.78, "the class colour lands once the lookup answers")
			fw.eq(b, 0.92, "the class colour lands once the lookup answers")
		end)
	end)
end)

fw.describe("MiniClassColors - identity events", function()
	local function ExpectClass(bar, token, message)
		local r, g, b = bar:GetStatusBarColor()
		local expected = RAID_CLASS_COLORS[token]

		fw.eq(r, expected.r, message .. ", red channel")
		fw.eq(g, expected.g, message .. ", green channel")
		fw.eq(b, expected.b, message .. ", blue channel")
	end

	---Paints the bar for a warrior, swaps the unit behind it for a mage, and runs the update the
	---client's own handler would.
	local function StaleBar()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")
		PatchAlphaDefault(bar)

		_G.UnitFrameHealthBar_Update(bar, "target")

		WowMock.SetPlayerClass("MAGE")
		_G.UnitFrameHealthBar_Update(bar, "target")

		ExpectClass(bar, "WARRIOR", "the gate holds the bar on the old unit's colour")

		return bar
	end

	fw.it("PLAYER_ENTERING_WORLD repaints a stale bar", function()
		local bar = StaleBar()

		WowMock.FireEvent("PLAYER_ENTERING_WORLD")

		ExpectClass(bar, "MAGE", "login, reload and zoning all follow this event")
	end)

	fw.it("PLAYER_TARGET_CHANGED repaints a stale bar", function()
		local bar = StaleBar()

		WowMock.FireEvent("PLAYER_TARGET_CHANGED")

		ExpectClass(bar, "MAGE", "a new target brings its target's target with it")
	end)

	fw.it("PLAYER_FOCUS_CHANGED repaints a stale bar", function()
		local bar = StaleBar()

		WowMock.FireEvent("PLAYER_FOCUS_CHANGED")

		ExpectClass(bar, "MAGE", "a new focus brings its target's target with it")
	end)

	fw.it("GROUP_ROSTER_UPDATE repaints a stale bar", function()
		local bar = StaleBar()

		WowMock.FireEvent("GROUP_ROSTER_UPDATE")

		ExpectClass(bar, "MAGE", "a party frame's unit becomes a different player on this event")
	end)

	fw.it("UNIT_ENTERED_VEHICLE repaints a stale bar", function()
		local bar = StaleBar()

		WowMock.FireEvent("UNIT_ENTERED_VEHICLE", "player")

		ExpectClass(bar, "MAGE", "the player bar's unit becomes the vehicle on this event")
	end)

	fw.it("UNIT_ENTERED_VEHICLE for a party member still repaints, since arg1 isn't filtered", function()
		local bar = StaleBar()

		WowMock.FireEvent("UNIT_ENTERED_VEHICLE", "party1")

		ExpectClass(bar, "MAGE", "PartyMemberFrameMixin gates on its own unit, not on the player's")
	end)

	fw.it("UNIT_EXITED_VEHICLE repaints a stale bar", function()
		local bar = StaleBar()

		WowMock.FireEvent("UNIT_EXITED_VEHICLE", "player")

		ExpectClass(bar, "MAGE", "the player bar's unit comes back on this event")
	end)

	fw.it("UNIT_TARGET for the player's own target repaints a stale bar", function()
		local bar = StaleBar()

		WowMock.FireEvent("UNIT_TARGET", "target")

		ExpectClass(bar, "MAGE", "a fixed target switching its own target is what this tracks")
	end)

	fw.it("UNIT_TARGET for an unrelated raid member leaves the bar alone", function()
		local bar = StaleBar()

		WowMock.FireEvent("UNIT_TARGET", "raid7")

		ExpectClass(bar, "WARRIOR", "the filter drops every unit but the player's and focus's target")
	end)

	fw.it("UNIT_PET for the player repaints a stale bar", function()
		local bar = StaleBar()

		WowMock.FireEvent("UNIT_PET", "player")

		ExpectClass(bar, "MAGE", "the pet bar's own unit swap is covered by this event")
	end)

	fw.it("UNIT_PET for a party member leaves the bar alone", function()
		local bar = StaleBar()

		WowMock.FireEvent("UNIT_PET", "party3")

		ExpectClass(bar, "WARRIOR", "another player's pet takes a reaction colour, which is never gated")
	end)

	fw.it("the sweep repaints each bar from its own unit, not one shared token", function()
		harness.Load("MiniClassColors")

		local playerBar = ScratchBar("target")
		WowMock.State.Units.target = true
		WowMock.SetPlayerClass("WARRIOR")

		local npcBar = ScratchBar("focus")
		WowMock.State.Units.focus = false

		WithGlobals({
			UnitReaction = function()
				return 1
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(playerBar, "target")
			_G.UnitFrameHealthBar_Update(npcBar, "focus")

			WowMock.SetPlayerClass("MAGE")
			WowMock.FireEvent("PLAYER_TARGET_CHANGED")

			ExpectClass(playerBar, "MAGE", "the player bar follows its own unit's class")

			local r, g, b = npcBar:GetStatusBarColor()

			fw.eq(r, 1, "the npc bar keeps its own unit's reaction colour, red channel")
			fw.eq(g, 0, "the npc bar keeps its own unit's reaction colour, green channel")
			fw.eq(b, 0, "the npc bar keeps its own unit's reaction colour, blue channel")
		end)
	end)

	fw.it("a bar is only ever registered once, however many times it repaints", function()
		harness.Load("MiniClassColors")

		local bar = ScratchBar("target")
		WowMock.State.Units.target = false

		WithGlobals({
			UnitReaction = function()
				return 5
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		WithGlobals({
			UnitReaction = function()
				return 1
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		WithGlobals({
			UnitReaction = function()
				return 5
			end,
		}, function()
			_G.UnitFrameHealthBar_Update(bar, "target")
		end)

		local calls = 0

		WithGlobals({
			UnitReaction = function()
				calls = calls + 1
				return 5
			end,
		}, function()
			WowMock.FireEvent("PLAYER_TARGET_CHANGED")
		end)

		fw.eq(calls, 1, "three distinct writes still only registered the bar once, so the sweep visits it once")
	end)
end)
