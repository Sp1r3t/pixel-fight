--!strict
--[[
	«Таблетка» — компактная плашка с иконкой и текстом: монеты в шапке экранов, метки
	(«БЕСПЛАТНО», «DELUXE», цена), статусы. Ширина подстраивается под текст.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>
type UsedAs<T> = Fusion.UsedAs<T>

export type Props = {
	Name: string?,
	Text: UsedAs<string>,
	Icon: string?,
	Color: UsedAs<Color3>?,
	TextColor: UsedAs<Color3>?,
	Height: number?,
	TextSize: number?,
	Font: Enum.Font?,
	Position: UsedAs<UDim2>?,
	AnchorPoint: UsedAs<Vector2>?,
	LayoutOrder: number?,
	ZIndex: number?,
	Visible: UsedAs<boolean>?,
}

local function Pill(scope: Scope, props: Props): Instance
	local height = props.Height or 30
	local textSize = props.TextSize or math.floor(height * 0.6)
	local zIndex = props.ZIndex or 1
	local items: { Instance } = {
		scope:New "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		},
	}
	if props.Icon then
		table.insert(
			items,
			scope:New "TextLabel" {
				Name = "Icon",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Title,
				LayoutOrder = 1,
				Size = UDim2.fromOffset(textSize + 4, height),
				Text = props.Icon,
				TextSize = textSize + 2,
				TextColor3 = Color3.new(1, 1, 1),
				ZIndex = zIndex + 1,
			}
		)
	end
	table.insert(
		items,
		scope:New "TextLabel" {
			Name = "Value",
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = props.Font or Theme.Fonts.Title,
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, height),
			Text = props.Text,
			TextColor3 = props.TextColor or Theme.Colors.Text,
			TextSize = textSize,
			ZIndex = zIndex + 1,
		}
	)

	return scope:New "Frame" {
		Name = props.Name or "Pill",
		AnchorPoint = props.AnchorPoint,
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = props.Color or Theme.Colors.Panel,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		Position = props.Position,
		Size = UDim2.fromOffset(0, height),
		Visible = props.Visible,
		ZIndex = zIndex,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			scope:New "UIPadding" {
				PaddingLeft = UDim.new(0, math.floor(height * 0.4)),
				PaddingRight = UDim.new(0, math.floor(height * 0.45)),
			},
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Colors.Outline,
				Thickness = 2,
			},
			items,
		} :: { Fusion.Child },
	}
end

return Pill
