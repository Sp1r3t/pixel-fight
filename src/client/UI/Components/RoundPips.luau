--!strict
--[[
	Индикаторы побед в раундах: по кружку на каждую нужную победу, закрашенные — выигранные.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Wins: Fusion.Value<{ number }>,
	RoundsToWin: Fusion.Value<number>,
	Slot: number,
	Side: "Left" | "Right",
	Position: UDim2,
	AnchorPoint: Vector2?,
}

local PIP_SIZE = 16

local function RoundPips(scope: Scope, props: Props): Instance
	return scope:New "Frame" {
		Name = "RoundPips",
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		Position = props.Position,
		Size = UDim2.fromOffset(PIP_SIZE * 3 + 12, PIP_SIZE),
		[Children] = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = if props.Side == "Left"
					then Enum.HorizontalAlignment.Left
					else Enum.HorizontalAlignment.Right,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			scope:Computed(function(use, innerScope: Scope): { Instance }
				local needed = use(props.RoundsToWin)
				local won = use(props.Wins)[props.Slot] or 0
				local pips = {}
				for index = 1, needed do
					local order = if props.Side == "Left" then index else needed - index
					table.insert(
						pips,
						innerScope:New "Frame" {
							Name = `Pip{index}`,
							BackgroundColor3 = if index <= won then Theme.Colors.Accent else Theme.Colors.StatEmpty,
							BorderSizePixel = 0,
							LayoutOrder = order,
							Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE),
							[Children] = {
								innerScope:New "UICorner" {
									CornerRadius = UDim.new(0.5, 0),
								},
								innerScope:New "UIStroke" {
									Color = Theme.Colors.Outline,
									Thickness = 2,
								},
							},
						}
					)
				end
				return pips
			end),
		} :: { Fusion.Child },
	}
end

return RoundPips
