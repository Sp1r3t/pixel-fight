--!strict
--[[
	Выбор персонажа: сетка из 16 бойцов + панель с живым превью, характеристиками и приёмами.
	Данные берутся из Config/Characters через CharacterRegistry — экран сам ничего не хранит.
	Платного персонажа, которого ещё нет, кнопка ведёт в магазин (Game Pass или монеты).

	Раскладка без наложений: карточка — портрет по пояс и имя внизу, метки (выбран ✓, замок 🔒)
	в правом верхнем углу поверх рамки, а не на лице; в панели всё, что может быть длинным,
	лежит в прокручиваемом списке.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Types = require(ReplicatedStorage.Shared.Types)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local Panel = require(script.Parent.Parent.Components.Panel)
local Pill = require(script.Parent.Parent.Components.Pill)
local FighterPortrait = require(script.Parent.Parent.Components.FighterPortrait)
local ScreenHeader = require(script.Parent.Parent.Components.ScreenHeader)
local StatBar = require(script.Parent.Parent.Components.StatBar)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>
type CharacterDef = Types.CharacterDef

local ARCHETYPE_NAMES: { [Types.Archetype]: string } = {
	AllRounder = "Универсал",
	Rushdown = "Напор",
	Grappler = "Борец",
	Zoner = "Зонер",
	Assassin = "Ассасин",
	Bruiser = "Громила",
	Aerial = "Воздушный бой",
	Counter = "Контратака",
	Spacer = "Контроль дистанции",
	Speedster = "Скорость",
	Trapper = "Ловушки",
}

local STAT_COLORS = table.freeze({
	health = Color3.fromHex("#5BD17A"),
	damage = Color3.fromHex("#FF4D6D"),
	speed = Color3.fromHex("#4DC3FF"),
	range = Color3.fromHex("#C77DFF"),
	superGain = Color3.fromHex("#FFC845"),
})

local CARD = 102

local function multiplierText(value: number): string
	return string.format("×%.2f", value)
end

local function Label(
	scope: Scope,
	props: {
		Text: string,
		Font: Enum.Font,
		TextSize: number,
		Color: Color3,
		LayoutOrder: number?,
		Wrapped: boolean?,
	}
): Instance
	return scope:New "TextLabel" {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = props.Font,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.fromScale(1, 0),
		Text = props.Text,
		TextColor3 = props.Color,
		TextSize = props.TextSize,
		TextWrapped = props.Wrapped == true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
end

-- Круглая метка в углу карточки (✓ выбран, 🔒 закрыт).
local function CornerMark(
	scope: Scope,
	props: { Name: string, Text: string, Color: Color3, Visible: Fusion.UsedAs<boolean> }
): Instance
	return scope:New "TextLabel" {
		Name = props.Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = props.Color,
		Font = Theme.Fonts.Title,
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(24, 24),
		Text = props.Text,
		TextColor3 = Theme.Colors.Outline,
		TextSize = 15,
		Visible = props.Visible,
		ZIndex = 8,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Colors.Outline,
				Thickness = 2,
			},
		},
	}
end

local function RosterCard(
	scope: Scope,
	def: CharacterDef,
	viewingId: Fusion.Value<string>,
	now: Fusion.Value<number>,
	state: AppState.AppState
): Instance
	local isViewing = scope:Computed(function(use)
		return use(viewingId) == def.id
	end)
	local isChosen = scope:Computed(function(use)
		return use(state.selectedCharacterId) == def.id
	end)
	local isOwned = scope:Computed(function(use)
		return use(state.ownedCharacters)[def.id] == true
	end)
	local deluxe = def.cosmetics.tier == "Deluxe"
	local accent = Color3.fromHex(def.palette.accent)

	-- Платные персонажи выглядят эффектнее: переливающаяся рамка-аура (пока карточку не выбрали).
	local strokeChildren = scope:Computed(function(use, innerScope: Scope): { Instance }
		if not deluxe or use(isViewing) then
			return {}
		end
		return {
			innerScope:New "UIGradient" {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, accent),
					ColorSequenceKeypoint.new(0.5, Color3.fromHex(def.palette.primary)),
					ColorSequenceKeypoint.new(1, accent),
				}),
				Rotation = innerScope:Computed(function(innerUse)
					return (innerUse(now) * 120) % 360
				end),
			},
		}
	end)

	return scope:New "TextButton" {
		Name = def.id,
		AutoButtonColor = false,
		BackgroundColor3 = accent:Lerp(Theme.Colors.Panel, 0.78),
		BorderSizePixel = 0,
		LayoutOrder = def.order,
		Text = "",

		[OnEvent "Activated"] = function()
			viewingId:set(def.id)
		end,

		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			scope:New "UIScale" {
				Scale = scope:Spring(
					scope:Computed(function(use)
						return if use(isViewing) then 1.06 else 1
					end),
					25,
					0.7
				),
			},
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = scope:Computed(function(use)
					if use(isViewing) then
						return Theme.Colors.Accent
					end
					-- У Deluxe цвет рамки задаёт UIGradient.
					return if deluxe then Color3.new(1, 1, 1) else Theme.Colors.Outline
				end),
				Thickness = scope:Spring(
					scope:Computed(function(use)
						return if use(isViewing) then 4 else 3
					end),
					30,
					1
				),
				[Children] = strokeChildren,
			},
			FighterPortrait(scope, {
				Character = def,
				Framing = "Bust",
				Size = UDim2.fromOffset(CARD - 14, CARD - 14),
				Position = UDim2.new(0.5, 0, 0, 2),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = 2,
			}),
			-- Полоса с именем внизу.
			scope:New "Frame" {
				Name = "NameStrip",
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Theme.Colors.Outline,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 22),
				ZIndex = 4,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
					scope:New "TextLabel" {
						Name = "Name",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Pixel,
						Position = UDim2.fromOffset(4, 2),
						Size = UDim2.new(1, -8, 1, -4),
						Text = string.upper(def.displayName),
						TextColor3 = Theme.Colors.Text,
						TextScaled = true,
						ZIndex = 5,
						[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 16 },
					},
				},
			},
			scope:New "Frame" {
				Name = "LockedShade",
				BackgroundColor3 = Theme.Colors.Outline,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				Visible = scope:Computed(function(use)
					return not use(isOwned)
				end),
				ZIndex = 6,
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			},
			CornerMark(scope, {
				Name = "ChosenMark",
				Text = "✓",
				Color = Theme.Colors.Accent,
				Visible = isChosen,
			}),
			CornerMark(scope, {
				Name = "LockMark",
				Text = "🔒",
				Color = Theme.Colors.Paid,
				Visible = scope:Computed(function(use)
					return not use(isOwned)
				end),
			}),
		},
	}
end

local function DetailsPanel(scope: Scope, def: CharacterDef, state: AppState.AppState): Instance
	local derived = CharacterRegistry.getDerivedStats(def)
	local isOwned = scope:Computed(function(use)
		return use(state.ownedCharacters)[def.id] == true
	end)
	local isChosen = scope:Computed(function(use)
		return use(state.selectedCharacterId) == def.id
	end)

	local stats: { { label: string, rating: number, value: string, color: Color3 } } = {
		{
			label = "Здоровье",
			rating = def.stats.health,
			value = `{derived.maxHealth} HP`,
			color = STAT_COLORS.health,
		},
		{
			label = "Урон",
			rating = def.stats.damage,
			value = multiplierText(derived.damageMultiplier),
			color = STAT_COLORS.damage,
		},
		{
			label = "Скорость",
			rating = def.stats.speed,
			value = `{derived.walkSpeed} ст/с`,
			color = STAT_COLORS.speed,
		},
		{
			label = "Дальность",
			rating = def.stats.range,
			value = multiplierText(derived.rangeMultiplier),
			color = STAT_COLORS.range,
		},
		{
			label = "Супер",
			rating = def.stats.superGain,
			value = multiplierText(derived.superGainMultiplier),
			color = STAT_COLORS.superGain,
		},
	}
	local statBars: { Instance } = {}
	for index, stat in stats do
		table.insert(
			statBars,
			StatBar(scope, {
				Label = stat.label,
				Rating = stat.rating,
				ValueText = stat.value,
				Color = stat.color,
				LayoutOrder = 10 + index,
			})
		)
	end

	local accent = Color3.fromHex(def.palette.accent)
	local paid = def.unlock == "Paid"

	return Panel(scope, {
		Name = "Details",
		Position = UDim2.fromOffset(472, 76),
		Size = UDim2.fromOffset(464, 444),
		StrokeColor = accent:Lerp(Theme.Colors.Outline, 0.35),
		Content = {
			-- Живое превью: боец по кругу показывает удары, приём, супер и победу.
			scope:New "Frame" {
				Name = "Stage",
				BackgroundColor3 = accent:Lerp(Theme.Colors.Outline, 0.72),
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(12, 12),
				Size = UDim2.fromOffset(150, 150),
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.Colors.Outline,
						Thickness = 2,
					},
					FighterPortrait(scope, {
						Character = def,
						Framing = "Full",
						Showcase = true,
						Size = UDim2.fromScale(1, 1),
					}),
				},
			},
			scope:New "Frame" {
				Name = "Identity",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(176, 14),
				Size = UDim2.new(1, -188, 0, 146),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 4),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:New "TextLabel" {
						Name = "Name",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Pixel,
						LayoutOrder = 1,
						Size = UDim2.new(1, 0, 0, 36),
						Text = string.upper(def.displayName),
						TextColor3 = Theme.Colors.Text,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 34 },
					},
					scope:New "TextLabel" {
						Name = "Title",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Pixel,
						LayoutOrder = 2,
						Size = UDim2.new(1, 0, 0, 22),
						Text = def.title,
						TextColor3 = accent,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 20 },
					},
					scope:New "Frame" {
						Name = "Tags",
						BackgroundTransparency = 1,
						LayoutOrder = 3,
						Size = UDim2.new(1, 0, 0, 28),
						[Children] = {
							scope:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								Padding = UDim.new(0, 6),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							Pill(scope, {
								Name = "Role",
								Text = ARCHETYPE_NAMES[def.archetype],
								Color = Theme.Colors.PanelLight,
								Height = 26,
								TextSize = 15,
								LayoutOrder = 1,
							}),
							Pill(scope, {
								Name = "Unlock",
								Icon = if paid then "👑" else nil,
								Text = if paid then "Deluxe" else "Бесплатный",
								Color = if paid then Theme.Colors.Paid else Theme.Colors.Success,
								TextColor = Theme.Colors.Outline,
								Height = 26,
								TextSize = 15,
								LayoutOrder = 2,
							}),
						},
					},
					scope:New "TextLabel" {
						Name = "Fairness",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.BodyRegular,
						LayoutOrder = 4,
						Size = UDim2.new(1, 0, 0, 36),
						Text = if paid
							then "Сила как у всех: платный боец отличается только видом."
							else "Доступен сразу.",
						TextColor3 = Theme.Colors.TextDim,
						TextSize = 14,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
					},
				},
			},
			scope:New "ScrollingFrame" {
				Name = "Body",
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				Position = UDim2.fromOffset(14, 172),
				ScrollBarImageColor3 = accent,
				ScrollBarThickness = 5,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				Size = UDim2.new(1, -24, 1, -240),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 5),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:New "UIPadding" {
						PaddingRight = UDim.new(0, 10),
					},
					Label(scope, {
						Text = def.style,
						Font = Theme.Fonts.BodyRegular,
						TextSize = 15,
						Color = Theme.Colors.Text,
						LayoutOrder = 1,
						Wrapped = true,
					}),
					statBars,
					Label(scope, {
						Text = `✨ ОСОБЫЙ ПРИЁМ · {def.special.move.name}`,
						Font = Theme.Fonts.Title,
						TextSize = 16,
						Color = accent,
						LayoutOrder = 20,
						Wrapped = true,
					}),
					Label(scope, {
						Text = def.special.description,
						Font = Theme.Fonts.BodyRegular,
						TextSize = 14,
						Color = Theme.Colors.Text,
						LayoutOrder = 21,
						Wrapped = true,
					}),
					Label(scope, {
						Text = `⚡ СУПЕР · {def.super.move.name}`,
						Font = Theme.Fonts.Title,
						TextSize = 16,
						Color = accent,
						LayoutOrder = 22,
						Wrapped = true,
					}),
					Label(scope, {
						Text = def.super.description,
						Font = Theme.Fonts.BodyRegular,
						TextSize = 14,
						Color = Theme.Colors.Text,
						LayoutOrder = 23,
						Wrapped = true,
					}),
				} :: { Fusion.Child },
			},
			Button(scope, {
				Name = "ChooseButton",
				Text = scope:Computed(function(use)
					if not use(isOwned) then
						return "Открыть в магазине"
					end
					return if use(isChosen) then "Выбран" else "Выбрать"
				end),
				Icon = scope:Computed(function(use)
					if not use(isOwned) then
						return "🔒"
					end
					return if use(isChosen) then "✅" else "👊"
				end),
				Disabled = scope:Computed(function(use)
					return use(isOwned) and use(isChosen)
				end),
				Color = scope:Computed(function(use)
					return if use(isOwned) then Theme.Colors.ButtonPrimary else Color3.fromHex("#E08A1E")
				end),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.fromOffset(260, 52),
				OnClick = function()
					if peek(isOwned) then
						state.selectedCharacterId:set(def.id)
					else
						AppState.navigate(state, "Shop")
					end
				end,
			}),
		},
	})
end

local function CharacterSelect(scope: Scope, state: AppState.AppState): Instance
	local viewingId = scope:Value(peek(state.selectedCharacterId))

	-- Общие «часы» для анимаций экрана; соединение удаляется вместе со scope экрана.
	local now = scope:Value(os.clock())
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function()
			now:set(os.clock())
		end)
	)

	local cards: { Instance } = {}
	for _, def in CharacterRegistry.list() do
		table.insert(cards, RosterCard(scope, def, viewingId, now, state))
	end

	return scope:New "Frame" {
		Name = "CharacterSelect",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			ScreenHeader(scope, {
				Title = "ВЫБОР БОЙЦА",
				Coins = state.coins,
				OnBack = function()
					AppState.back(state)
				end,
			}),
			scope:New "Frame" {
				Name = "Roster",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(24, 80),
				Size = UDim2.fromOffset(432, 440),
				[Children] = {
					scope:New "UIGridLayout" {
						CellPadding = UDim2.fromOffset(8, 8),
						CellSize = UDim2.fromOffset(CARD, CARD),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					cards,
				} :: { Fusion.Child },
			},
			scope:Computed(function(use, innerScope: Scope): Instance?
				local def = CharacterRegistry.get(use(viewingId))
				if def == nil then
					return nil
				end
				return DetailsPanel(innerScope, def, state)
			end),
		} :: { Fusion.Child },
	}
end

return CharacterSelect
