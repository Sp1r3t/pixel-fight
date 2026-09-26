--!strict
--[[
	Главное меню: логотип, выбранный боец и навигация по разделам.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local PixelFigure = require(script.Parent.Parent.Components.PixelFigure)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

type MenuEntry = {
	text: string,
	screen: AppState.ScreenName,
	primary: boolean?,
}

local ENTRIES: { MenuEntry } = {
	{ text = "Одиночная игра", screen = "BossMap", primary = true },
	{ text = "Мультиплеер", screen = "ModeSelect" },
	{ text = "Персонажи", screen = "CharacterSelect" },
	{ text = "Магазин", screen = "Shop" },
	{ text = "Управление", screen = "ControlsSettings" },
}

local function MainMenu(scope: Scope, state: AppState.AppState): Instance
	local buttons: { Instance } = {}
	for index, entry in ENTRIES do
		table.insert(
			buttons,
			Button(scope, {
				Text = entry.text,
				LayoutOrder = index,
				Size = UDim2.fromOffset(300, 52),
				Color = if entry.primary then Theme.Colors.ButtonPrimary else Theme.Colors.Button,
				OnClick = function()
					AppState.navigate(state, entry.screen)
				end,
			})
		)
	end

	-- Превью выбранного бойца справа: пересоздаётся при смене выбора.
	local fighterPreview = scope:Computed(function(use, innerScope: Scope): Instance?
		local def = CharacterRegistry.get(use(state.selectedCharacterId))
		if def == nil then
			return nil
		end
		return innerScope:New "Frame" {
			Name = "FighterPreview",
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -60, 0.55, 0),
			Size = UDim2.fromOffset(300, 360),
			[Children] = {
				PixelFigure(innerScope, {
					Palette = def.palette,
					Size = UDim2.fromOffset(280, 280),
					Position = UDim2.fromOffset(10, 0),
				}),
				innerScope:New "TextLabel" {
					Name = "Name",
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Pixel,
					Position = UDim2.fromOffset(0, 290),
					Size = UDim2.new(1, 0, 0, 36),
					Text = string.upper(def.displayName),
					TextColor3 = Theme.Colors.Text,
					TextSize = 36,
				},
				innerScope:New "TextLabel" {
					Name = "Title",
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Pixel,
					Position = UDim2.fromOffset(0, 326),
					Size = UDim2.new(1, 0, 0, 24),
					Text = def.title,
					TextColor3 = Color3.fromHex(def.palette.accent),
					TextSize = 22,
				},
			},
		}
	end)

	return scope:New "Frame" {
		Name = "MainMenu",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			scope:New "TextLabel" {
				Name = "Logo",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(60, 40),
				Size = UDim2.fromOffset(480, 80),
				Text = "PIXEL FIGHT",
				TextColor3 = Theme.Colors.Accent,
				TextSize = 80,
				TextXAlignment = Enum.TextXAlignment.Left,
				[Children] = scope:New "UIStroke" {
					Color = Theme.Colors.Outline,
					Thickness = 4,
				},
			},
			scope:New "TextLabel" {
				Name = "Tagline",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.BodyRegular,
				Position = UDim2.fromOffset(64, 118),
				Size = UDim2.fromOffset(480, 24),
				Text = "2D-файтинг · 16 бойцов · 20 боссов",
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			scope:New "Frame" {
				Name = "Buttons",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(60, 170),
				Size = UDim2.fromOffset(300, 320),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 10),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					buttons,
				} :: { Fusion.Child },
			},
			fighterPreview,
			scope:New "TextLabel" {
				Name = "Version",
				AnchorPoint = Vector2.new(0, 1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.new(0, 16, 1, -10),
				Size = UDim2.fromOffset(300, 18),
				Text = "PROTOTYPE - STAGE 1",
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
		} :: { Fusion.Child },
	}
end

return MainMenu
