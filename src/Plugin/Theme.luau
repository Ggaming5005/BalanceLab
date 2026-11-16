--!strict
local Theme = {}

function Theme.colors()
	local theme = settings().Studio.Theme
	local function color(role: Enum.StudioStyleGuideColor)
		return theme:GetColor(role)
	end
	return {
		background = color(Enum.StudioStyleGuideColor.MainBackground),
		panel = color(Enum.StudioStyleGuideColor.InputFieldBackground),
		button = color(Enum.StudioStyleGuideColor.Button),
		text = color(Enum.StudioStyleGuideColor.MainText),
		muted = color(Enum.StudioStyleGuideColor.DimmedText),
		border = color(Enum.StudioStyleGuideColor.Border),
		accent = Color3.fromRGB(77, 165, 143),
		before = Color3.fromRGB(151, 165, 188),
		error = Color3.fromRGB(214, 111, 100),
	}
end

return Theme
