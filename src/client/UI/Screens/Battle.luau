--!strict
--[[
	HUD боя (поверх 3D-арены). Всё важное — в верхней полосе, низ экрана свободен для кнопок:
	  • 1 на 1 — у каждого бойца портрет, имя и победы в раундах одной строкой, под ними полоса HP
	    с задержанной белой полосой урона и шкала супера с подписью «SUPER!» сбоку; таймер по центру;
	  • 2 на 2 — две компактные строки на команду (слева синие, справа красные): портрет, имя, HP и
	    тонкая шкала супера; выбитый боец помечен «K.O.»; победы команд — по бокам от таймера;
	  • под таймером — кнопка паузы: окно «Продолжить / Как играть / Выйти» (Components/BattleOverlays,
	    слой поверх сенсорных кнопок) — случайно выйти из боя нельзя;
	  • счётчик комбо у атакующей стороны, крупные надписи раундов по центру;
	  • на ПК и геймпаде внизу — подсказка клавиш: в тренировке всегда, в бою — первые секунды.
	Верхняя полоса HUD — до y = 112 (камера держит бойцов ниже неё), комбо — ниже.
	Все данные — Fusion Values из AppState.hud, их обновляет FightController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Cosmetics = require(ReplicatedStorage.Shared.Config.Cosmetics)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local FighterPortrait = require(script.Parent.Parent.Components.FighterPortrait)
local HealthBar = require(script.Parent.Parent.Components.HealthBar)
local SuperMeter = require(script.Parent.Parent.Components.SuperMeter)
local RoundPips = require(script.Parent.Parent.Components.RoundPips)
local Banner = require(script.Parent.Parent.Components.Banner)

local Children, peek = Fusion.Children, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>

-- Подсказка клавиш: клавиши-«кнопочки» и что они делают (иконка как на сенсорных кнопках).
type Hint = { keys: { string }, text: string }

local HINTS: { [string]: { Hint } } = {
	Keyboard = {
		{ keys = { "A", "D" }, text = "ходьба" },
		{ keys = { "W" }, text = "прыжок" },
		{ keys = { "S" }, text = "присед" },
		{ keys = { "J" }, text = "👊 рука" },
		{ keys = { "K" }, text = "🦶 нога" },
		{ keys = { "L" }, text = "✨ приём" },
		{ keys = { "I" }, text = "⚡ супер" },
		{ keys = { "Q" }, text = "🛡️ блок" },
		{ keys = { "Shift" }, text = "💨 рывок" },
	},
	Gamepad = {
		{ keys = { "Стик" }, text = "ходьба" },
		{ keys = { "A" }, text = "прыжок" },
		{ keys = { "X" }, text = "👊 рука" },
		{ keys = { "Y" }, text = "🦶 нога" },
		{ keys = { "B" }, text = "✨ приём" },
		{ keys = { "RB" }, text = "⚡ супер" },
		{ keys = { "LT" }, text = "🛡️ блок" },
		{ keys = { "LB" }, text = "💨 рывок" },
	},
}
-- Сколько секунд показывать подсказку в начале боя (в тренировке — всегда).
local HINT_SECONDS = 12

local TEAM_COLORS: { Color3 } = { Color3.fromHex("#4DB8FF"), Color3.fromHex("#FF5A6E") }
-- 2 на 2: строки команды (слоты сверху вниз). Нижний этаж (1, 2) — первая строка.
local TEAM_SLOTS: { { number } } = { { 1, 3 }, { 2, 4 } }
local ROW_HEIGHT = 48
local ROW_BAR_WIDTH = 250

local HP_WIDTH = 300
local PORTRAIT = 56
local BAR_X = 16 + PORTRAIT + 10

local function fighterInfo(
	scope: Scope,
	state: AppState.AppState,
	slot: number
): Fusion.Computed<AppState.BattleFighter?>
	return scope:Computed(function(use): AppState.BattleFighter?
		local battle = use(state.battle)
		return if battle then AppState.fighterInSlot(battle, slot) else nil
	end)
end

local function superColorOf(scope: Scope, info: Fusion.Computed<AppState.BattleFighter?>): Fusion.Computed<Color3>
	return scope:Computed(function(use)
		local fighter = use(info)
		local def = if fighter then CharacterRegistry.get(fighter.characterId) else nil
		return if def then Color3.fromHex(def.cosmetics.superFlash) else Theme.Colors.Accent
	end)
end

-- Портрет бойца в рамке цвета стороны (смотрит к центру экрана).
local function PortraitFrame(
	scope: Scope,
	info: Fusion.Computed<AppState.BattleFighter?>,
	props: {
		isLeft: boolean,
		size: number,
		color: Color3,
		position: UDim2,
		knockedOut: Fusion.UsedAs<boolean>?,
	}
): Instance
	local portrait = scope:Computed(function(use, innerScope: Scope): Instance?
		local fighter = use(info)
		local def = if fighter then CharacterRegistry.get(fighter.characterId) else nil
		if fighter == nil or def == nil then
			return nil
		end
		return FighterPortrait(innerScope, {
			Character = def,
			Palette = fighter.palette,
			Framing = "Bust",
			Facing = if props.isLeft then 1 else -1,
		})
	end)
	local extras: { Instance } = {}
	if props.knockedOut ~= nil then
		table.insert(
			extras,
			scope:New "TextLabel" {
				Name = "KO",
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.35,
				Font = Theme.Fonts.Pixel,
				Size = UDim2.fromScale(1, 1),
				Text = "K.O.",
				TextColor3 = Theme.Colors.Danger,
				TextSize = 18,
				Visible = props.knockedOut,
				ZIndex = 3,
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
			}
		)
	end
	return scope:New "Frame" {
		Name = "Portrait",
		AnchorPoint = Vector2.new(if props.isLeft then 0 else 1, 0),
		BackgroundColor3 = props.color:Lerp(Theme.Colors.Panel, 0.7),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = props.position,
		Size = UDim2.fromOffset(props.size, props.size),
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = props.color,
				Thickness = 3,
			},
			portrait,
			extras,
		} :: { Fusion.Child },
	}
end

-- 1 на 1: панель бойца сверху — портрет; имя и победы; полоса HP; шкала супера.
local function FighterPanel(scope: Scope, state: AppState.AppState, slot: number, clock: Fusion.Value<number>): Instance
	local side: "Left" | "Right" = if slot == 1 then "Left" else "Right"
	local isLeft = slot == 1
	local hudFighter = state.hud.fighters[slot]
	local info = fighterInfo(scope, state, slot)

	local name = scope:Computed(function(use)
		local fighter = use(info)
		local battle = use(state.battle)
		if fighter == nil or battle == nil then
			return ""
		end
		local def = CharacterRegistry.get(fighter.characterId)
		local text = string.upper(fighter.displayName or (if def then def.displayName else fighter.characterId))
		if battle.localSlot == slot then
			text ..= " (YOU)"
		end
		if fighter.vip then
			text = "👑 " .. text
		end
		return text
	end)
	local superColor = superColorOf(scope, info)

	local function at(x: number, y: number): UDim2
		return if isLeft then UDim2.fromOffset(x, y) else UDim2.new(1, -x, 0, y)
	end
	local anchor = Vector2.new(if isLeft then 0 else 1, 0)

	return scope:New "Frame" {
		Name = `FighterPanel{slot}`,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			PortraitFrame(scope, info, {
				isLeft = isLeft,
				size = PORTRAIT,
				color = TEAM_COLORS[slot],
				position = at(16, 8),
			}),
			scope:New "TextLabel" {
				Name = "Name",
				AnchorPoint = anchor,
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = at(BAR_X, 6),
				Size = UDim2.fromOffset(HP_WIDTH - 70, 22),
				Text = name,
				TextColor3 = Theme.Colors.Text,
				TextSize = 22,
				TextStrokeTransparency = 0.2,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			},
			RoundPips(scope, {
				Wins = state.hud.wins,
				RoundsToWin = state.hud.roundsToWin,
				Slot = slot,
				Side = if isLeft then "Right" else "Left",
				AnchorPoint = Vector2.new(if isLeft then 1 else 0, 0),
				Position = at(BAR_X + HP_WIDTH, 9),
			}),
			HealthBar(scope, {
				Health = hudFighter.health,
				MaxHealth = hudFighter.maxHealth,
				Side = side,
				AnchorPoint = anchor,
				Position = at(BAR_X, 32),
				Size = UDim2.fromOffset(HP_WIDTH, 22),
			}),
			scope:Computed(function(use, innerScope: Scope): Instance
				return SuperMeter(innerScope, {
					Meter = hudFighter.meter,
					Side = side,
					Color = use(superColor),
					Clock = clock,
					AnchorPoint = anchor,
					Position = at(BAR_X, 62),
					Size = UDim2.fromOffset(190, 10),
				})
			end),
		} :: { Fusion.Child },
	}
end

-- 2 на 2: строка бойца в панели команды — портрет, имя, HP, тонкая шкала супера, отметка K.O.
local function TeamRow(
	scope: Scope,
	state: AppState.AppState,
	slot: number,
	team: number,
	row: number,
	clock: Fusion.Value<number>
): Instance
	local isLeft = team == 1
	local hudFighter = state.hud.fighters[slot]
	local info = fighterInfo(scope, state, slot)
	local knockedOut = scope:Computed(function(use)
		return use(hudFighter.health) <= 0
	end)
	local portraitSize = 40
	local barX = portraitSize + 8
	local y = 6 + (row - 1) * ROW_HEIGHT

	local name = scope:Computed(function(use)
		local fighter = use(info)
		local battle = use(state.battle)
		if fighter == nil or battle == nil then
			return ""
		end
		local def = CharacterRegistry.get(fighter.characterId)
		local text = fighter.playerName or fighter.displayName or (if def then def.displayName else fighter.characterId)
		if battle.localSlot == slot then
			text = "ВЫ · " .. (if def then def.displayName else text)
		end
		return text
	end)
	local isLocal = scope:Computed(function(use)
		local battle = use(state.battle)
		return battle ~= nil and battle.localSlot == slot
	end)
	local superColor = superColorOf(scope, info)

	local rowWidth = barX + ROW_BAR_WIDTH
	return scope:New "Frame" {
		Name = `TeamRow{slot}`,
		AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
		BackgroundTransparency = 1,
		Position = if isLeft then UDim2.fromOffset(12, y) else UDim2.new(1, -12, 0, y),
		Size = UDim2.fromOffset(rowWidth, ROW_HEIGHT - 4),
		[Children] = {
			PortraitFrame(scope, info, {
				isLeft = isLeft,
				size = portraitSize,
				color = TEAM_COLORS[team],
				position = UDim2.fromScale(if isLeft then 0 else 1, 0),
				knockedOut = knockedOut,
			}),
			scope:New "TextLabel" {
				Name = "Name",
				AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = if isLeft then UDim2.fromOffset(barX, -1) else UDim2.new(1, -barX, 0, -1),
				Size = UDim2.fromOffset(ROW_BAR_WIDTH, 17),
				Text = name,
				TextColor3 = scope:Computed(function(use)
					return if use(isLocal) then Theme.Colors.Accent else Theme.Colors.Text
				end),
				TextSize = 15,
				TextStrokeTransparency = 0.3,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			},
			HealthBar(scope, {
				Health = hudFighter.health,
				MaxHealth = hudFighter.maxHealth,
				Side = if isLeft then "Left" else "Right",
				AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
				Position = if isLeft then UDim2.fromOffset(barX, 18) else UDim2.new(1, -barX, 0, 18),
				Size = UDim2.fromOffset(ROW_BAR_WIDTH, 14),
			}),
			scope:Computed(function(use, innerScope: Scope): Instance
				return SuperMeter(innerScope, {
					Meter = hudFighter.meter,
					Side = if isLeft then "Left" else "Right",
					Color = use(superColor),
					Clock = clock,
					AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
					Position = if isLeft then UDim2.fromOffset(barX, 35) else UDim2.new(1, -barX, 0, 35),
					Size = UDim2.fromOffset(ROW_BAR_WIDTH * 0.7, 6),
					Compact = true,
					-- Своя строка: «SUPER!» рядом со шкалой, когда можно бить супер.
					ReadyLabel = use(isLocal),
				})
			end),
		} :: { Fusion.Child },
	}
end

-- Победы в раундах по бокам от таймера (2 на 2 — по командам).
local function TeamPips(scope: Scope, state: AppState.AppState, team: number): Instance
	local isLeft = team == 1
	return RoundPips(scope, {
		Wins = state.hud.wins,
		RoundsToWin = state.hud.roundsToWin,
		Slot = team,
		Side = if isLeft then "Left" else "Right",
		AnchorPoint = Vector2.new(if isLeft then 1 else 0, 0),
		Position = if isLeft then UDim2.new(0.5, -52, 0, 26) else UDim2.new(0.5, 52, 0, 26),
	})
end

-- Самая длинная серия, которую сейчас получает кто-то из бойцов команды team.
local function teamCombo(use: Fusion.Use, state: AppState.AppState, battle: AppState.BattleInfo?, team: number): number
	local best = 0
	if battle == nil then
		return best
	end
	for _, fighter in battle.fighters do
		if fighter.team == team then
			local hudFighter = state.hud.fighters[fighter.slot]
			if hudFighter then
				best = math.max(best, use(hudFighter.combo))
			end
		end
	end
	return best
end

-- «N HITS» у атакующей стороны, пока кто-то из противников в комбо.
local function ComboCounter(scope: Scope, state: AppState.AppState, attackerTeam: number): Instance
	local combo = scope:Computed(function(use)
		return teamCombo(use, state, use(state.battle), 3 - attackerTeam)
	end)
	local isLeft = attackerTeam == 1
	return scope:New "TextLabel" {
		Name = `Combo{attackerTeam}`,
		AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Pixel,
		Position = if isLeft then UDim2.fromOffset(24, 150) else UDim2.new(1, -24, 0, 150),
		Size = UDim2.fromOffset(260, 48),
		Text = scope:Computed(function(use)
			return `{use(combo)} HITS`
		end),
		TextColor3 = Theme.Colors.Accent,
		TextSize = 44,
		TextStrokeTransparency = 0,
		TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
		Visible = scope:Computed(function(use)
			return use(combo) >= 2
		end),
	}
end

-- Название комбо («КЛАССИКА!») под счётчиком ударов у стороны того, кто его сделал.
local function ComboTitle(scope: Scope, state: AppState.AppState, team: number): Instance
	local hud = state.hud
	local isLeft = team == 1
	local scale = scope:Spring(scope:Value(1), 30, 0.5)
	scope:Observer(hud.comboSerial):onChange(function()
		if peek(hud.comboTeam) == team then
			scale:setPosition(1.8)
		end
	end)
	return scope:New "TextLabel" {
		Name = `ComboTitle{team}`,
		AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Title,
		Position = if isLeft then UDim2.fromOffset(24, 198) else UDim2.new(1, -24, 0, 198),
		Size = UDim2.fromOffset(320, 40),
		Text = scope:Computed(function(use)
			return use(hud.comboName) .. "!"
		end),
		TextColor3 = Theme.Colors.Accent,
		TextSize = 34,
		TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
		Visible = scope:Computed(function(use)
			return use(hud.comboName) ~= "" and use(hud.comboTeam) == team
		end),
		ZIndex = 15,
		[Children] = {
			scope:New "UIScale" { Scale = scale },
			scope:New "UIStroke" {
				Color = Theme.Colors.Outline,
				Thickness = 3,
			},
			scope:New "UIGradient" {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromHex("#FFF6B0")),
					ColorSequenceKeypoint.new(1, Color3.fromHex("#FF9A3D")),
				}),
				Rotation = 90,
			},
		},
	}
end

local function Timer(scope: Scope, state: AppState.AppState): Instance
	return scope:New "TextLabel" {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Pixel,
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(84, 58),
		Text = scope:Computed(function(use)
			local seconds = use(state.hud.timer)
			return if seconds < 0 then "∞" else tostring(seconds)
		end),
		TextColor3 = scope:Computed(function(use)
			local seconds = use(state.hud.timer)
			return if seconds >= 0 and seconds <= 10 then Theme.Colors.Danger else Theme.Colors.Text
		end),
		TextSize = 52,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Colors.Outline,
				Thickness = 3,
			},
		},
	}
end

-- Одна подсказка: клавиши-«кнопочки» и подпись.
local function HintChip(scope: Scope, hint: Hint, order: number): Instance
	local items: { Instance } = {
		scope:New "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		},
	}
	for index, key in hint.keys do
		table.insert(
			items,
			scope:New "TextLabel" {
				Name = `Key{index}`,
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Theme.Colors.Text,
				Font = Theme.Fonts.Title,
				LayoutOrder = index,
				Size = UDim2.fromOffset(20, 20),
				Text = key,
				TextColor3 = Theme.Colors.Outline,
				TextSize = 13,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
					scope:New "UIPadding" {
						PaddingLeft = UDim.new(0, 5),
						PaddingRight = UDim.new(0, 5),
					},
				},
			}
		)
	end
	table.insert(
		items,
		scope:New "TextLabel" {
			Name = "Text",
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			LayoutOrder = 10,
			Size = UDim2.fromOffset(0, 20),
			Text = hint.text,
			TextColor3 = Theme.Colors.Text,
			TextSize = 14,
			TextStrokeTransparency = 0.4,
		}
	)
	return scope:New "Frame" {
		Name = `Hint{order}`,
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Size = UDim2.fromOffset(0, 22),
		[Children] = items,
	}
end

local function ControlsHint(scope: Scope, state: AppState.AppState, clock: Fusion.Value<number>): Instance
	local startedAt = os.clock()
	return scope:New "Frame" {
		Name = "ControlsHint",
		AnchorPoint = Vector2.new(0.5, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Colors.Outline,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(0, 32),
		Visible = scope:Computed(function(use)
			local platform = use(state.platform)
			if HINTS[platform] == nil then
				return false
			end
			local battle = use(state.battle)
			if battle and battle.mode == "Training" then
				return true
			end
			return use(clock) - startedAt < HINT_SECONDS
		end),
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			scope:New "UIPadding" {
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
			},
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			},
			scope:Computed(function(use, innerScope: Scope): { Instance }
				local chips: { Instance } = {}
				local hints: { Hint } = HINTS[use(state.platform)] or {}
				for index, hint in hints do
					table.insert(chips, HintChip(innerScope, hint, index))
				end
				return chips
			end),
		} :: { Fusion.Child },
	}
end

-- Эмоции: кнопка 😀 справа от паузы раскрывает ряд доступных смайликов (только в своём бою).
local function EmoteBar(scope: Scope, state: AppState.AppState): Instance
	local open = scope:Value(false)
	local emotes = scope:Computed(function(use, innerScope: Scope): { Instance }
		local items = use(state.items)
		local list: { Instance } = {
			innerScope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
		}
		for index, item in Cosmetics.ofKind("Emote") do
			if items[item.id] then
				table.insert(
					list,
					Button(innerScope, {
						Name = `Emote_{item.id}`,
						Text = item.emoji or item.icon,
						LayoutOrder = index,
						Size = UDim2.fromOffset(44, 44),
						TextSize = 24,
						Color = Theme.Colors.PanelLight,
						OnClick = function()
							state.actions.emote(item.id)
							open:set(false)
						end,
					})
				)
			end
		end
		return list
	end)
	return scope:New "Frame" {
		Name = "Emotes",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = scope:Computed(function(use)
			local battle = use(state.battle)
			return battle ~= nil and battle.localSlot ~= nil
		end),
		[Children] = {
			Button(scope, {
				Name = "EmoteButton",
				Text = "😀",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.new(0.5, 4, 0, 72),
				Size = UDim2.fromOffset(48, 40),
				TextSize = 22,
				OnClick = function()
					open:set(not peek(open))
				end,
			}),
			scope:New "Frame" {
				Name = "EmoteRow",
				AnchorPoint = Vector2.new(0.5, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Theme.Colors.Outline,
				BackgroundTransparency = 0.3,
				Position = UDim2.new(0.5, 0, 0, 120),
				Size = UDim2.fromOffset(0, 56),
				Visible = open,
				ZIndex = 20,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
					scope:New "UIPadding" {
						PaddingLeft = UDim.new(0, 6),
						PaddingRight = UDim.new(0, 6),
						PaddingTop = UDim.new(0, 6),
					},
					emotes,
				} :: { Fusion.Child },
			},
		},
	}
end

local function Battle(scope: Scope, state: AppState.AppState): Instance
	-- Часы для пульсаций и подсказок; соединение удаляется вместе со scope экрана.
	local clock = scope:Value(os.clock())
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function()
			clock:set(os.clock())
		end)
	)
	-- Первая тренировка в сессии: сама открывается памятка «Как играть».
	local battleInfo = peek(state.battle)
	if battleInfo and battleInfo.mode == "Training" and not state.howToSeen then
		state.howToSeen = true
		state.modal:set("HowToPlay")
	end

	-- Раскладка HUD зависит от числа бойцов (пересобирается, только когда начинается новый бой).
	local teamMode = scope:Computed(function(use)
		local battle = use(state.battle)
		return battle ~= nil and #battle.fighters > 2
	end)
	local panels = scope:Computed(function(use, innerScope: Scope): { Instance }
		if not use(teamMode) then
			return {
				FighterPanel(innerScope, state, 1, clock),
				FighterPanel(innerScope, state, 2, clock),
			}
		end
		local items: { Instance } = {}
		for team, slots in TEAM_SLOTS do
			for row, slot in slots do
				table.insert(items, TeamRow(innerScope, state, slot, team, row, clock))
			end
			table.insert(items, TeamPips(innerScope, state, team))
		end
		return items
	end)

	return scope:New "Frame" {
		Name = "Battle",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			panels,
			Timer(scope, state),
			ComboCounter(scope, state, 1),
			ComboCounter(scope, state, 2),
			ComboTitle(scope, state, 1),
			ComboTitle(scope, state, 2),
			Banner(scope, {
				Text = state.hud.banner,
				Color = state.hud.bannerColor,
				Serial = state.hud.bannerSerial,
			}),
			Button(scope, {
				Name = "Pause",
				Text = "II",
				Font = Theme.Fonts.Pixel,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(0.5, -4, 0, 72),
				Size = UDim2.fromOffset(48, 40),
				TextSize = 22,
				OnClick = function()
					state.modal:set(if peek(state.modal) == "Pause" then "" else "Pause")
				end,
			}),
			EmoteBar(scope, state),
			ControlsHint(scope, state, clock),
		} :: { Fusion.Child },
	}
end

return Battle
