--!strict
--[[
	Панель интерфейса: тёмная заливка с мягким вертикальным градиентом, толстая обводка,
	чуть скруглённые углы и светлая кромка сверху — «пиксельно, но не сильно».

	Содержимое передаётся в Content (любые дети Fusion). Цвет обводки можно подсветить
	(StrokeColor), например цветом сложности босса или персонажа.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>
type UsedAs<T> = Fusion.UsedAs<T>

export type Props = {
	Name: string?,
	Size: UsedAs<UDim2>?,
	Position: UsedAs<UDim2>?,
	AnchorPoint: UsedAs<Vector2>?,
	Color: UsedAs<Color3>?,
	Transparency: UsedAs<number>?,
	StrokeColor: UsedAs<Color3>?,
	StrokeThickness: UsedAs<number>?,
	Radius: number?,
	Edge: boolean?, -- светлая кромка сверху (по умолчанию есть)
	LayoutOrder: number?,
	ZIndex: number?,
	Visible: UsedAs<boolean>?,
	ClipsDescendants: boolean?,
	Content: Fusion.Child?,
}

local WHITE = Color3.new(1, 1, 1)

local function Panel(scope: Scope, props: Props): Frame
	local radius = props.Radius or Theme.Radius
	local content: Fusion.Child = props.Content or {}
	local zIndex = props.ZIndex or 1
	local edge: { Instance } = {}
	if props.Edge ~= false then
		table.insert(
			edge,
			scope:New "Frame" {
				Name = "Edge",
				BackgroundColor3 = Theme.Colors.PanelEdge,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(radius, 2),
				Size = UDim2.new(1, -radius * 2, 0, 2),
				ZIndex = zIndex,
			}
		)
	end

	return scope:New "Frame" {
		Name = props.Name or "Panel",
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = props.Color or Theme.Colors.Panel,
		BackgroundTransparency = props.Transparency or 0.04,
		BorderSizePixel = 0,
		ClipsDescendants = props.ClipsDescendants,
		LayoutOrder = props.LayoutOrder,
		Position = props.Position,
		Size = props.Size,
		Visible = props.Visible,
		ZIndex = zIndex,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, radius) },
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = props.StrokeColor or Theme.Colors.PanelEdge,
				Thickness = props.StrokeThickness or Theme.Outline,
			},
			scope:New "UIGradient" {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, WHITE),
					ColorSequenceKeypoint.new(1, Color3.new(0.78, 0.78, 0.84)),
				}),
				Rotation = 90,
			},
			edge,
			content,
		} :: { Fusion.Child },
	} :: Frame
end

return Panel
