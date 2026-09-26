--!strict
--[[
	Шапка экрана: кнопка «Назад» слева и заголовок по центру.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Button)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Title: string,
	OnBack: () -> (),
}

local function ScreenHeader(scope: Scope, props: Props): Instance
	return scope:New "Frame" {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 64),
		[Children] = {
			Button(scope, {
				Text = "← Назад",
				OnClick = props.OnBack,
				Position = UDim2.fromOffset(16, 12),
				Size = UDim2.fromOffset(130, 42),
				TextSize = 20,
			}),
			scope:New "TextLabel" {
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(0.5, 0, 0, 14),
				Size = UDim2.new(1, -340, 0, 40),
				Text = props.Title,
				TextColor3 = Theme.Colors.Accent,
				TextSize = 32,
			},
		},
	}
end

return ScreenHeader
