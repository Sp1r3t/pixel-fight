--!strict
--[[
	Крупная надпись по центру экрана боя: «ROUND 1», «FIGHT!», «K.O.», «TIME», «YOU WIN!» …
	Каждая новая надпись «выстреливает» из увеличенного размера (пружина масштаба), а под ней
	раскрывается тёмная полоса с цветными кантами — надпись читается на любом фоне.
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

local BAND_HEIGHT = 124

local function Banner(scope: Scope, props: Props): Instance
	local scale = scope:Spring(scope:Value(1), 28, 0.55)
	local band = scope:Spring(scope:Value(1), 22, 0.8)
	scope:Observer(props.Serial):onChange(function()
		scale:setPosition(2.4)
		band:setPosition(0)
	end)
	local visible = scope:Computed(function(use)
		return use(props.Text) ~= ""
	end)

	local function edge(name: string, y: number): Instance
		return scope:New "Frame" {
			Name = name,
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = props.Color,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, y),
			Size = UDim2.new(1, 0, 0, 4),
			ZIndex = 19,
			[Children] = scope:New "UIGradient" {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.25, 0.1),
					NumberSequenceKeypoint.new(0.75, 0.1),
					NumberSequenceKeypoint.new(1, 1),
				}),
			},
		}
	end

	return scope:New "Frame" {
		Name = "BannerLayer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 18,
		[Children] = {
			scope:New "Frame" {
				Name = "BannerBand",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Theme.Colors.Outline,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.4),
				Size = scope:Computed(function(use)
					return UDim2.new(1, 0, 0, BAND_HEIGHT * math.clamp(use(band), 0, 1.2))
				end),
				Visible = visible,
				ZIndex = 18,
				[Children] = {
					scope:New "UIGradient" {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.2, 0.25),
							NumberSequenceKeypoint.new(0.8, 0.25),
							NumberSequenceKeypoint.new(1, 1),
						}),
					},
					edge("Top", 0),
					edge("Bottom", 1),
				},
			},
			scope:New "TextLabel" {
				Name = "Banner",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromScale(0.5, 0.4),
				Size = UDim2.fromOffset(900, 110),
				Text = props.Text,
				TextColor3 = props.Color,
				TextSize = 96,
				Visible = visible,
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
			},
		},
	}
end

return Banner
