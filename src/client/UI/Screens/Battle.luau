--!strict
--[[
	HUD боя (поверх 3D-арены):
	  • 1 на 1 — сверху портреты, имена, полосы HP с задержанной белой полосой урона, победы в раундах,
	    таймер; снизу шкалы супера (пульсируют, когда полные);
	  • 2 на 2 — две компактные строки на команду (слева синие, справа красные): портрет, имя, HP и
	    тонкая шкала супера; выбитый боец помечен «K.O.»; большая шкала супера — только своя;
	  • счётчик комбо у атакующей стороны, крупные надписи раундов по центру, кнопка выхода.
	Ничего не перекрывается: верхняя полоса HUD — до y = 110, комбо — ниже, шкалы супера — у нижнего края
	вне зоны сенсорных кнопок.
	Все данные — Fusion Values из AppState.hud, их обновляет FightController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local FighterPortrait = require(script.Parent.Parent.Components.FighterPortrait)
local HealthBar = require(script.Parent.Parent.Components.HealthBar)
local SuperMeter = require(script.Parent.Parent.Components.SuperMeter)
local RoundPips = require(script.Parent.Parent.Components.RoundPips)
local Banner = require(script.Parent.Parent.Components.Banner)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

local HINTS: { [string]: string } = {
	Keyboard = "A/D — движение · W/Пробел — прыжок · S — присед · Shift — рывок · Q — блок · "
		.. "J — рука · K — нога · L — особый · I — супер",
	Gamepad = "Стик — движение · A — прыжок · LB — рывок · LT — блок · "
		.. "X — рука · Y — нога · B — особый · RB — супер",
}

local TEAM_COLORS: { Color3 } = { Color3.fromHex("#4DB8FF"), Color3.fromHex("#FF5A6E") }
-- 2 на 2: строки команды (слоты сверху вниз). Нижний этаж (1, 2) — первая строка.
local TEAM_SLOTS: { { number } } = { { 1, 3 }, { 2, 4 } }
local ROW_HEIGHT = 48
local ROW_BAR_WIDTH = 250

local SCREEN_WIDTH = Theme.ReferenceSize.X
local HP_WIDTH = 340
local PORTRAIT = 46

-- Панель одного бойца сверху: портрет, имя, HP, победы в раундах.
local function FighterPanel(scope: Scope, state: AppState.AppState, slot: number): Instance
	local side: "Left" | "Right" = if slot == 1 then "Left" else "Right"
	local isLeft = slot == 1
	local hudFighter = state.hud.fighters[slot]

	local info = scope:Computed(function(use): AppState.BattleFighter?
		local battle = use(state.battle)
		if battle == nil then
			return nil
		end
		for _, fighter in battle.fighters do
			if fighter.slot == slot then
				return fighter
			end
		end
		return nil
	end)

	local portrait = scope:Computed(function(use, innerScope: Scope): Instance?
		local fighter = use(info)
		local def = if fighter then CharacterRegistry.get(fighter.characterId) else nil
		if fighter == nil or def == nil then
			return nil
		end
		local palette = fighter.palette or def.palette
		return innerScope:New "Frame" {
			Name = "Portrait",
			BackgroundColor3 = Theme.Colors.Panel,
			BorderSizePixel = 0,
			Position = if isLeft then UDim2.fromOffset(16, 10) else UDim2.fromOffset(SCREEN_WIDTH - 16 - PORTRAIT, 10),
			Size = UDim2.fromOffset(PORTRAIT, PORTRAIT),
			[Children] = {
				innerScope:New "UIStroke" {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Color3.fromHex(palette.accent),
					Thickness = 3,
				},
				FighterPortrait(innerScope, {
					Character = def,
					Palette = palette,
					Framing = "Bust",
					Facing = if isLeft then 1 else -1,
				}),
			},
		}
	end)

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
		return text
	end)

	local barX = if isLeft then 16 + PORTRAIT + 8 else SCREEN_WIDTH - 16 - PORTRAIT - 8

	return scope:New "Frame" {
		Name = `FighterPanel{slot}`,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			portrait,
			scope:New "TextLabel" {
				Name = "Name",
				AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Pixel,
				Position = UDim2.fromOffset(barX, 4),
				Size = UDim2.fromOffset(HP_WIDTH, 24),
				Text = name,
				TextColor3 = Theme.Colors.Text,
				TextSize = 24,
				TextStrokeTransparency = 0.2,
				TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			},
			HealthBar(scope, {
				Health = hudFighter.health,
				MaxHealth = hudFighter.maxHealth,
				Side = side,
				AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
				Position = UDim2.fromOffset(barX, 30),
				Size = UDim2.fromOffset(HP_WIDTH, 22),
			}),
			RoundPips(scope, {
				Wins = state.hud.wins,
				RoundsToWin = state.hud.roundsToWin,
				Slot = slot,
				Side = side,
				AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
				Position = UDim2.fromOffset(barX, 60),
			}),
		} :: { Fusion.Child },
	}
end

local function SuperPanel(
	scope: Scope,
	state: AppState.AppState,
	slot: number,
	clock: Fusion.Value<number>,
	isLeft: boolean
): Fusion.Child
	local color = scope:Computed(function(use)
		local battle = use(state.battle)
		if battle then
			for _, fighter in battle.fighters do
				if fighter.slot == slot then
					local def = CharacterRegistry.get(fighter.characterId)
					if def then
						return Color3.fromHex(def.cosmetics.superFlash)
					end
				end
			end
		end
		return Theme.Colors.Accent
	end)
	return scope:Computed(function(use, innerScope: Scope): Instance
		return SuperMeter(innerScope, {
			Meter = state.hud.fighters[slot].meter,
			Side = if isLeft then "Left" else "Right",
			Color = use(color),
			Clock = clock,
			AnchorPoint = Vector2.new(if isLeft then 0 else 1, 1),
			Position = if isLeft then UDim2.new(0, 16, 1, -34) else UDim2.new(1, -16, 1, -34),
			Size = UDim2.fromOffset(240, 16),
		})
	end)
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
	local info = scope:Computed(function(use): AppState.BattleFighter?
		local battle = use(state.battle)
		return if battle then AppState.fighterInSlot(battle, slot) else nil
	end)
	local knockedOut = scope:Computed(function(use)
		return use(hudFighter.health) <= 0
	end)
	local portraitSize = 40
	local barX = portraitSize + 8
	local y = 6 + (row - 1) * ROW_HEIGHT

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
			Facing = if isLeft then 1 else -1,
		})
	end)

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

	local superColor = scope:Computed(function(use)
		local fighter = use(info)
		local def = if fighter then CharacterRegistry.get(fighter.characterId) else nil
		return if def then Color3.fromHex(def.cosmetics.superFlash) else Theme.Colors.Accent
	end)

	local rowWidth = barX + ROW_BAR_WIDTH
	return scope:New "Frame" {
		Name = `TeamRow{slot}`,
		AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
		BackgroundTransparency = 1,
		Position = if isLeft then UDim2.fromOffset(12, y) else UDim2.new(1, -12, 0, y),
		Size = UDim2.fromOffset(rowWidth, ROW_HEIGHT - 4),
		[Children] = {
			scope:New "Frame" {
				Name = "Portrait",
				AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
				BackgroundColor3 = Theme.Colors.Panel,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(if isLeft then 0 else 1, 0),
				Size = UDim2.fromOffset(portraitSize, portraitSize),
				[Children] = {
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = TEAM_COLORS[team],
						Thickness = 3,
					},
					portrait,
					scope:New "TextLabel" {
						Name = "KO",
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = 0.35,
						Font = Theme.Fonts.Pixel,
						Size = UDim2.fromScale(1, 1),
						Text = "K.O.",
						TextColor3 = Color3.fromHex("#FF4D6D"),
						TextSize = 18,
						Visible = knockedOut,
						ZIndex = 3,
					},
				} :: { Fusion.Child },
			},
			scope:New "TextLabel" {
				Name = "Name",
				AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = if isLeft then UDim2.fromOffset(barX, -1) else UDim2.new(1, -barX, 0, -1),
				Size = UDim2.fromOffset(ROW_BAR_WIDTH, 17),
				Text = name,
				TextColor3 = Theme.Colors.Text,
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
				})
			end),
		} :: { Fusion.Child },
	}
end

-- 2 на 2: победы команд в раундах — по бокам от таймера.
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

local function Timer(scope: Scope, state: AppState.AppState): Instance
	return scope:New "TextLabel" {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Pixel,
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(84, 58),
		Text = scope:Computed(function(use)
			local seconds = use(state.hud.timer)
			return if seconds < 0 then "--" else tostring(seconds)
		end),
		TextColor3 = scope:Computed(function(use)
			local seconds = use(state.hud.timer)
			return if seconds >= 0 and seconds <= 10 then Color3.fromHex("#FF4D6D") else Theme.Colors.Text
		end),
		TextSize = 54,
		[Children] = scope:New "UIStroke" {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Colors.Outline,
			Thickness = 3,
		},
	}
end

local function Battle(scope: Scope, state: AppState.AppState): Instance
	-- Часы для пульсаций; соединение удаляется вместе со scope экрана.
	local clock = scope:Value(os.clock())
	table.insert(
		scope,
		RunService.RenderStepped:Connect(function()
			clock:set(os.clock())
		end)
	)

	-- Раскладка HUD зависит от числа бойцов (пересобирается, только когда начинается новый бой).
	local teamMode = scope:Computed(function(use)
		local battle = use(state.battle)
		return battle ~= nil and #battle.fighters > 2
	end)
	local panels = scope:Computed(function(use, innerScope: Scope): { Instance }
		if not use(teamMode) then
			return {
				FighterPanel(innerScope, state, 1),
				FighterPanel(innerScope, state, 2),
				SuperPanel(innerScope, state, 1, clock, true) :: any,
				SuperPanel(innerScope, state, 2, clock, false) :: any,
			}
		end
		local items: { Instance } = {}
		for team, slots in TEAM_SLOTS do
			for row, slot in slots do
				table.insert(items, TeamRow(innerScope, state, slot, team, row, clock))
			end
			table.insert(items, TeamPips(innerScope, state, team))
		end
		-- Большая шкала супера — только своя (на стороне своей команды).
		local battle = use(state.battle)
		local localSlot = if battle then battle.localSlot else nil
		local localTeam = if battle then battle.localTeam else nil
		if localSlot then
			table.insert(items, SuperPanel(innerScope, state, localSlot, clock, localTeam ~= 2) :: any)
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
			Banner(scope, {
				Text = state.hud.banner,
				Color = state.hud.bannerColor,
				Serial = state.hud.bannerSerial,
			}),
			Button(scope, {
				Text = "Выйти",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 72),
				Size = UDim2.fromOffset(96, 32),
				TextSize = 16,
				OnClick = function()
					state.actions.leaveMatch()
				end,
			}),
			scope:New "TextLabel" {
				Name = "ControlsHint",
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.fromOffset(440, 30),
				Text = scope:Computed(function(use)
					return HINTS[use(state.platform)] or ""
				end),
				TextColor3 = Theme.Colors.Text,
				TextSize = 13,
				TextStrokeTransparency = 0.4,
				TextWrapped = true,
			},
		} :: { Fusion.Child },
	}
end

return Battle
