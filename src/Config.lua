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
		Description = "Applies class colouring to the target, focus, and target of target frames.",
	})

	mini:RegisterSlashCommand(category, panel, {
		"/miniclasscolors",
		"/miniclasscolours",
		"/mcolors",
	})
end)
