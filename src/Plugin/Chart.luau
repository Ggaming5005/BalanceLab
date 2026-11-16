--!strict
local B = require(script.Parent.BalanceLab)
local UI = require(script.Parent.UI)
local Chart = {}

function Chart.new(parent: Instance, colors: any)
	local frame = UI.new("Frame", { Name = "ProgressChart", Size = UDim2.new(1, 0, 0, 300), BackgroundColor3 = colors.panel, BorderSizePixel = 0, ClipsDescendants = true }, parent)
	UI.new("UICorner", { CornerRadius = UDim.new(0, 5) }, frame)
	local plot = UI.new("Frame", { Name = "Plot", Position = UDim2.new(0, 59, 0, 30), Size = UDim2.new(1, -78, 1, -67), BackgroundTransparency = 1, Active = true }, frame)
	local drawing = UI.new("Folder", {}, plot)
	local cursor = UI.new("Frame", { Name = "Cursor", Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = colors.text, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 5, Visible = false }, plot)
	local title = UI.label(frame, "Balance · sampled curve, exact cursor values", 24, 13, colors.muted)
	title.Position = UDim2.new(0, 12, 0, 2)
	title.Size = UDim2.new(1, -24, 0, 24)
	local readout = UI.label(parent, "Move over the chart to inspect a moment.", 34, 13, colors.muted)
	local chart: any = { Frame = frame, Readout = readout, current = nil, before = nil, metric = "Balance", logarithmic = false, maxTime = 1 }

	local function value(result: any, t: number): number?
		if not result then return nil end
		if t > result.endTime then
			if result.status ~= "reached" then return nil end
			t = result.endTime
		end
		if chart.metric == "Chance" then return B.Simulate.chanceAt(result, t)
		elseif chart.metric == "Income" then return B.Simulate.incomeAt(result, t)
		else return B.Simulate.balanceAt(result, t) end
	end
	local function formatValue(v: number?): string
		if v == nil then return "—" end
		return if chart.metric == "Chance" then B.Format.percent(v) else B.Format.number(v)
	end
	local function transform(v: number): number
		return if chart.logarithmic and chart.metric ~= "Chance" then math.log10(1 + v) else v
	end
	function chart:SetCursor(t: number)
		t = math.clamp(t, 0, self.maxTime)
		cursor.Visible = true
		local fraction = t / self.maxTime
		cursor.Position = UDim2.new(fraction, -fraction, 0, 0)
		readout.Text = B.Format.duration(t) .. " play   ·   Before " .. formatValue(value(self.before, t)) .. "   ·   After " .. formatValue(value(self.current, t))
	end
	function chart:Draw()
		if not frame.Parent then return end
		drawing:ClearAllChildren()
		cursor.Visible = false
		readout.Text = "Move over the chart to inspect a moment."
		local width, height = plot.AbsoluteSize.X, plot.AbsoluteSize.Y
		if width < 2 or height < 2 or not self.current then return end
		self.maxTime = math.max(self.current.endTime, if self.before then self.before.endTime else 0, 0.001)
		local maximum = if self.metric == "Chance" then 1 else 0
		for _, r in { self.current, self.before } do
			if r then
				local values = if self.metric == "Income" then r.timeline.income else r.timeline.before
				if self.metric ~= "Chance" then
					for _, v in values do maximum = math.max(maximum, v) end
				end
			end
		end
		maximum = math.max(transform(maximum), 1e-12)
		local log = self.logarithmic and self.metric ~= "Chance"
		title.Text = self.metric .. (if log then " · logarithmic scale" else " · linear scale") .. "   /   play time"
		for i = 0, 4 do
			local fraction = i / 4
			UI.new("Frame", { Position = UDim2.fromScale(0, 1 - fraction), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, BackgroundColor3 = colors.border, BackgroundTransparency = 0.35 }, drawing)
			local raw = if log then 10 ^ (maximum * fraction) - 1 else maximum * fraction
			local tick = UI.label(drawing, formatValue(raw), 18, 12, colors.muted)
			tick.Position = UDim2.new(0, -54, 1 - fraction, -9)
			tick.Size = UDim2.new(0, 48, 0, 18)
			tick.TextXAlignment = Enum.TextXAlignment.Right
			local time = UI.label(drawing, B.Format.tick(fraction * self.maxTime), 18, 12, colors.muted)
			time.AnchorPoint = Vector2.new(if i == 0 then 0 elseif i == 4 then 1 else 0.5, 0)
			time.Position = UDim2.new(fraction, 0, 1, 9)
			time.Size = UDim2.new(0, 70, 0, 18)
			time.TextXAlignment = if i == 0 then Enum.TextXAlignment.Left elseif i == 4 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
		end
		local function series(result: any, color: Color3, thickness: number)
			if not result then return end
			local last: Vector2? = nil
			for i = 0, 180 do
				local t = self.maxTime * i / 180
				local v = value(result, t)
				if v == nil then last = nil; continue end
				local point = Vector2.new(width * i / 180, height * (1 - math.clamp(transform(v) / maximum, 0, 1)))
				if last then
					local delta = point - last
					UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((point.X + last.X) / 2, (point.Y + last.Y) / 2), Size = UDim2.fromOffset(delta.Magnitude + 0.4, thickness), Rotation = math.deg(math.atan2(delta.Y, delta.X)), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 3 }, drawing)
				end
				last = point
			end
		end
		series(self.before, colors.before, 2)
		series(self.current, colors.accent, 2)
	end
	plot.MouseMoved:Connect(function(x)
		if chart.current and plot.AbsoluteSize.X > 0 then chart:SetCursor((x - plot.AbsolutePosition.X) / plot.AbsoluteSize.X * chart.maxTime) end
	end)
	plot.MouseLeave:Connect(function() cursor.Visible = false end)
	local queued = false
	plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if queued then return end
		queued = true
		task.defer(function() queued = false; chart:Draw() end)
	end)
	return chart
end

return Chart
