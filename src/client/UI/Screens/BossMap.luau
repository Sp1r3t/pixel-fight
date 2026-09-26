--!strict
--[[
	Экран «Башня боссов» — одиночный режим.
	  • сетка из 20 боссов: пройденные (✓), следующий открытый (пульсирующая рамка), закрытые (силуэт);
	    цвет рамки — тир сложности;
	  • панель выбранного босса: портрет в его цветах, описание, механики, бонус HP, стиль, награда;
	  • ваш боец (кнопка «Сменить» → выбор бойца) и кнопка «В бой» (неактивна, если босс закрыт).
	Прогресс (bossProgress, bossClears, coins) приходит с сервера — экран только показывает его.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Types = require(ReplicatedStorage.Shared.Types)
local AiDifficulty = require(ReplicatedStorage.Shared.Config.AiDifficulty)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local PixelFigure = require(script.Parent.Parent.Components.PixelFigure)
local ScreenHeader = require(script.Parent.Parent.Components.ScreenHeader)

local Children, OnEvent = Fusion.Children, Fusion.OnEvent

type Scope = Fusion.Scope<typeof(Fusion)>
type BossDef = Types.BossDef

export type BossStatus = "Cleared" | "Next" | "Locked"

local TIER_COLORS: { [string]: Color3 } = {
	Easy = Color3.fromHex("#5BD17A"),
	Medium = Color3.fromHex("#4DC3FF"),
	Hard = Color3.fromHex("#FFB020"),
	VeryHard = Color3.fromHex("#FF4D6D"),
	Final = Color3.fromHex("#C77DFF"),
}

-- Силуэт закрытого босса.
local LOCKED_PALETTE: Types.Palette = { primary = "#2A2440", secondary = "#3A3550", accent = "#1F1838" }

local CARD_SIZE = Vector2.new(100, 92)

-- Статус босса для игрока с прогрессом progress (пройдено по порядку).
local function statusOf(boss: BossDef, progress: number): BossStatus
	if boss.order <= progress then
		return "Cleared"
	elseif boss.order == progress + 1 then
		return "Next"
	end
	return "Locked"
end

local function tierColor(boss: BossDef): Color3
	return TIER_COLORS[BossRegistry.tierOf(boss.order).id] or Theme.Colors.Accent
end

local function BossCard(scope: Scope, boss: BossDef, state: AppState.AppState, now: Fusion.Value<number>): Instance
	local status = scope:Computed(function(use): string
		return statusOf(boss, use(state.bossProgress))
	end)
	local isSelected = scope:Computed(function(use)
		return use(state.selectedBossId) == boss.id
	end)
	local color = tierColor(boss)

	local portrait = scope:Computed(function(use, innerScope: Scope): Instance
		local locked = use(status) == "Locked"
		return PixelFigure(innerScope, {
			Palette = if locked then LOCKED_PALETTE else boss.palette,
			Size = UDim2.fromOffset(52, 52),
			Position = UDim2.fromOffset(24, 14),
		})
	end)

	return scope:New "TextButton" {
		Name = `Boss_{boss.id}`,
		AutoButtonColor = false,
		BackgroundColor3 = scope:Computed(function(use)
			return if use(isSelected) then Theme.Colors.PanelLight else Theme.Colors.Panel
		end),
		BorderSizePixel = 0,
		LayoutOrder = boss.order,
		Text = "",

		[OnEvent "Activated"] = function()
			state.selectedBossId:set(boss.id)
		end,

		[Children] = {
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = scope:Computed(function(use)
					return if use(isSelected) then Theme.Colors.Text else color
				end),
				Thickness = scope:Computed(function(use)
					if use(isSelected) then
						return 4
					elseif use(status) == "Next" then
						-- Следующий босс «пульсирует».
						return 2 + 1.5 * (1 + math.sin(use(now) * 5))
					end
					return 2
				end),
				Transparency = scope:Computed(function(use)
					return if use(status) == "Locked" then 0.5 else 0
				end),
			},
			scope:New "TextLabel" {
				Name = "Order",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(6, 2),
				Size = UDim2.fromOffset(30, 18),
				Text = tostring(boss.order),
				TextColor3 = color,
				TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			portrait,
			scope:New "TextLabel" {
				Name = "BossName",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(2, 68),
				Size = UDim2.new(1, -4, 0, 18),
				Text = scope:Computed(function(use)
					return if use(status) == "Locked" then "???" else string.upper(boss.name)
				end),
				TextColor3 = scope:Computed(function(use)
					return if use(status) == "Locked" then Theme.Colors.TextDim else Theme.Colors.Text
				end),
				TextScaled = true,
			},
			scope:New "TextLabel" {
				Name = "Cleared",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = Theme.Colors.Free,
				BorderSizePixel = 0,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(20, 20),
				Text = "✓",
				TextColor3 = Theme.Colors.Outline,
				TextSize = 16,
				Visible = scope:Computed(function(use)
					return use(status) == "Cleared"
				end),
			},
			scope:New "TextLabel" {
				Name = "Lock",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(50, 40),
				Size = UDim2.fromOffset(40, 40),
				Text = "?",
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 36,
				Visible = scope:Computed(function(use)
					return use(status) == "Locked"
				end),
			},
		} :: { Fusion.Child },
	}
end

type LineProps = {
	Color: Color3?,
	Size: number?,
	Font: Enum.Font?,
	Name: string?,
}

local function Line(scope: Scope, text: Fusion.UsedAs<string>, order: number, props: LineProps?): Instance
	local options: LineProps = props or {}
	return scope:New "TextLabel" {
		Name = options.Name or "Line",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = options.Font or Theme.Fonts.BodyRegular,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		Text = text,
		TextColor3 = options.Color or Theme.Colors.Text,
		TextSize = options.Size or 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
end

local function DetailsPanel(scope: Scope, boss: BossDef, state: AppState.AppState): Instance
	local status = scope:Computed(function(use): string
		return statusOf(boss, use(state.bossProgress))
	end)
	local tier = BossRegistry.tierOf(boss.order)
	local style = AiDifficulty.styles[boss.ai.style]
	local isMirror = table.find(boss.mechanics, "Mirror") ~= nil
	local moveset = CharacterRegistry.get(boss.character)
	local hpBonus = math.floor((boss.hpMultiplier - 1) * 100 + 0.5)

	local info: { Instance } = {
		Line(
			scope,
			`Сложность: {tier.name}`,
			1,
			{ Color = tierColor(boss), Font = Theme.Fonts.Body, Size = 16 }
		),
		Line(scope, boss.description, 2, { Color = Theme.Colors.TextDim }),
		Line(
			scope,
			`Стиль: {if style then style.name else boss.ai.style} · Приёмы: {if isMirror
				then "ваш боец"
				elseif moveset then moveset.displayName
				else boss.character} · HP {if hpBonus > 0 then `+{hpBonus}%` else "обычное"}`,
			3
		),
	}
	for index, mechanic in boss.mechanics do
		local mechanicInfo = BossRegistry.MECHANICS[mechanic]
		if mechanicInfo then
			table.insert(
				info,
				Line(
					scope,
					`◆ {mechanicInfo.name}: {mechanicInfo.description}`,
					3 + index,
					{ Color = Theme.Colors.Accent }
				)
			)
		end
	end
	table.insert(
		info,
		Line(
			scope,
			scope:Computed(function(use)
				local wins = use(state.bossClears)[boss.id] or 0
				local current = use(status)
				if current == "Locked" then
					return `Закрыт: сначала победите босса {boss.order - 1}`
				elseif wins > 0 then
					return `Пройден ✓ (побед: {wins})`
				end
				return `Награда за первую победу: {boss.reward} монет`
			end),
			20,
			{ Name = "Status", Font = Theme.Fonts.Body }
		)
	)

	local fighterName = scope:Computed(function(use)
		local def = CharacterRegistry.get(use(state.selectedCharacterId))
		return `Ваш боец: {if def then def.displayName else "?"}`
	end)

	return scope:New "Frame" {
		Name = "BossDetails",
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(576, 76),
		Size = UDim2.fromOffset(360, 448),
		[Children] = {
			scope:New "UIStroke" {
				Color = tierColor(boss),
				Thickness = Theme.Outline,
			},
			PixelFigure(scope, {
				Palette = boss.palette,
				Size = UDim2.fromOffset(96, 96),
				Position = UDim2.fromOffset(12, 10),
			}),
			scope:New "TextLabel" {
				Name = "BossTitle",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(118, 16),
				Size = UDim2.fromOffset(230, 30),
				Text = string.upper(boss.name),
				TextColor3 = Theme.Colors.Text,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			scope:New "TextLabel" {
				Name = "Subtitle",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(118, 50),
				Size = UDim2.fromOffset(230, 22),
				Text = `Босс {boss.order} — {boss.title}`,
				TextColor3 = Color3.fromHex(boss.palette.accent),
				TextSize = 16,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			scope:New "Frame" {
				Name = "Info",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(14, 112),
				Size = UDim2.fromOffset(332, 230),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					info,
				} :: { Fusion.Child },
			},
			scope:New "TextLabel" {
				Name = "Fighter",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(14, 352),
				Size = UDim2.fromOffset(200, 32),
				Text = fighterName,
				TextColor3 = Theme.Colors.Text,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			Button(scope, {
				Name = "ChangeFighter",
				Text = "Сменить",
				Position = UDim2.fromOffset(226, 350),
				Size = UDim2.fromOffset(120, 36),
				TextSize = 16,
				OnClick = function()
					AppState.navigate(state, "CharacterSelect")
				end,
			}),
			Button(scope, {
				Name = "FightBoss",
				Text = "В БОЙ",
				Color = Theme.Colors.ButtonPrimary,
				Disabled = scope:Computed(function(use)
					return use(status) == "Locked"
				end),
				Position = UDim2.fromOffset(14, 394),
				Size = UDim2.fromOffset(332, 44),
				OnClick = function()
					if statusOf(boss, Fusion.peek(state.bossProgress)) ~= "Locked" then
						state.actions.startBoss(boss.id)
					else
						AppState.notify(state, `Сначала победите босса {boss.order - 1}`)
					end
				end,
			}),
		} :: { Fusion.Child },
	}
end

local function BossMap(scope: Scope, state: AppState.AppState): Instance
	-- Общие «часы» для анимаций экрана; соединение удаляется вместе со scope экрана.
	local now = scope:Value(os.clock())
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function()
			now:set(os.clock())
		end)
	)

	local cards: { Instance } = {}
	for _, boss in BossRegistry.list() do
		table.insert(cards, BossCard(scope, boss, state, now))
	end

	return scope:New "Frame" {
		Name = "BossMap",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			ScreenHeader(scope, {
				Title = "БАШНЯ БОССОВ",
				OnBack = function()
					AppState.back(state)
				end,
			}),
			scope:New "TextLabel" {
				Name = "Progress",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(1, -20, 0, 12),
				Size = UDim2.fromOffset(170, 20),
				Text = scope:Computed(function(use)
					return `Пройдено: {use(state.bossProgress)} / {BossRegistry.count()}`
				end),
				TextColor3 = Theme.Colors.Text,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Right,
			},
			scope:New "TextLabel" {
				Name = "Coins",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(1, -20, 0, 34),
				Size = UDim2.fromOffset(170, 20),
				Text = scope:Computed(function(use)
					return `Монеты: {use(state.coins)}`
				end),
				TextColor3 = Theme.Colors.Accent,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Right,
			},
			scope:New "Frame" {
				Name = "Tower",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(24, 80),
				Size = UDim2.fromOffset(532, 392),
				[Children] = {
					scope:New "UIGridLayout" {
						CellPadding = UDim2.fromOffset(8, 8),
						CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					cards,
				} :: { Fusion.Child },
			},
			scope:New "TextLabel" {
				Name = "Legend",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.BodyRegular,
				Position = UDim2.fromOffset(24, 480),
				Size = UDim2.fromOffset(532, 40),
				Text = "Боссы открываются по порядку. Бой до 3 побед. Цвет рамки — сложность: "
					.. "зелёный · синий · оранжевый · красный · фиолетовый.",
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 13,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			},
			scope:Computed(function(use, innerScope: Scope): Instance?
				local boss = BossRegistry.get(use(state.selectedBossId))
				if boss == nil then
					return nil
				end
				return DetailsPanel(innerScope, boss, state)
			end),
		} :: { Fusion.Child },
	}
end

return BossMap
