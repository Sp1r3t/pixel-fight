--!strict
--[[
	Экран боя (поверх 3D-арены). На этапе 2 — имена бойцов, кнопка выхода и подсказка
	по управлению; полноценный HUD (HP, супер, таймер, раунды) — этап 4.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

local CONTROLS_HINT = "A/D — движение · W — прыжок · S — присед · Shift или двойное нажатие — рывок · "
	.. "назад от противника — блок"

local function NameTag(scope: Scope, text: string, color: Color3, rightSide: boolean): Instance
	return scope:New "TextLabel" {
		Name = "NameTag",
		AnchorPoint = Vector2.new(if rightSide then 1 else 0, 0),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Pixel,
		Position = if rightSide then UDim2.new(1, -16, 0, 14) else UDim2.fromOffset(16, 14),
		Size = UDim2.fromOffset(300, 34),
		Text = string.upper(text),
		TextColor3 = color,
		TextSize = 26,
		TextXAlignment = if rightSide then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
		[Children] = {
			scope:New "UIPadding" {
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			},
			scope:New "UIStroke" {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Theme.Colors.Outline,
				Thickness = 2,
			},
		},
	}
end

local function Battle(scope: Scope, state: AppState.AppState): Instance
	local tags = scope:Computed(function(use, innerScope: Scope): { Instance }
		local battle = use(state.battle)
		if battle == nil then
			return {}
		end
		local result = {}
		for _, fighter in battle.fighters do
			local def = CharacterRegistry.get(fighter.characterId)
			if def then
				local isLocal = battle.localSlot == fighter.slot
				local label = if isLocal then `{def.displayName} (вы)` else def.displayName
				table.insert(result, NameTag(innerScope, label, Color3.fromHex(def.palette.accent), fighter.slot == 2))
			end
		end
		return result
	end)

	return scope:New "Frame" {
		Name = "Battle",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			tags,
			Button(scope, {
				Text = "Выйти",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 12),
				Size = UDim2.fromOffset(120, 40),
				TextSize = 18,
				OnClick = function()
					state.actions.leaveMatch()
				end,
			}),
			scope:New "TextLabel" {
				Name = "ControlsHint",
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, -40, 0, 20),
				Text = CONTROLS_HINT,
				TextColor3 = Theme.Colors.Text,
				TextSize = 14,
				TextStrokeTransparency = 0.4,
			},
		} :: { Fusion.Child },
	}
end

return Battle
