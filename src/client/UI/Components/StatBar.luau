--!strict
--[[
	Полоска характеристики из пиксельных сегментов: рейтинг 2..8 из Balance.StatMax.
	Сегменты заполняются с небольшой задержкой друг за другом (Tween), когда меняется значение.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Balance = require(ReplicatedStorage.Shared.Config.Balance)
local Theme = require(script.Parent.Parent.Theme)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>
type UsedAs<T> = Fusion.UsedAs<T>

export type Props = {
	Label: string,
	Rating: UsedAs<number>,
	ValueText: UsedAs<string>,
	Color: UsedAs<Color3>,
	LayoutOrder: number?,
}

local SEGMENT_WIDTH = 18
local SEGMENT_GAP = 3

local function StatBar(scope: Scope, props: Props): Instance
	local segments: { Instance } = {}
	for index = 1, Balance.StatMax do
		local filled = scope:Computed(function(use)
			return if use(props.Rating) >= index then 1 else 0
		end)
		local fill = scope:Tween(filled, TweenInfo.new(0.08 + index * 0.025, Enum.EasingStyle.Quad))

		table.insert(
			segments,
			scope:New "Frame" {
				Name = `Segment{index}`,
				BackgroundColor3 = scope:Computed(function(use)
					return Theme.Colors.StatEmpty:Lerp(use(props.Color), use(fill))
				end),
				BorderSizePixel = 0,
				LayoutOrder = index,
				Size = UDim2.fromOffset(SEGMENT_WIDTH, 12),
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0, 3) },
			}
		)
	end

	return scope:New "Frame" {
		Name = `Stat_{props.Label}`,
		BackgroundTransparency = 1,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(1, 0, 0, 18),
		[Children] = {
			scope:New "TextLabel" {
				Name = "Label",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Text = props.Label,
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(0, 110, 1, 0),
			},
			scope:New "Frame" {
				Name = "Segments",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(110, 3),
				Size = UDim2.fromOffset(Balance.StatMax * (SEGMENT_WIDTH + SEGMENT_GAP), 12),
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, SEGMENT_GAP),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					segments,
				} :: { Fusion.Child },
			},
			scope:New "TextLabel" {
				Name = "Value",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 90, 1, 0),
				Text = props.ValueText,
				TextColor3 = Theme.Colors.Text,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Right,
			},
		},
	}
end

return StatBar
