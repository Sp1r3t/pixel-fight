--!strict
--[[
	Шапка экрана: кнопка «Назад» слева, крупный заголовок по центру и (по желанию) монеты и кристаллы справа.
	Высота шапки — 64 логических пикселя; содержимое экрана начинается ниже.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.Theme)
local Format = require(script.Parent.Parent.Format)
local Button = require(script.Parent.Button)
local Pill = require(script.Parent.Pill)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

export type Props = {
	Title: string,
	OnBack: () -> (),
	Coins: Fusion.Value<number>?, -- показать монеты игрока справа
	Crystals: Fusion.Value<number>?, -- и кристаллы (левее монет)
	BackText: string?,
}

local function ScreenHeader(scope: Scope, props: Props): Instance
	-- Счётчики справа: строка, выровненная по правому краю (длинные числа не наезжают друг на друга).
	local right: { Instance } = {
		scope:New "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		},
	}
	local coins = props.Coins
	if coins then
		table.insert(
			right,
			Pill(scope, {
				Name = "Coins",
				Icon = "🪙",
				Text = scope:Computed(function(use)
					return Format.number(use(coins))
				end),
				Color = Theme.Colors.Panel,
				TextColor = Theme.Colors.Coins,
				Height = 34,
				LayoutOrder = 2,
			})
		)
	end
	local crystals = props.Crystals
	if crystals then
		table.insert(
			right,
			Pill(scope, {
				Name = "Crystals",
				Icon = "💎",
				Text = scope:Computed(function(use)
					return Format.number(use(crystals))
				end),
				Color = Theme.Colors.Panel,
				TextColor = Theme.Colors.Crystals,
				Height = 34,
				LayoutOrder = 1,
			})
		)
	end
	-- С двумя счётчиками заголовку оставляем меньше места, чтобы ничего не наезжало.
	local titleMargin = if crystals then 560 else 380

	return scope:New "Frame" {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 64),
		[Children] = {
			Button(scope, {
				Name = "Back",
				Text = props.BackText or "← Назад",
				OnClick = props.OnBack,
				Position = UDim2.fromOffset(16, 10),
				Size = UDim2.fromOffset(132, 46),
				TextSize = 20,
			}),
			scope:New "TextLabel" {
				Name = "Title",
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Title,
				Position = UDim2.new(0.5, 0, 0, 10),
				Size = UDim2.new(1, -titleMargin, 0, 44),
				Text = props.Title,
				TextColor3 = Theme.Colors.Accent,
				TextScaled = true,
				[Children] = {
					scope:New "UITextSizeConstraint" { MaxTextSize = 36 },
					scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = 3,
					},
				},
			},
			scope:New "Frame" {
				Name = "Counters",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Position = UDim2.new(1, -16, 0, 14),
				Size = UDim2.fromOffset(titleMargin / 2 - 24, 34),
				[Children] = right,
			},
		} :: { Fusion.Child },
	}
end

return ScreenHeader
