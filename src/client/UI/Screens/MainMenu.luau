--!strict
--[[
	Главное меню: логотип, монеты, крупные плитки разделов с иконками и выбранный боец справа.

	Для детей: три главные плитки (башня боссов, онлайн, тренировка) — большие и цветные,
	под ними — бойцы, магазин и управление. Подпись под названием объясняет, что внутри.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Format = require(script.Parent.Parent.Format)
local Button = require(script.Parent.Parent.Components.Button)
local Pill = require(script.Parent.Parent.Components.Pill)
local FighterPortrait = require(script.Parent.Parent.Components.FighterPortrait)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

type MenuEntry = {
	text: string,
	icon: string,
	subtitle: string?,
	color: Color3,
	screen: AppState.ScreenName?,
	action: ((state: AppState.AppState) -> ())?,
}

-- Главные разделы — большие плитки.
local MAIN: { MenuEntry } = {
	{
		text = "Одиночная игра",
		icon = "🏰",
		subtitle = "Башня из 20 боссов",
		color = Theme.Colors.ButtonPrimary,
		screen = "BossMap",
	},
	{
		text = "Мультиплеер",
		icon = "⚔️",
		subtitle = "1 на 1 · 2 на 2",
		color = Theme.Colors.Info,
		screen = "ModeSelect",
	},
	{
		text = "Тренировка",
		icon = "🥋",
		subtitle = "Пробуй приёмы",
		color = Theme.Colors.Success,
		action = function(state: AppState.AppState)
			state.actions.startTraining()
		end,
	},
}

-- Остальное — кнопки поменьше.
local MORE: { MenuEntry } = {
	{ text = "Персонажи", icon = "🦸", color = Theme.Colors.Button, screen = "CharacterSelect" },
	{ text = "Магазин", icon = "🛒", color = Color3.fromHex("#E08A1E"), screen = "Shop" },
	{ text = "Управление", icon = "🎮", color = Theme.Colors.Button, screen = "ControlsSettings" },
}

local TILE_W, TILE_H, GAP = 180, 150, 12
local LEFT, TOP = 40, 158

-- Ореол из трёх колец: чем ближе к бойцу, тем ярче (пиксельная «радиальная» подсветка).
local function halo(scope: Scope, color: Color3): Instance
	local rings: { Instance } = {}
	for index, ring in { { size = 270, alpha = 0.9 }, { size = 210, alpha = 0.84 }, { size = 150, alpha = 0.78 } } do
		table.insert(
			rings,
			scope:New "Frame" {
				Name = `Ring{index}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = color,
				BackgroundTransparency = ring.alpha,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(ring.size, ring.size),
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			}
		)
	end
	return scope:New "Frame" {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(150, 165),
		Size = UDim2.fromOffset(270, 270),
		[Children] = rings,
	}
end

local function open(state: AppState.AppState, entry: MenuEntry)
	if entry.action then
		entry.action(state)
	elseif entry.screen then
		AppState.navigate(state, entry.screen)
	end
end

local function MainMenu(scope: Scope, state: AppState.AppState): Instance
	local items: { Instance } = {}
	for index, entry in MAIN do
		table.insert(
			items,
			Button(scope, {
				Name = `Tile{index}`,
				Text = entry.text,
				Icon = entry.icon,
				IconSize = 56,
				Subtitle = entry.subtitle,
				Tile = true,
				Color = entry.color,
				TextSize = 23,
				Position = UDim2.fromOffset(LEFT + (index - 1) * (TILE_W + GAP), TOP),
				Size = UDim2.fromOffset(TILE_W, TILE_H),
				OnClick = function()
					open(state, entry)
				end,
			})
		)
	end
	for index, entry in MORE do
		table.insert(
			items,
			Button(scope, {
				Name = `More{index}`,
				Text = entry.text,
				Icon = entry.icon,
				Color = entry.color,
				TextSize = 19,
				Position = UDim2.fromOffset(LEFT + (index - 1) * (TILE_W + GAP), TOP + TILE_H + 16),
				Size = UDim2.fromOffset(TILE_W, 56),
				OnClick = function()
					open(state, entry)
				end,
			})
		)
	end

	-- Выбранный боец справа: пересоздаётся при смене выбора.
	local fighterPreview = scope:Computed(function(use, innerScope: Scope): Instance?
		local def = CharacterRegistry.get(use(state.selectedCharacterId))
		if def == nil then
			return nil
		end
		local accent = Color3.fromHex(def.palette.accent)
		return innerScope:New "Frame" {
			Name = "FighterPreview",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -24, 0, 70),
			Size = UDim2.fromOffset(300, 450),
			[Children] = {
				-- Ступенчатый ореол цвета бойца и «подставка» под ногами.
				halo(innerScope, accent),
				innerScope:New "Frame" {
					Name = "Pedestal",
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = Theme.Colors.Outline,
					BackgroundTransparency = 0.35,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(150, 296),
					Size = UDim2.fromOffset(170, 26),
					[Children] = innerScope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
				},
				FighterPortrait(innerScope, {
					Character = def,
					Framing = "Full",
					Facing = -1,
					Animated = true,
					Size = UDim2.fromOffset(300, 300),
					Position = UDim2.fromOffset(0, 0),
					ZIndex = 2,
				}),
				innerScope:New "TextLabel" {
					Name = "Name",
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Pixel,
					Position = UDim2.fromOffset(0, 312),
					Size = UDim2.new(1, 0, 0, 40),
					Text = string.upper(def.displayName),
					TextColor3 = Theme.Colors.Text,
					TextSize = 40,
					ZIndex = 3,
					[Children] = innerScope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = 3,
					},
				},
				innerScope:New "TextLabel" {
					Name = "Title",
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Pixel,
					Position = UDim2.fromOffset(0, 352),
					Size = UDim2.new(1, 0, 0, 22),
					Text = def.title,
					TextColor3 = accent,
					TextSize = 22,
					ZIndex = 3,
					[Children] = innerScope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = 2,
					},
				},
				Button(innerScope, {
					Name = "ChangeFighter",
					Text = "Сменить бойца",
					Icon = "🔄",
					TextSize = 17,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromOffset(150, 386),
					Size = UDim2.fromOffset(190, 46),
					OnClick = function()
						AppState.navigate(state, "CharacterSelect")
					end,
				}),
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
				Position = UDim2.fromOffset(LEFT - 2, 28),
				Size = UDim2.fromOffset(560, 84),
				Text = "PIXEL FIGHT",
				TextColor3 = Theme.Colors.Accent,
				TextSize = 84,
				TextXAlignment = Enum.TextXAlignment.Left,
				[Children] = {
					scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = 5,
					},
					scope:New "UIGradient" {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromHex("#FFF3A6")),
							ColorSequenceKeypoint.new(0.55, Color3.fromHex("#FFD23F")),
							ColorSequenceKeypoint.new(1, Color3.fromHex("#FF8A3D")),
						}),
						Rotation = 90,
					},
				},
			},
			scope:New "TextLabel" {
				Name = "Tagline",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(LEFT, 112),
				Size = UDim2.fromOffset(560, 26),
				Text = "16 бойцов · 20 боссов · бои 1 на 1 и 2 на 2",
				TextColor3 = Theme.Colors.Text,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Left,
				[Children] = scope:New "UIStroke" {
					Color = Theme.Colors.Outline,
					Thickness = 2,
					Transparency = 0.3,
				},
			},
			Pill(scope, {
				Name = "Coins",
				Icon = "🪙",
				Text = scope:Computed(function(use)
					return Format.number(use(state.coins))
				end),
				TextColor = Theme.Colors.Coins,
				Height = 36,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -24, 0, 22),
			}),
			items,
			fighterPreview,
		} :: { Fusion.Child },
	}
end

return MainMenu
