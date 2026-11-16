--!strict
local Selection = game:GetService("Selection")
local HttpService = game:GetService("HttpService")
local History = game:GetService("ChangeHistoryService")
local B = require(script.Parent.BalanceLab)
local Theme = require(script.Parent.Theme)
local UI = require(script.Parent.UI)
local Chart = require(script.Parent.Chart)
local App = {}

local function json(value: any, depth: number?): string
	local level = depth or 0
	if type(value) ~= "table" then return HttpService:JSONEncode(value) end
	local array = #value > 0
	local keys = {}
	for key in value do table.insert(keys, key) end
	table.sort(keys)
	if #keys == 0 then return "[]" end
	local lines = { if array then "[" else "{" }
	for i, key in keys do
		local prefix = if array then "" else HttpService:JSONEncode(key) .. ": "
		table.insert(lines, string.rep("  ", level + 1) .. prefix .. json(value[key], level + 1) .. (if i < #keys then "," else ""))
	end
	table.insert(lines, string.rep("  ", level) .. (if array then "]" else "}"))
	return table.concat(lines, "\n")
end

function App.start(plugin: Plugin)
	local colors = Theme.colors()
	local widget = plugin:CreateDockWidgetPluginGuiAsync("BalanceLabStudio.v0.1", DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 1060, 780, 760, 500))
	widget.Title = "BalanceLab"
	local toolbar = plugin:CreateToolbar("BalanceLab")
	local toggle = toolbar:CreateButton("BalanceLabPanel", "Model and compare progression", "", "BalanceLab")
	toggle.ClickableWhenViewportHidden = true
	local state: any = { alive = true, busy = false, version = 0, draft = B.Config.draft(B.Config.assert(B.presets()[1])), result = nil, baseline = nil, preset = 1, dirty = false }
	local app: any = { Widget = widget, State = state, Controls = {} }
	local connections = {}
	local jobs: { [thread]: boolean } = {}
	local importClone: ModuleScript? = nil
	local function spawn(callback: () -> ())
		local thread: thread
		thread = task.defer(function()
			local ok, err = pcall(function() if state.alive then callback() end end)
			jobs[thread] = nil
			if not ok then warn("BalanceLab: " .. tostring(err)) end
		end)
		jobs[thread] = true
	end
	local root = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = colors.background, BorderSizePixel = 0 }, widget)
	UI.padding(root, 16)
	local heading = UI.label(root, "BalanceLab", 28, 24, colors.text, true)
	heading.Size = UDim2.new(0.5, 0, 0, 28)
	local caption = UI.label(root, "PROGRESSION / MODELED, NOT LIVE ANALYTICS", 28, 12, colors.muted)
	caption.Size, caption.Position = UDim2.new(0.5, 0, 0, 28), UDim2.fromScale(0.5, 0)
	caption.TextXAlignment = Enum.TextXAlignment.Right
	local actions = UI.new("Frame", { Position = UDim2.new(0, 0, 0, 40), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, root)
	UI.list(actions, 8, true)
	local body = UI.new("Frame", { Position = UDim2.new(0, 0, 0, 90), Size = UDim2.new(1, 0, 1, -124), BackgroundTransparency = 1 }, root)
	local editor = UI.scroll(body, colors)
	editor.Name, editor.Size = "Parameters", UDim2.new(0.32, -10, 1, 0)
	UI.new("UIPadding", { PaddingRight = UDim.new(0, 10) }, editor)
	local results = UI.scroll(body, colors)
	results.Name, results.Position, results.Size = "Results", UDim2.new(0.32, 10, 0, 0), UDim2.new(0.68, -10, 1, 0)
	UI.new("UIPadding", { PaddingRight = UDim.new(0, 8) }, results)
	UI.list(results, 8)
	local status = UI.label(root, "Choose a preset, edit an assumption, then run the comparison.", 30, 13, colors.muted)
	status.AnchorPoint, status.Position = Vector2.new(0, 1), UDim2.fromScale(0, 1)
	local function message(text: string, errorState: boolean?)
		if not state.alive then return end
		status.Text = text
		status.TextColor3 = if errorState then colors.error else colors.muted
	end
	local summary = UI.label(results, "Modeling progression…", 34, 25, colors.text, true)
	local comparison = UI.label(results, "Your first run becomes the baseline.", 36, 14, colors.muted)
	local chartActions = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, results)
	UI.list(chartActions, 8, true)
	local chart = Chart.new(results, colors)
	app.Chart = chart
	local legend = UI.label(results, "BEFORE  ·  blue-gray        AFTER  ·  green", 20, 12, colors.muted)
	legend.Name = "Legend"
	local report = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, results)
	local runButton: TextButton
	local metricButton: TextButton
	local scaleButton: TextButton
	local presetButton: TextButton
	local rebuild: () -> ()

	local function render()
		local result = state.result
		if not result then return end
		local time = result.goalTime
		local kind = if result.loot then "Median target" else "Time to milestone"
		summary.Text = kind .. "   " .. B.Format.duration(time)
		comparison.Text = if state.baseline then B.compare(state.baseline, result).text else "Pin this run to compare your next edit."
		if time then comparison.Text ..= "   ·   ~" .. B.Format.day(time, result.config.player.sessionMinutes, result.config.player.sessionsPerDay) end
		chart.current, chart.before = result, state.baseline
		if result.loot then chart.metric = "Chance" elseif chart.metric == "Chance" then chart.metric = "Balance" end
		metricButton.Text = "Chart: " .. chart.metric
		chart:Draw()
		report:ClearAllChildren()
		UI.list(report, 6)
		UI.label(report, if result.loot then "FIRST TARGET DROP" else "CURRENCY MILESTONES", 24, 13, colors.muted, true)
		local function row(left: string, right: string)
			local line = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 25), BackgroundTransparency = 1 }, report)
			local a = UI.label(line, left, 25, 14, colors.text)
			a.Size = UDim2.fromScale(0.52, 1)
			local b = UI.label(line, right, 25, 14, colors.text)
			b.Size, b.Position, b.TextXAlignment = UDim2.fromScale(0.48, 1), UDim2.fromScale(0.5, 0), Enum.TextXAlignment.Right
		end
		if result.loot then
			for _, q in result.loot.quantiles do
				row(B.Format.percent(q.q) .. " own target · " .. B.Format.integer(q.rolls) .. " rolls", B.Format.duration(q.time))
			end
			UI.label(report, "Per roll: " .. B.Format.odds(result.loot.chance) .. "   ·   " .. (if result.loot.pity > 0 then "guaranteed by roll " .. tostring(result.loot.pity) else "no hard pity"), 28, 13, colors.muted)
		else
			for _, fraction in { 0.1, 0.5, 1 } do
				local amount = result.config.goal.amount * fraction
				row(B.Format.number(amount) .. " " .. result.config.currency .. " held", B.Format.duration(B.Simulate.timeAtBalance(result, amount)))
			end
		end
		UI.label(report, "LONGEST WAIT TO THE GOAL", 28, 13, colors.muted, true)
		local gap = result.longestGap
		UI.label(report, if gap then B.Format.duration(gap.duration) .. " before " .. gap.label else "No waiting before the goal.", 35, 15, colors.text)
		row("Upgrade purchases", tostring(result.purchases))
		row("Income at end / second", B.Format.number(result.income))
		row("Spent on upgrades", B.Format.number(result.spentUpgrades))
		if result.message ~= "" then UI.label(report, result.message, 42, 14, colors.error) end
		UI.label(report, "ASSUMPTIONS", 25, 13, colors.muted, true)
		UI.label(report, "Constant action rate during play. No offline income. Instant purchases. Upgrades add per-level effects; multiplier bonuses add to 1. The selected strategy is a heuristic, not an optimal player.", 72, 13, colors.muted)
		UI.label(report, if result.loot then "Loot times use the first-success distribution on a shared all-misses purchase schedule. Independent rolls; one target; hard pity. Missing times mean the simulated range was insufficient." else "Currency goals track held balance, including the moment before a purchase. Chart lines are sampled; cursor and milestone values use the event timeline.", 62, 13, colors.muted)
	end

	function app:SetConfig(raw: any): (boolean, string?)
		local config, problems = B.validate(raw)
		if not config then
			local lines = {}
			for _, p in problems do table.insert(lines, p.path .. " " .. p.message) end
			local errorText = table.concat(lines, "; ")
			message(errorText, true)
			return false, errorText
		end
		state.version += 1
		state.busy = false
		if runButton then runButton.Text = "Run comparison" end
		state.draft, state.dirty = B.Config.draft(config), true
		if rebuild then rebuild() end
		message("Edited assumptions. Run to compare with the pinned baseline.")
		return true
	end
	function app:SetValue(path: string, value: any): (boolean, string?)
		local draft = B.Config.draft(state.draft)
		local parts = string.split(path, ".")
		local target = draft
		for i = 1, #parts - 1 do target = target[tonumber(parts[i]) or parts[i]] end
		target[tonumber(parts[#parts]) or parts[#parts]] = value
		return self:SetConfig(draft)
	end
	function app:Run(raw: any?)
		if not state.alive then return nil end
		local config, problems = B.validate(raw or state.draft)
		if not config then message(problems[1].path .. " " .. problems[1].message, true); return nil end
		if raw then state.draft = B.Config.draft(config); rebuild() end
		state.version += 1
		local version = state.version
		state.busy = true
		runButton.Text = "Cancel run"
		message("Computing the purchase timeline…")
		local ok, result = pcall(B.simulate, config, { yieldEvery = 500, yield = task.wait, isCancelled = function() return not state.alive or state.version ~= version end })
		if not state.alive or state.version ~= version then return nil end
		state.busy = false
		runButton.Text = "Run comparison"
		if not ok then message(tostring(result), true); return nil end
		state.result, state.dirty = result, false
		if not state.baseline then state.baseline = result end
		render()
		message(if result.message ~= "" then result.message else "Updated. Hover over the chart for exact values.", result.status ~= "reached")
		return result
	end
	function app:PinBaseline()
		if state.result then state.baseline = state.result; render(); message("Current run pinned as the baseline.") end
	end
	function app:LoadPreset(index: number)
		local presets = B.presets()
		assert(presets[index], "Unknown preset")
		state.preset, state.baseline = index, nil
		self:SetConfig(presets[index])
		presetButton.Text = presets[index].name .. "  ›"
		return self:Run()
	end
	function app:Export(): ModuleScript?
		local config, problems = B.validate(state.draft)
		if not config then message(problems[1].path .. " " .. problems[1].message, true); return nil end
		local recording = History:TryBeginRecording("BalanceLabExport", "Export BalanceLab configuration")
		if not recording then message("Finish the current Studio operation first.", true); return nil end
		local module = Instance.new("ModuleScript")
		local ok, err = pcall(function()
			module.Name, module.Source = "BalanceLabConfig", B.toSource(config)
			module.Parent = game:GetService("ReplicatedStorage")
			Selection:Set({ module })
		end)
		if not ok then module:Destroy() end
		History:FinishRecording(recording, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
		message(if ok then "BalanceLabConfig added to ReplicatedStorage. Export is undoable." else tostring(err), not ok)
		return if ok then module else nil
	end
	function app:ImportSelected()
		local selected = Selection:Get()
		if #selected ~= 1 or not selected[1]:IsA("ModuleScript") then message("Select one self-contained config ModuleScript.", true); return end
		if importClone then message("A module import is already running.", true); return end
		local clone = Instance.new("ModuleScript")
		clone.Name, clone.Source, clone.Archivable = selected[1].Name, selected[1].Source, false
		clone.Parent = selected[1].Parent
		importClone = clone
		local ok, raw = pcall(require, clone)
		clone:Destroy()
		importClone = nil
		if not state.alive then return end
		if not ok then message(tostring(raw), true); return end
		if self:SetConfig(raw) then state.baseline = nil; self:Run() end
	end

	presetButton = UI.button(actions, "Crystal Mine  ›", colors, function() spawn(function() app:LoadPreset(state.preset % 3 + 1) end) end)
	presetButton.Size = UDim2.new(0.31, -6, 1, 0)
	runButton = UI.button(actions, "Run comparison", colors, function()
		if state.busy then state.version += 1; state.busy = false; runButton.Text = "Run comparison"; message("Run cancelled.")
		else spawn(function() app:Run() end) end
	end, true)
	runButton.Size = UDim2.new(0.24, -6, 1, 0)
	local pin = UI.button(actions, "Pin current baseline", colors, function() app:PinBaseline() end)
	pin.Size = UDim2.new(0.25, -6, 1, 0)
	local configButton = UI.button(actions, "Edit full JSON", colors, function() app:OpenJSON() end)
	configButton.Size = UDim2.new(0.2, -6, 1, 0)
	metricButton = UI.button(chartActions, "Chart: Balance", colors, function()
		if state.result and state.result.loot then chart.metric = if chart.metric == "Chance" then "Income" else "Chance"
		else chart.metric = if chart.metric == "Balance" then "Income" else "Balance" end
		metricButton.Text = "Chart: " .. chart.metric
		chart:Draw()
	end)
	metricButton.Size = UDim2.new(0.58, -4, 1, 0)
	scaleButton = UI.button(chartActions, "Scale: linear", colors, function()
		chart.logarithmic = not chart.logarithmic
		scaleButton.Text = if chart.logarithmic then "Scale: log" else "Scale: linear"
		chart:Draw()
	end)
	scaleButton.Size = UDim2.new(0.42, -4, 1, 0)

	rebuild = function()
		local scrollPosition = editor.CanvasPosition
		editor:ClearAllChildren()
		UI.new("UIPadding", { PaddingRight = UDim.new(0, 10) }, editor)
		UI.list(editor, 7)
		table.clear(app.Controls)
		local function section(text: string)
			UI.label(editor, text, 27, 12, colors.muted, true)
		end
		local function field(label: string, path: string, value: number)
			local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, editor)
			local title = UI.label(row, label, 30, 14, colors.text)
			title.Size = UDim2.fromScale(0.6, 1)
			local input = UI.new("TextBox", { Name = path, Position = UDim2.fromScale(0.62, 0), Size = UDim2.fromScale(0.38, 1), BackgroundColor3 = colors.panel, BorderSizePixel = 0, ClearTextOnFocus = false, Text = tostring(value), TextSize = 14, TextColor3 = colors.text, Font = Enum.Font.SourceSans }, row)
			UI.new("UICorner", { CornerRadius = UDim.new(0, 3) }, input)
			app.Controls[path] = input
			input.FocusLost:Connect(function()
				local number = tonumber(input.Text)
				if not number then input.Text = tostring(value); message(label .. " must be a number.", true); return end
				local accepted = app:SetValue(path, number)
				if not accepted and input.Parent then input.Text = tostring(value) end
			end)
		end
		local d = state.draft
		section("PLAY PROFILE")
		field("Actions / second", "player.actionsPerSecond", d.player.actionsPerSecond)
		field("Session minutes", "player.sessionMinutes", d.player.sessionMinutes)
		field("Sessions / day", "player.sessionsPerDay", d.player.sessionsPerDay)
		UI.button(editor, "Strategy: " .. d.player.strategy, colors, function() app:SetValue("player.strategy", if d.player.strategy == "efficient" then "eager" else "efficient") end)
		section(string.upper(d.currency) .. " INCOME")
		field("Starting balance", "startingBalance", d.startingBalance)
		field("Per second", "income.perSecond", d.income.perSecond)
		field("Per action", "income.perAction", d.income.perAction)
		section("GOAL")
		UI.label(editor, d.goal.name, 36, 15, colors.text, true)
		if d.goal.kind == "loot" then
			field("Cost / roll", "goal.rollCost", d.goal.rollCost)
			field("Hard pity (0 = off)", "goal.pity", d.goal.pity)
		else field("Currency needed", "goal.amount", d.goal.amount) end
		field("Horizon / hours", "limits.maxHours", d.limits.maxHours)
		for i, u in d.upgrades do
			section(string.upper(u.name))
			UI.label(editor, u.cost.curve .. " cost · " .. u.effect.kind .. " gain", 24, 12, colors.muted)
			field("Base cost", "upgrades." .. i .. ".cost.base", u.cost.base)
			field("Cost growth", "upgrades." .. i .. ".cost.growth", u.cost.growth)
			field("Base gain / level", "upgrades." .. i .. ".effect.base", u.effect.base)
			field("Gain growth", "upgrades." .. i .. ".effect.growth", u.effect.growth)
			field("Maximum level", "upgrades." .. i .. ".maxLevel", u.maxLevel)
		end
		section("CONFIGURATION")
		UI.button(editor, "Export ModuleScript", colors, function() app:Export() end)
		UI.button(editor, "Import selected module", colors, function() spawn(function() app:ImportSelected() end) end)
		UI.label(editor, "Import runs the selected module's code. Use a self-contained config you trust. Full JSON editing runs no code.", 66, 12, colors.muted)
		task.defer(function() if state.alive then editor.CanvasPosition = scrollPosition end end)
	end
	local modal: Frame? = nil
	function app:OpenJSON()
		if modal then return end
		local overlay = UI.new("Frame", { Name = "JSONEditor", Size = UDim2.fromScale(1, 1), BackgroundColor3 = colors.background, BorderSizePixel = 0, ZIndex = 10 }, root)
		modal = overlay
		local covered: { [GuiObject]: boolean } = {}
		for _, child in root:GetChildren() do
			if child:IsA("GuiObject") and child ~= overlay then
				covered[child], child.Visible = child.Visible, false
			end
		end
		local function closeModal()
			overlay:Destroy()
			modal, app.JSONInput = nil, nil
			for child, visible in covered do if child.Parent then child.Visible = visible end end
		end
		local title = UI.label(overlay, "Edit the full configuration", 32, 22, colors.text, true)
		title.ZIndex = 11
		local help = UI.label(overlay, "Add upgrades, change curve types, or edit loot weights. JSON is validated before use.", 40, 14, colors.muted)
		help.Position, help.ZIndex = UDim2.new(0, 0, 0, 35), 11
		local scroll = UI.scroll(overlay, colors)
		scroll.BackgroundTransparency, scroll.BackgroundColor3 = 0, colors.panel
		scroll.Position, scroll.Size, scroll.ZIndex = UDim2.new(0, 0, 0, 84), UDim2.new(1, 0, 1, -132), 11
		UI.padding(scroll, 12)
		local input = UI.new("TextBox", { Name = "JSONSource", Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = json(state.draft), TextColor3 = colors.text, TextSize = 14, Font = Enum.Font.Code, MultiLine = true, ClearTextOnFocus = false, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12 }, scroll)
		local bar = UI.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, ZIndex = 11 }, overlay)
		UI.list(bar, 8, true)
		local apply = UI.button(bar, "Apply JSON", colors, function()
			local function reject(text: string)
				help.Text, help.TextColor3 = text, colors.error
				message(text, true)
			end
			if #input.Text > 300000 then reject("Configuration text is too large."); return end
			local ok, raw = pcall(HttpService.JSONDecode, HttpService, input.Text)
			if not ok then reject("Invalid JSON: " .. tostring(raw)); return end
			local accepted, problem = app:SetConfig(raw)
			if accepted then closeModal(); spawn(function() app:Run() end)
			else reject(problem or "Invalid configuration.") end
		end, true)
		apply.Size, apply.ZIndex = UDim2.new(0.5, -4, 1, 0), 12
		local close = UI.button(bar, "Close", colors, closeModal)
		close.Size, close.ZIndex = UDim2.new(0.5, -4, 1, 0), 12
		app.JSONInput = input
	end
	function app:Destroy()
		if not state.alive then return end
		state.alive, state.version = false, state.version + 1
		for thread in jobs do if coroutine.running() ~= thread then pcall(task.cancel, thread) end end
		table.clear(jobs)
		if importClone then importClone:Destroy(); importClone = nil end
		for _, connection in connections do connection:Disconnect() end
		widget:Destroy()
		toolbar:Destroy()
	end
	table.insert(connections, toggle.Click:Connect(function() widget.Enabled = not widget.Enabled end))
	table.insert(connections, widget:GetPropertyChangedSignal("Enabled"):Connect(function() toggle:SetActive(widget.Enabled) end))
	table.insert(connections, plugin.Unloading:Connect(function() app:Destroy() end))
	rebuild()
	spawn(function() app:Run() end)
	return app
end

return App
