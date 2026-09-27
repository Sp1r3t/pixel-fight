--!strict
--[[
	Экран «Комбо»: все 28 комбо с кнопками-иконками (👊 👊 🦶), подсказкой и наградой.

	  • вкладки «Для всех» (12 общих — выходят у любого бойца) и «Фирменные» (16 — по одному
	    на бойца, с портретом);
	  • найденное комбо отмечено ✓, ненайденное показывает награду за первое выполнение;
	  • «Попробовать» — сразу в тренировку; у фирменного комбо портрет — кнопка «попробовать этим
	    бойцом» (закрытый боец ведёт в магазин).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Combos = require(ReplicatedStorage.Shared.Config.Combos)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local Panel = require(script.Parent.Parent.Components.Panel)
local Pill = require(script.Parent.Parent.Components.Pill)
local FighterPortrait = require(script.Parent.Parent.Components.FighterPortrait)
local ScreenHeader = require(script.Parent.Parent.Components.ScreenHeader)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>
type Combo = Combos.Combo

local ROW_HEIGHT = 70

-- Кнопки-иконки комбо: [👊] [👊] [🦶].
local function InputChips(scope: Scope, combo: Combo): Instance
	local chips: { Instance } = {
		scope:New "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		},
	}
	for index, token in combo.inputs do
		table.insert(
			chips,
			scope:New "TextLabel" {
				Name = `Input{index}`,
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Theme.Colors.PanelLight,
				Font = Theme.Fonts.Title,
				LayoutOrder = index,
				Size = UDim2.fromOffset(40, 40),
				Text = Combos.tokenIcons[token] or token,
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 22,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, 8) },
					scope:New "UIPadding" {
						PaddingLeft = UDim.new(0, 6),
						PaddingRight = UDim.new(0, 6),
					},
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.Colors.Outline,
						Thickness = 2,
					},
				},
			}
		)
	end
	return scope:New "Frame" {
		Name = "Inputs",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -118, 0.5, 0),
		Size = UDim2.fromOffset(260, 44),
		[Children] = chips,
	}
end

local function ComboRow(scope: Scope, state: AppState.AppState, combo: Combo, order: number): Instance
	local found = scope:Computed(function(use)
		return use(state.combosFound)[combo.id] == true
	end)
	local def = if combo.character then CharacterRegistry.get(combo.character) else nil
	local textX = if def then 64 else 58

	local left: { Instance } = {}
	if def then
		local fighterId = def.id
		local owned = scope:Computed(function(use)
			return use(state.ownedCharacters)[fighterId] == true
		end)
		-- Портрет — кнопка: сразу в тренировку этим бойцом (или в магазин, если он закрыт).
		table.insert(
			left,
			scope:New "TextButton" {
				Name = `Try_{combo.id}`,
				AnchorPoint = Vector2.new(0, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = Color3.fromHex(def.palette.accent):Lerp(Theme.Colors.Panel, 0.7),
				ClipsDescendants = true,
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.fromOffset(48, 48),
				Text = "",
				[OnEvent "Activated"] = function()
					if peek(owned) then
						state.selectedCharacterId:set(fighterId)
						state.actions.startTraining()
					else
						AppState.navigate(state, "Shop")
					end
				end,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
					FighterPortrait(scope, { Character = def, Framing = "Bust" }),
					scope:New "TextLabel" {
						Name = "Play",
						AnchorPoint = Vector2.new(1, 1),
						BackgroundColor3 = scope:Computed(function(use)
							return if use(owned) then Theme.Colors.Success else Theme.Colors.Paid
						end),
						Font = Theme.Fonts.Title,
						Position = UDim2.new(1, -1, 1, -1),
						Size = UDim2.fromOffset(20, 20),
						Text = scope:Computed(function(use)
							return if use(owned) then "▶" else "🔒"
						end),
						TextColor3 = Theme.Colors.Outline,
						TextSize = 12,
						ZIndex = 3,
						[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					},
				},
			}
		)
	else
		table.insert(
			left,
			scope:New "TextLabel" {
				Name = "Status",
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = scope:Computed(function(use)
					return if use(found) then Theme.Colors.Success else Theme.Colors.PanelLight
				end),
				Font = Theme.Fonts.Title,
				Position = UDim2.new(0, 10, 0.5, 0),
				Size = UDim2.fromOffset(38, 38),
				Text = scope:Computed(function(use)
					return if use(found) then "✓" else "?"
				end),
				TextColor3 = Theme.Colors.Text,
				TextSize = 20,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Theme.Colors.Outline,
						Thickness = 2,
					},
				},
			}
		)
	end

	return Panel(scope, {
		Name = `Combo_{combo.id}`,
		Color = scope:Computed(function(use)
			return if use(found) then Theme.Colors.PanelLight else Theme.Colors.Panel
		end),
		LayoutOrder = order,
		Size = UDim2.new(1, -8, 0, ROW_HEIGHT - 6),
		StrokeColor = scope:Computed(function(use)
			return if use(found) then Theme.Colors.Success else Theme.Colors.Outline
		end),
		Content = {
			left,
			scope:New "TextLabel" {
				Name = "ComboName",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Title,
				Position = UDim2.fromOffset(textX, 6),
				Size = UDim2.new(1, -textX - 390, 0, 24),
				Text = if def then `{combo.name} · {def.displayName}` else combo.name,
				TextColor3 = Theme.Colors.Text,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 20 },
			},
			scope:New "TextLabel" {
				Name = "Hint",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(textX, 32),
				Size = UDim2.new(1, -textX - 390, 0, 28),
				Text = combo.hint,
				TextColor3 = Theme.Colors.TextDim,
				TextScaled = true,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				[Children] = scope:New "UITextSizeConstraint" { MaxTextSize = 14 },
			},
			InputChips(scope, combo),
			Pill(scope, {
				Name = "Reward",
				Icon = scope:Computed(function(use): string
					return if use(found) then "✅" else "🪙"
				end),
				Text = scope:Computed(function(use)
					return if use(found) then "есть" else `+{combo.reward}`
				end),
				Color = scope:Computed(function(use)
					return if use(found) then Theme.Colors.Success else Theme.Colors.Panel
				end),
				TextColor = scope:Computed(function(use)
					return if use(found) then Theme.Colors.Text else Theme.Colors.Coins
				end),
				Height = 30,
				TextSize = 16,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
			}),
		} :: { Fusion.Child },
	})
end

local function ComboList(scope: Scope, state: AppState.AppState): Instance
	local tab = scope:Value("All")
	local total = #Combos.list
	local foundCount = scope:Computed(function(use)
		local count = 0
		for id in use(state.combosFound) do
			if Combos.byId[id] then
				count += 1
			end
		end
		return count
	end)

	local rows = scope:Computed(function(use, innerScope: Scope): { Instance }
		local signature = use(tab) == "Signature"
		local items: { Instance } = {}
		for index, combo in Combos.list do
			if (combo.character ~= nil) == signature then
				table.insert(items, ComboRow(innerScope, state, combo, index))
			end
		end
		return items
	end)

	local function TabButton(id: string, text: string, icon: string, x: number): Instance
		return Button(scope, {
			Name = `Tab_{id}`,
			Text = text,
			Icon = icon,
			TextSize = 18,
			Color = scope:Computed(function(use)
				return if use(tab) == id then Theme.Colors.ButtonPrimary else Theme.Colors.Button
			end),
			Position = UDim2.fromOffset(x, 72),
			Size = UDim2.fromOffset(210, 44),
			OnClick = function()
				tab:set(id)
			end,
		})
	end

	return scope:New "Frame" {
		Name = "ComboList",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			ScreenHeader(scope, {
				Title = "КОМБО",
				Coins = state.coins,
				OnBack = function()
					AppState.back(state)
				end,
			}),
			TabButton("All", "Для всех", "👊", 24),
			TabButton("Signature", "Фирменные", "⭐", 244),
			Pill(scope, {
				Name = "Found",
				Icon = "📜",
				Text = scope:Computed(function(use)
					return `Найдено: {use(foundCount)} / {total}`
				end),
				Color = Theme.Colors.PanelLight,
				Height = 34,
				TextSize = 17,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -24, 0, 78),
			}),
			scope:New "ScrollingFrame" {
				Name = "List",
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				Position = UDim2.fromOffset(24, 128),
				ScrollBarImageColor3 = Theme.Colors.Accent,
				ScrollBarThickness = 6,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				Size = UDim2.new(1, -48, 0, 340),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:New "UIPadding" {
						PaddingTop = UDim.new(0, 3),
						PaddingLeft = UDim.new(0, 3),
						PaddingRight = UDim.new(0, 8),
					},
					rows,
				} :: { Fusion.Child },
			},
			scope:New "TextLabel" {
				Name = "Help",
				AnchorPoint = Vector2.new(0, 1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(0, 24, 1, -14),
				Size = UDim2.fromOffset(600, 40),
				Text = "Жми следующую кнопку, как только прошлый удар попал. За каждое новое комбо — монеты!",
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 15,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			},
			Button(scope, {
				Name = "TryCombos",
				Text = "Попробовать",
				Icon = "🥋",
				Color = Theme.Colors.Success,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -24, 1, -12),
				Size = UDim2.fromOffset(250, 50),
				OnClick = function()
					state.actions.startTraining()
				end,
			}),
		},
	}
end

return ComboList
