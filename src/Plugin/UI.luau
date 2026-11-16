--!strict
local UI = {}

function UI.new(class: string, props: { [string]: any }, parent: Instance): any
	local object = Instance.new(class)
	for key, value in props do object[key] = value end
	if object:IsA("GuiObject") and props.LayoutOrder == nil then object.LayoutOrder = #parent:GetChildren() end
	object.Parent = parent
	return object
end

function UI.list(parent: Instance, gap: number, horizontal: boolean?)
	return UI.new("UIListLayout", { Padding = UDim.new(0, gap), FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }, parent)
end

function UI.padding(parent: Instance, amount: number)
	UI.new("UIPadding", { PaddingTop = UDim.new(0, amount), PaddingBottom = UDim.new(0, amount), PaddingLeft = UDim.new(0, amount), PaddingRight = UDim.new(0, amount) }, parent)
end

function UI.label(parent: Instance, text: string, height: number, size: number, color: Color3, bold: boolean?): TextLabel
	return UI.new("TextLabel", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, Text = text, TextSize = size, TextColor3 = color, Font = if bold then Enum.Font.SourceSansSemibold else Enum.Font.SourceSans, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true }, parent)
end

function UI.button(parent: Instance, text: string, colors: any, action: () -> (), accent: boolean?): TextButton
	local base = if accent then colors.accent else colors.button
	local b = UI.new("TextButton", { Name = text:gsub("%W", ""), Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = base, BorderSizePixel = 0, Text = text, TextSize = 15, TextColor3 = if accent then Color3.fromRGB(15, 29, 27) else colors.text, Font = Enum.Font.SourceSansSemibold, AutoButtonColor = false }, parent)
	UI.new("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
	b.MouseEnter:Connect(function() b.BackgroundColor3 = base:Lerp(colors.text, 0.09) end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = base end)
	b.MouseButton1Down:Connect(function() b.BackgroundColor3 = base:Lerp(colors.background, 0.16) end)
	b.MouseButton1Up:Connect(function() b.BackgroundColor3 = base end)
	b.Activated:Connect(action)
	return b
end

function UI.scroll(parent: Instance, colors: any): ScrollingFrame
	return UI.new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = colors.muted, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y }, parent)
end

return UI
