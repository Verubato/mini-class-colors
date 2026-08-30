-- Loads the whole addon into a mocked client and drives it through login.
-- The shared body lives in build/Lua/SmokeTest.lua.

local fw = require("TestFramework")
local smoke = require("SmokeTest")
local WowMock = require("WowMock")

---The header's subtitle is built by the framework and never handed back to the addon, so a
---test finds it the way a player reads it, by its words.
---@param text string
---@return boolean
local function HasText(text)
	for _, frame in ipairs(WowMock.Frames) do
		if frame.GetText and frame:GetText() == text then
			return true
		end

		for _, region in ipairs({ frame:GetRegions() }) do
			if region.GetText and region:GetText() == text then
				return true
			end
		end
	end

	return false
end

---The section rule is built by the framework and never handed back to the addon, so a test
---finds it the way a player sees it, by its label.
---@param text string
---@return boolean
local function HasDivider(text)
	for _, frame in ipairs(WowMock.Frames) do
		if frame.Label and frame.Label.GetText and frame.Label:GetText() == text then
			return true
		end
	end

	return false
end

smoke.Run("MiniClassColors", {
	extra = function(context)
		fw.eq(context.Addon.Framework.CustomStyling, true, "custom styling on")
		fw.eq(context.Addon.Framework.CustomStylingOverrides.Button, false, "stock buttons")
		fw.truthy(HasText("Applies class colouring to the player, target, focus, and target of target frames."), "the subtitle under the panel title")
		fw.truthy(HasText("This addon has no settings, it simply works out of the box."), "the second subtitle line saying there is nothing to configure")
		-- The panel has no controls, so it carries no section rule either.
		fw.falsy(HasDivider("SETTINGS"), "no settings section rule under the header")

		-- MiniAuras has owned /mcc since it was called MiniCC, so claiming it here would
		-- take the command away from whichever addon loaded second.
		for i = 1, 4 do
			fw.truthy(_G["SLASH_MINICLASSCOLORS" .. i] ~= "/mcc", "alias " .. i .. " is not /mcc")
		end
	end,
})
