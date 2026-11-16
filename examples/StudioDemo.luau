-- Pass the App handle returned by the plugin's App.start(plugin).
return function(app)
	app:LoadPreset(1)
	app:PinBaseline()
	app:SetValue("upgrades.1.cost.growth", 1.13)
	local result = app:Run()
	app.Widget.Enabled = true
	if result then app.Chart:SetCursor(result.goalTime * 0.65) end
	return result
end
