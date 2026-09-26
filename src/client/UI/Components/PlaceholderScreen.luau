--!strict
--[[
	Временный экран-заглушка для разделов, которые появятся на следующих этапах.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)
local ScreenHeader = require(script.Parent.ScreenHeader)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Title: string,
	Stage: number,
	Description: string,
	OnBack: () -> (),
}

local function PlaceholderScreen(scope: Scope, props: Props): Instance
	return scope:New "Frame" {
		Name = "PlaceholderScreen",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			ScreenHeader(scope, { Title = props.Title, OnBack = props.OnBack }),
			scope:New "Frame" {
				Name = "Card",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Theme.Colors.Panel,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.55),
				Size = UDim2.fromOffset(560, 220),
				[Children] = {
					scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = Theme.Outline,
					},
					scope:New "TextLabel" {
						Name = "Stage",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Pixel,
						Position = UDim2.fromOffset(0, 28),
						Size = UDim2.new(1, 0, 0, 40),
						Text = `STAGE {props.Stage}`,
						TextColor3 = Theme.Colors.Accent,
						TextSize = 40,
					},
					scope:New "TextLabel" {
						Name = "Description",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.BodyRegular,
						Position = UDim2.fromOffset(32, 84),
						Size = UDim2.new(1, -64, 1, -110),
						Text = props.Description,
						TextColor3 = Theme.Colors.Text,
						TextSize = 20,
						TextWrapped = true,
						TextYAlignment = Enum.TextYAlignment.Top,
					},
				},
			},
		},
	}
end

return PlaceholderScreen
