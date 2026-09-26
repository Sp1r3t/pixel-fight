--!strict
--[[
	Пиксельная кнопка с «тенью»: при наведении светлеет, при нажатии проседает (Spring-анимации).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>
type UsedAs<T> = Fusion.UsedAs<T>

export type Props = {
	Text: UsedAs<string>,
	OnClick: () -> (),
	Size: UsedAs<UDim2>?,
	Position: UsedAs<UDim2>?,
	AnchorPoint: UsedAs<Vector2>?,
	LayoutOrder: UsedAs<number>?,
	Color: UsedAs<Color3>?,
	Disabled: UsedAs<boolean>?,
	Font: Enum.Font?,
	TextSize: number?,
}

local SHADOW_DEPTH = 4

local function Button(scope: Scope, props: Props): Instance
	local hovering = scope:Value(false)
	local pressing = scope:Value(false)
	local disabled: UsedAs<boolean> = props.Disabled or false
	local baseColor: UsedAs<Color3> = props.Color or Theme.Colors.Button

	local targetColor = scope:Computed(function(use)
		local color = use(baseColor)
		if use(disabled) then
			return Theme.Colors.Disabled
		elseif use(pressing) then
			return color:Lerp(Color3.new(0, 0, 0), 0.2)
		elseif use(hovering) then
			return color:Lerp(Color3.new(1, 1, 1), 0.15)
		end
		return color
	end)

	local targetDepth = scope:Computed(function(use)
		return if use(pressing) and not use(disabled) then SHADOW_DEPTH else 0
	end)
	local depth = scope:Spring(targetDepth, 40, 1)

	return scope:New "Frame" {
		Name = "Button",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(220, 48),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,

		[Children] = {
			scope:New "Frame" {
				Name = "Shadow",
				BackgroundColor3 = Theme.Colors.Outline,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, SHADOW_DEPTH),
				Size = UDim2.new(1, 0, 1, -SHADOW_DEPTH),
			},
			scope:New "TextButton" {
				Name = "Face",
				AutoButtonColor = false,
				BackgroundColor3 = scope:Spring(targetColor, 30, 1),
				BorderSizePixel = 0,
				Position = scope:Computed(function(use)
					return UDim2.fromOffset(0, use(depth))
				end),
				Size = UDim2.new(1, 0, 1, -SHADOW_DEPTH),
				Font = props.Font or Theme.Fonts.Body,
				Text = props.Text,
				TextSize = props.TextSize or 22,
				TextColor3 = scope:Computed(function(use)
					return if use(disabled) then Theme.Colors.TextDim else Theme.Colors.Text
				end),

				[OnEvent "MouseEnter"] = function()
					hovering:set(true)
				end,
				[OnEvent "MouseLeave"] = function()
					hovering:set(false)
					pressing:set(false)
				end,
				[OnEvent "MouseButton1Down"] = function()
					pressing:set(true)
				end,
				[OnEvent "MouseButton1Up"] = function()
					pressing:set(false)
				end,
				[OnEvent "Activated"] = function()
					if not peek(disabled) then
						props.OnClick()
					end
				end,

				[Children] = {
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.Colors.Outline,
						Thickness = Theme.Outline,
					},
				},
			},
		},
	}
end

return Button
