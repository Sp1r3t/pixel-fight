--!strict
--[[
	Главное меню: строгий список режимов, дополнительные разделы и выбранный боец справа.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Combos = require(ReplicatedStorage.Shared.Config.Combos)
local TestMode = require(ReplicatedStorage.Shared.Config.TestMode)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Format = require(script.Parent.Parent.Format)
local Button = require(script.Parent.Parent.Components.Button)
local ModeCard = require(script.Parent.Parent.Components.ModeCard)
local IconGlyph = require(script.Parent.Parent.Components.IconGlyph)
local Pill = require(script.Parent.Parent.Components.Pill)
local Panel = require(script.Parent.Parent.Components.Panel)
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
		icon = "castle",
		subtitle = "Путь через 20 противников",
		color = Theme.Colors.ButtonPrimary,
		screen = "BossMap",
	},
	{
		text = "Мультиплеер",
		icon = "swords",
		subtitle = "1 на 1 · 2 на 2",
		color = Theme.Colors.Info,
		screen = "ModeSelect",
	},
	{
		text = "Тренировка",
		icon = "belt",
		subtitle = "Пробуй приёмы",
		color = Theme.Colors.Success,
		action = function(state: AppState.AppState)
			state.actions.startTraining()
		end,
	},
}

-- Остальное — кнопки поменьше.
local MORE: { MenuEntry } = {
	{ text = "Персонажи", icon = "hero", color = Theme.Colors.Button, screen = "CharacterSelect" },
	{ text = "Магазин", icon = "cart", color = Theme.Colors.Button, screen = "Shop" },
	{ text = "Управление", icon = "gamepad", color = Theme.Colors.Button, screen = "ControlsSettings" },
}

type Tip = { icon: string, text: ({ [string]: string }) -> string }

-- Отдельные советы для клавиатуры, телефона и геймпада. Клавиши берутся из активных биндов.
local TIPS: { [string]: { Tip } } = {
	Keyboard = {
		{
			icon = "dash",
			text = function(b)
				return `Двигайся: {b.Move}. Присесть: {b.Crouch}.`
			end,
		},
		{
			icon = "shield",
			text = function(b)
				return `Удерживай {b.Block} для блока.`
			end,
		},
		{
			icon = "lightning",
			text = function(b)
				return `Шкала SUPER полная? Нажми {b.Super}.`
			end,
		},
		{
			icon = "dash",
			text = function(b)
				return `Нажми {b.Dash}, чтобы сделать рывок.`
			end,
		},
		{
			icon = "punch",
			text = function(b)
				return `Простое комбо: {b.Light}, {b.Light}, {b.Heavy}.`
			end,
		},
		{
			icon = "arrow_up",
			text = function(b)
				return `В 2 на 2 нажми {b.Jump} ещё раз в воздухе.`
			end,
		},
		{
			icon = "special",
			text = function(b)
				return `Особый приём твоего бойца — клавиша {b.Special}.`
			end,
		},
	},
	Touch = {
		{
			icon = "joystick",
			text = function(_b)
				return "Двигай джойстик влево и вправо. Потяни вниз, чтобы присесть."
			end,
		},
		{
			icon = "shield",
			text = function(_b)
				return "Удерживай пиксельную кнопку щита для блока."
			end,
		},
		{
			icon = "lightning",
			text = function(_b)
				return "Шкала SUPER полная? Нажми кнопку молнии."
			end,
		},
		{
			icon = "dash",
			text = function(_b)
				return "Дважды быстро толкни джойстик в сторону для рывка."
			end,
		},
		{
			icon = "punch",
			text = function(_b)
				return "Комбо: дважды кнопка руки, затем кнопка ноги."
			end,
		},
		{
			icon = "arrow_up",
			text = function(_b)
				return "В 2 на 2 нажми кнопку прыжка ещё раз в воздухе."
			end,
		},
		{
			icon = "special",
			text = function(_b)
				return "Кнопка звезды запускает особый приём бойца."
			end,
		},
	},
	Gamepad = {
		{
			icon = "gamepad",
			text = function(b)
				return `Двигайся: {b.Move}. Присесть: {b.Crouch}.`
			end,
		},
		{
			icon = "shield",
			text = function(b)
				return `Удерживай {b.Block} для блока.`
			end,
		},
		{
			icon = "lightning",
			text = function(b)
				return `Шкала SUPER полная? Нажми {b.Super}.`
			end,
		},
		{
			icon = "dash",
			text = function(b)
				return `Нажми {b.Dash}, чтобы сделать рывок.`
			end,
		},
		{
			icon = "punch",
			text = function(b)
				return `Простое комбо: {b.Light}, {b.Light}, {b.Heavy}.`
			end,
		},
		{
			icon = "arrow_up",
			text = function(b)
				return `В 2 на 2 нажми {b.Jump} ещё раз в воздухе.`
			end,
		},
		{
			icon = "special",
			text = function(b)
				return `Особый приём твоего бойца — кнопка {b.Special}.`
			end,
		},
	},
}
local TIP_SECONDS = 7

local TILE_W, GAP = 180, 12
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

local function TipBar(scope: Scope, state: AppState.AppState): Instance
	local index = scope:Value(math.random(1, #TIPS.Keyboard))
	local elapsed = 0
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function(dt: number)
			elapsed += dt
			if elapsed >= TIP_SECONDS then
				elapsed = 0
				local platformTips = TIPS[Fusion.peek(state.platform)] or TIPS.Keyboard
				index:set(Fusion.peek(index) % #platformTips + 1)
			end
		end)
	)
	return Panel(scope, {
		Name = "Tips",
		Position = UDim2.fromOffset(LEFT, 462),
		Size = UDim2.fromOffset(TILE_W * 2 + GAP, 58),
		Transparency = 0.15,
		Content = {
			IconGlyph(scope, {
				Id = scope:Computed(function(use)
					local platformTips = TIPS[use(state.platform)] or TIPS.Keyboard
					return platformTips[math.min(use(index), #platformTips)].icon
				end),
				Name = "Bulb",
				Color = Theme.Colors.Accent,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10, 0.5, 0),
				Size = UDim2.fromOffset(34, 34),
			}),
			scope:New "TextLabel" {
				Name = "Tip",
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(0, 52, 0.5, 0),
				Size = UDim2.new(1, -64, 1, -10),
				Text = scope:Computed(function(use)
					local platformTips = TIPS[use(state.platform)] or TIPS.Keyboard
					local tip = platformTips[math.min(use(index), #platformTips)]
					return tip.text(use(state.inputBindings))
				end),
				TextColor3 = Theme.Colors.Text,
				TextScaled = true,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 17 },
			},
		},
	})
end

local function MainMenu(scope: Scope, state: AppState.AppState): Instance
	local items: { Instance } = {}
	for index, entry in MAIN do
		table.insert(
			items,
			ModeCard(scope, {
				Name = `Tile{index}`,
				Text = entry.text,
				Icon = entry.icon,
				Subtitle = entry.subtitle,
				Color = entry.color,
				Campaign = index == 1,
				Position = if index == 1
					then UDim2.fromOffset(LEFT, TOP)
					else UDim2.fromOffset(LEFT + (index - 2) * 288, 292),
				Size = if index == 1 then UDim2.fromOffset(564, 120) else UDim2.fromOffset(276, 104),
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
				Position = UDim2.fromOffset(LEFT + (index - 1) * (TILE_W + GAP), 410),
				Size = UDim2.fromOffset(TILE_W, 38),
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
					Palette = AppState.skinPalette(state, use, def.id),
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
						Thickness = 1,
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
					Icon = "refresh",
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
				TextSize = 64,
				TextXAlignment = Enum.TextXAlignment.Left,
				[Children] = {
					scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = 1,
					},
					scope:New "UIGradient" {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Theme.Colors.Text),
							ColorSequenceKeypoint.new(0.55, Theme.Colors.Accent),
							ColorSequenceKeypoint.new(1, Theme.Colors.Paid),
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
				Text = if TestMode.UnlockAllCharacters
					then "ТЕСТ: все 16 бойцов открыты"
					else "16 бойцов · 20 боссов · бои 1 на 1 и 2 на 2",
				TextColor3 = Theme.Colors.Text,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Left,
				[Children] = scope:New "UIStroke" {
					Color = Theme.Colors.Outline,
					Thickness = 2,
					Transparency = 0.3,
				},
			},
			-- Справа сверху: подарок дня, кристаллы и монеты (строка прижата к правому краю).
			scope:New "Frame" {
				Name = "Wallet",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Position = UDim2.new(1, -24, 0, 22),
				Size = UDim2.fromOffset(320, 40),
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					},
					Button(scope, {
						Name = "Daily",
						Text = "",
						Icon = "gift",
						IconOnly = true,
						Color = Theme.Colors.Button,
						Badge = scope:Computed(function(use)
							return if AppState.dailyAvailable(use(state.daily), os.time()) then "!" else ""
						end),
						Disabled = scope:Computed(function(use)
							return not AppState.dailyAvailable(use(state.daily), os.time())
						end),
						LayoutOrder = 1,
						Size = UDim2.fromOffset(52, 40),
						TextSize = 22,
						OnClick = function()
							state.actions.claimDaily()
						end,
					}),
					Pill(scope, {
						Name = "Crystals",
						Icon = "crystal",
						Text = scope:Computed(function(use)
							return Format.number(use(state.crystals))
						end),
						TextColor = Theme.Colors.Crystals,
						Height = 36,
						LayoutOrder = 2,
					}),
					Pill(scope, {
						Name = "Coins",
						Icon = "coin",
						Text = scope:Computed(function(use)
							return Format.number(use(state.coins))
						end),
						TextColor = Theme.Colors.Coins,
						Height = 36,
						LayoutOrder = 3,
					}),
				},
			},
			items,
			TipBar(scope, state),
			Button(scope, {
				Name = "Combos",
				Text = "Комбо",
				Icon = "scroll",
				Color = Theme.Colors.Button,
				Badge = scope:Computed(function(use)
					local count = 0
					for id in use(state.combosFound) do
						if Combos.byId[id] then
							count += 1
						end
					end
					return `{count}/{#Combos.list}`
				end),
				TextSize = 19,
				Position = UDim2.fromOffset(LEFT + (TILE_W + GAP) * 2, 462),
				Size = UDim2.fromOffset(TILE_W, 58),
				OnClick = function()
					AppState.navigate(state, "ComboList")
				end,
			}),
			fighterPreview,
		} :: { Fusion.Child },
	}
end

return MainMenu
