local addonName, addon = ...
---@type MiniFramework
local mini = addon.Framework

mini:WaitForAddonLoad(function()
	-- A styled button clashes with the stock Blizzard art around it in the settings screen.
	mini:SetCustomStyling(true, { Button = false })

	local panel = CreateFrame("Frame")
	panel.name = addonName

	local category = mini:AddCategory(panel)

	if not category then
		return
	end

	-- A section rule with no settings under it reads as a page that failed to load.
	mini:PanelHeader({
		Parent = panel,
		Lines = {
			"Applies class colouring to the player, target, focus, and target of target frames.",
			"This addon has no settings, it simply works out of the box.",
		},
	})

	mini:RegisterSlashCommand(category, panel, {
		"/miniclasscolors",
		"/miniclasscolours",
		"/mcolors",
	})
end)
