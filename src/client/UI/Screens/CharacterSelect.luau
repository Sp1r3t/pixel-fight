--!strict
--[[
	Выбор персонажа: сетка из 16 бойцов + панель с превью, характеристиками и приёмами.
	Данные берутся из Config/Characters через CharacterRegistry — экран сам ничего не хранит.
	Покупка платных персонажей подключится на этапе 9 (сейчас кнопка неактивна).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Types = require(ReplicatedStorage.Shared.Types)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local PixelFigure = require(script.Parent.Parent.Components.PixelFigure)
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

local function Badge(scope: Scope, def: CharacterDef, props: { Position: UDim2?, AnchorPoint: Vector2? }): Instance
	local isPaid = def.unlock == "Paid"
	return scope:New "TextLabel" {
		Name = "Badge",
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = if isPaid then Theme.Colors.Paid else Theme.Colors.Free,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Pixel,
		Position = props.Position,
		Size = UDim2.fromOffset(if isPaid then 52 else 44, 16),
		Text = if isPaid then "DELUXE" else "FREE",
		TextColor3 = Theme.Colors.Outline,
		TextSize = 14,
		ZIndex = 5,
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

	local strokeChildren: { Instance } = {}
	if def.cosmetics.tier == "Deluxe" then
		-- Платные персонажи выглядят эффектнее: переливающаяся рамка-аура.
		table.insert(
			strokeChildren,
			scope:New "UIGradient" {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromHex(def.palette.accent)),
					ColorSequenceKeypoint.new(0.5, Color3.fromHex(def.palette.primary)),
					ColorSequenceKeypoint.new(1, Color3.fromHex(def.palette.accent)),
				}),
				Rotation = scope:Computed(function(use)
					return (use(now) * 120) % 360
				end),
			}
		)
	end

	return scope:New "TextButton" {
		Name = def.id,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.PanelLight,
		BorderSizePixel = 0,
		LayoutOrder = def.order,
		Text = "",

		[OnEvent "Activated"] = function()
			viewingId:set(def.id)
		end,

		[Children] = {
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
					if def.cosmetics.tier == "Deluxe" then
						return Color3.new(1, 1, 1) -- цвет задаёт UIGradient
					end
					return if use(isViewing) then Theme.Colors.Accent else Theme.Colors.Outline
				end),
				Thickness = scope:Spring(
					scope:Computed(function(use)
						return if use(isViewing) then 4 else 2
					end),
					30,
					1
				),
				[Children] = strokeChildren,
			},
			PixelFigure(scope, {
				Palette = def.palette,
				Size = UDim2.fromOffset(70, 70),
				Position = UDim2.new(0.5, 0, 0, 6),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			scope:New "TextLabel" {
				Name = "Name",
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.new(0.5, 0, 1, -4),
				Size = UDim2.new(1, -8, 0, 18),
				Text = string.upper(def.displayName),
				TextColor3 = Theme.Colors.Text,
				TextScaled = true,
			},
			Badge(scope, def, { Position = UDim2.fromOffset(4, 4) }),
			scope:New "TextLabel" {
				Name = "ChosenMark",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = Theme.Colors.Accent,
				BorderSizePixel = 0,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(16, 16),
				Text = "✓",
				TextColor3 = Theme.Colors.Outline,
				TextSize = 14,
				Visible = isChosen,
				ZIndex = 5,
			},
			scope:New "Frame" {
				Name = "LockedShade",
				BackgroundColor3 = Theme.Colors.Outline,
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				Visible = scope:Computed(function(use)
					return not use(isOwned)
				end),
				ZIndex = 4,
			},
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
				LayoutOrder = index,
			})
		)
	end

	local accent = Color3.fromHex(def.palette.accent)
	local unlockText = if def.unlock == "Paid"
		then "платный (только косметика)"
		else "бесплатный"

	return scope:New "Frame" {
		Name = "Details",
		BackgroundColor3 = Theme.Colors.Panel,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(472, 76),
		Size = UDim2.fromOffset(464, 444),
		[Children] = {
			scope:New "UIStroke" {
				Color = Theme.Colors.Outline,
				Thickness = Theme.Outline,
			},
			PixelFigure(scope, {
				Palette = def.palette,
				Size = UDim2.fromOffset(120, 120),
				Position = UDim2.fromOffset(12, 12),
			}),
			scope:New "Frame" {
				Name = "Identity",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(144, 12),
				Size = UDim2.new(1, -156, 0, 124),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 2),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					Label(scope, {
						Text = string.upper(def.displayName),
						Font = Theme.Fonts.Pixel,
						TextSize = 32,
						Color = Theme.Colors.Text,
						LayoutOrder = 1,
					}),
					Label(scope, {
						Text = def.title,
						Font = Theme.Fonts.Pixel,
						TextSize = 20,
						Color = accent,
						LayoutOrder = 2,
					}),
					Label(scope, {
						Text = `{ARCHETYPE_NAMES[def.archetype]} · {unlockText}`,
						Font = Theme.Fonts.Body,
						TextSize = 15,
						Color = if def.unlock == "Paid" then Theme.Colors.Paid else Theme.Colors.Free,
						LayoutOrder = 3,
					}),
					Label(scope, {
						Text = def.style,
						Font = Theme.Fonts.BodyRegular,
						TextSize = 14,
						Color = Theme.Colors.TextDim,
						LayoutOrder = 4,
						Wrapped = true,
					}),
				},
			},
			scope:New "ScrollingFrame" {
				Name = "Body",
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				Position = UDim2.fromOffset(12, 144),
				ScrollBarThickness = 4,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				Size = UDim2.new(1, -24, 1, -208),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 4),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					statBars,
					Label(scope, {
						Text = `ОСОБЫЙ ПРИЁМ · {def.special.move.name}`,
						Font = Theme.Fonts.Body,
						TextSize = 16,
						Color = accent,
						LayoutOrder = 10,
					}),
					Label(scope, {
						Text = def.special.description,
						Font = Theme.Fonts.BodyRegular,
						TextSize = 14,
						Color = Theme.Colors.Text,
						LayoutOrder = 11,
						Wrapped = true,
					}),
					Label(scope, {
						Text = `СУПЕР · {def.super.move.name}`,
						Font = Theme.Fonts.Body,
						TextSize = 16,
						Color = accent,
						LayoutOrder = 12,
					}),
					Label(scope, {
						Text = def.super.description,
						Font = Theme.Fonts.BodyRegular,
						TextSize = 14,
						Color = Theme.Colors.Text,
						LayoutOrder = 13,
						Wrapped = true,
					}),
				} :: { Fusion.Child },
			},
			Button(scope, {
				Text = scope:Computed(function(use)
					if not use(isOwned) then
						return "Купить (этап 9)"
					end
					return if use(isChosen) then "Выбран" else "Выбрать"
				end),
				Disabled = scope:Computed(function(use)
					return not use(isOwned) or use(isChosen)
				end),
				Color = Theme.Colors.ButtonPrimary,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.fromOffset(240, 48),
				OnClick = function()
					if peek(isOwned) then
						state.selectedCharacterId:set(def.id)
					end
				end,
			}),
		},
	}
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
						CellSize = UDim2.fromOffset(102, 102),
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
