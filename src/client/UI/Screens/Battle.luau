--!strict
--[[
	HUD боя (поверх 3D-арены):
	  • сверху: портреты, имена, полосы HP с задержанной белой полосой урона, победы в раундах, таймер;
	  • снизу: шкалы супера (пульсируют, когда полные);
	  • счётчик комбо у атакующего, крупные надписи раундов по центру;
	  • кнопка выхода из боя.
	Все данные — Fusion Values из AppState.hud, их обновляет FightController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local PixelFigure = require(script.Parent.Parent.Components.PixelFigure)
local HealthBar = require(script.Parent.Parent.Components.HealthBar)
local SuperMeter = require(script.Parent.Parent.Components.SuperMeter)
local RoundPips = require(script.Parent.Parent.Components.RoundPips)
local Banner = require(script.Parent.Parent.Components.Banner)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

local CONTROLS_HINT = "A/D — движение · W — прыжок · S — присед · Shift — рывок · назад — блок · "
	.. "J — рука · K — нога · L — особый · I — супер"

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
		if def == nil then
			return nil
		end
		return innerScope:New "Frame" {
			Name = "Portrait",
			BackgroundColor3 = Theme.Colors.Panel,
			BorderSizePixel = 0,
			Position = if isLeft then UDim2.fromOffset(16, 10) else UDim2.fromOffset(SCREEN_WIDTH - 16 - PORTRAIT, 10),
			Size = UDim2.fromOffset(PORTRAIT, PORTRAIT),
			[Children] = {
				innerScope:New "UIStroke" {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Color3.fromHex(def.palette.accent),
					Thickness = 3,
				},
				PixelFigure(innerScope, { Palette = def.palette }),
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
		local text = string.upper(if def then def.displayName else fighter.characterId)
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
	clock: Fusion.Value<number>
): Fusion.Child
	local isLeft = slot == 1
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

-- «N HITS» у атакующего, пока противник в комбо.
local function ComboCounter(scope: Scope, state: AppState.AppState, attackerSlot: number): Instance
	local victim = state.hud.fighters[3 - attackerSlot]
	local isLeft = attackerSlot == 1
	return scope:New "TextLabel" {
		Name = `Combo{attackerSlot}`,
		AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Pixel,
		Position = if isLeft then UDim2.fromOffset(24, 150) else UDim2.new(1, -24, 0, 150),
		Size = UDim2.fromOffset(260, 48),
		Text = scope:Computed(function(use)
			return `{use(victim.combo)} HITS`
		end),
		TextColor3 = Theme.Colors.Accent,
		TextSize = 44,
		TextStrokeTransparency = 0,
		TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
		Visible = scope:Computed(function(use)
			return use(victim.combo) >= 2
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

	return scope:New "Frame" {
		Name = "Battle",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			FighterPanel(scope, state, 1),
			FighterPanel(scope, state, 2),
			Timer(scope, state),
			SuperPanel(scope, state, 1, clock),
			SuperPanel(scope, state, 2, clock),
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
				Size = UDim2.new(0, 440, 0, 30),
				Text = CONTROLS_HINT,
				TextColor3 = Theme.Colors.Text,
				TextSize = 13,
				TextStrokeTransparency = 0.4,
				TextWrapped = true,
			},
		} :: { Fusion.Child },
	}
end

return Battle
