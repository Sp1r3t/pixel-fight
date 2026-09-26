--!strict
--[[
	Крупная надпись по центру экрана боя: «ROUND 1», «FIGHT!», «K.O.», «TIME», «YOU WIN!» …
	Каждая новая надпись «выстреливает» из увеличенного размера (пружина масштаба).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Text: Fusion.Value<string>,
	Color: Fusion.Value<Color3>,
	Serial: Fusion.Value<number>,
}

local function Banner(scope: Scope, props: Props): Instance
	local scale = scope:Spring(scope:Value(1), 28, 0.55)
	scope:Observer(props.Serial):onChange(function()
		scale:setPosition(2.4)
	end)

	return scope:New "TextLabel" {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Pixel,
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(900, 110),
		Text = props.Text,
		TextColor3 = props.Color,
		TextSize = 96,
		Visible = scope:Computed(function(use)
			return use(props.Text) ~= ""
		end),
		ZIndex = 20,
		[Children] = {
			scope:New "UIScale" {
				Scale = scale,
			},
			scope:New "UIStroke" {
				Color = Theme.Colors.Outline,
				Thickness = 6,
			},
		},
	}
end

return Banner
