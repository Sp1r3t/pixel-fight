--!strict
--[[
	Окна поверх боя (слой Overlay в App — выше сенсорных кнопок; пока окно открыто, кнопки скрыты):
	  • PauseMenu — «Продолжить» / «Как играть» / «Выйти». Бой не останавливается (в онлайне пауза
	    была бы нечестной), но выйти из боя можно только отсюда — дети не выйдут случайно;
	  • HowToPlay — памятка для детей: что делает каждая кнопка. Иконки и цвета — как на сенсорных
	    кнопках; на ПК и геймпаде рядом показана клавиша. Сама открывается в первой тренировке.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Button)
local Panel = require(script.Parent.Panel)
local TouchControls = require(script.Parent.TouchControls)

local Children = Fusion.Children

type Scope = Fusion.Scope<typeof(Fusion)>

type HowItem = {
	id: string,
	icon: string,
	title: string,
	text: string,
	keyboard: string,
	gamepad: string,
}

local HOW_TO: { HowItem } = {
	{
		id = "Move",
		icon = "🕹️",
		title = "Ходить",
		text = "Джойстик влево и вправо, вниз — присесть",
		keyboard = "A D",
		gamepad = "Стик",
	},
	{
		id = "Jump",
		icon = "⬆️",
		title = "Прыжок",
		text = "В 2 на 2 можно прыгнуть ещё раз в воздухе",
		keyboard = "W",
		gamepad = "A",
	},
	{
		id = "Light",
		icon = "👊",
		title = "Рука",
		text = "Быстрый удар",
		keyboard = "J",
		gamepad = "X",
	},
	{
		id = "Heavy",
		icon = "🦶",
		title = "Нога",
		text = "Сильный удар — дальше и больнее",
		keyboard = "K",
		gamepad = "Y",
	},
	{
		id = "Special",
		icon = "✨",
		title = "Приём",
		text = "Особый приём твоего бойца",
		keyboard = "L",
		gamepad = "B",
	},
	{
		id = "Super",
		icon = "⚡",
		title = "Супер",
		text = "Шкала заполнилась — жми, будет мощно!",
		keyboard = "I",
		gamepad = "RB",
	},
	{
		id = "Block",
		icon = "🛡️",
		title = "Блок",
		text = "Держи, чтобы удары не отнимали здоровье",
		keyboard = "Q",
		gamepad = "LT",
	},
	{
		id = "Dash",
		icon = "💨",
		title = "Рывок",
		text = "Дважды быстро толкни джойстик в сторону",
		keyboard = "Shift",
		gamepad = "LB",
	},
}

local MOVE_COLOR = Color3.fromHex("#5B6B9A")

local function buttonColor(id: string): Color3
	for _, button in TouchControls.BUTTONS do
		if button.id == id then
			return button.color
		end
	end
	return MOVE_COLOR
end

-- Затемнение экрана под окном.
local function Dim(scope: Scope, name: string, content: { Fusion.Child }): Instance
	return scope:New "Frame" {
		Name = name,
		Active = true,
		BackgroundColor3 = Theme.Colors.Outline,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
		[Children] = content,
	}
end

local BattleOverlays = {}

function BattleOverlays.PauseMenu(scope: Scope, state: AppState.AppState): Instance
	local battle = Fusion.peek(state.battle)
	local online = battle ~= nil and (battle.mode == "Versus" or battle.mode == "Team")
	return Dim(scope, "PauseMenu", {
		Panel(scope, {
			Name = "Box",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(360, 320),
			ZIndex = 41,
			Content = {
				scope:New "TextLabel" {
					Name = "Title",
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Title,
					Position = UDim2.fromOffset(0, 16),
					Size = UDim2.new(1, 0, 0, 40),
					Text = "ПАУЗА",
					TextColor3 = Theme.Colors.Accent,
					TextSize = 36,
					ZIndex = 42,
					[Children] = scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = 3,
					},
				},
				scope:New "TextLabel" {
					Name = "Note",
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Body,
					Position = UDim2.fromOffset(20, 58),
					Size = UDim2.new(1, -40, 0, 40),
					Text = if online
						then "Бой продолжается — соперник ждёт!"
						else "Отдохни и возвращайся в бой.",
					TextColor3 = Theme.Colors.TextDim,
					TextSize = 16,
					TextWrapped = true,
					ZIndex = 42,
				},
				Button(scope, {
					Name = "Resume",
					Text = "Продолжить",
					Icon = "▶️",
					Color = Theme.Colors.Success,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 106),
					Size = UDim2.fromOffset(270, 56),
					ZIndex = 42,
					OnClick = function()
						state.modal:set("")
					end,
				}),
				Button(scope, {
					Name = "HowToPlayButton",
					Text = "Как играть",
					Icon = "❓",
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 172),
					Size = UDim2.fromOffset(270, 50),
					TextSize = 20,
					ZIndex = 42,
					OnClick = function()
						state.modal:set("HowToPlay")
					end,
				}),
				Button(scope, {
					Name = "Leave",
					Text = "Выйти",
					Icon = "🚪",
					Color = Theme.Colors.Danger,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 236),
					Size = UDim2.fromOffset(270, 50),
					TextSize = 20,
					ZIndex = 42,
					OnClick = function()
						state.modal:set("")
						state.actions.leaveMatch()
					end,
				}),
			},
		}),
	})
end

local function HowRow(scope: Scope, item: HowItem, order: number, platform: string): Instance
	local key = if platform == "Keyboard" then item.keyboard elseif platform == "Gamepad" then item.gamepad else nil
	local extras: { Instance } = {}
	if key then
		table.insert(
			extras,
			scope:New "TextLabel" {
				Name = "Key",
				AnchorPoint = Vector2.new(1, 0),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Theme.Colors.Text,
				Font = Theme.Fonts.Title,
				Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(24, 22),
				Text = key,
				TextColor3 = Theme.Colors.Outline,
				TextSize = 14,
				ZIndex = 44,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, 5) },
					scope:New "UIPadding" {
						PaddingLeft = UDim.new(0, 6),
						PaddingRight = UDim.new(0, 6),
					},
				},
			}
		)
	end
	return scope:New "Frame" {
		Name = `How_{item.id}`,
		BackgroundColor3 = Theme.Colors.PanelLight,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 42,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			scope:New "TextLabel" {
				Name = "Icon",
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = buttonColor(item.id),
				Font = Theme.Fonts.Title,
				Position = UDim2.new(0, 6, 0.5, 0),
				Size = UDim2.fromOffset(50, 50),
				Text = item.icon,
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 26,
				ZIndex = 43,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = Color3.new(1, 1, 1),
						Thickness = 2,
					},
				},
			},
			scope:New "TextLabel" {
				Name = "Title",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Title,
				Position = UDim2.fromOffset(66, 6),
				Size = UDim2.new(1, -120, 0, 22),
				Text = item.title,
				TextColor3 = Theme.Colors.Text,
				TextSize = 19,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 43,
			},
			scope:New "TextLabel" {
				Name = "Text",
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(66, 28),
				Size = UDim2.new(1, -72, 0, 32),
				Text = item.text,
				TextColor3 = Theme.Colors.TextDim,
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 43,
			},
			extras,
		} :: { Fusion.Child },
	}
end

function BattleOverlays.HowToPlay(scope: Scope, state: AppState.AppState): Instance
	local rows = scope:Computed(function(use, innerScope: Scope): { Instance }
		local platform = use(state.platform)
		local items: { Instance } = {}
		for index, item in HOW_TO do
			table.insert(items, HowRow(innerScope, item, index, platform))
		end
		return items
	end)
	return Dim(scope, "HowToPlay", {
		Panel(scope, {
			Name = "Box",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(640, 440),
			ZIndex = 41,
			Content = {
				scope:New "TextLabel" {
					Name = "Title",
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Title,
					Position = UDim2.fromOffset(0, 12),
					Size = UDim2.new(1, 0, 0, 38),
					Text = "КАК ИГРАТЬ",
					TextColor3 = Theme.Colors.Accent,
					TextSize = 34,
					ZIndex = 42,
					[Children] = scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = 3,
					},
				},
				scope:New "Frame" {
					Name = "Grid",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(16, 60),
					Size = UDim2.new(1, -32, 0, 292),
					ZIndex = 42,
					[Children] = {
						scope:New "UIGridLayout" {
							CellPadding = UDim2.fromOffset(8, 8),
							CellSize = UDim2.new(0.5, -4, 0, 66),
							SortOrder = Enum.SortOrder.LayoutOrder,
						},
						rows,
					} :: { Fusion.Child },
				},
				Button(scope, {
					Name = "GotIt",
					Text = "Понятно!",
					Icon = "👍",
					Color = Theme.Colors.ButtonPrimary,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -14),
					Size = UDim2.fromOffset(240, 56),
					ZIndex = 42,
					OnClick = function()
						state.modal:set("")
					end,
				}),
			},
		}),
	})
end

return BattleOverlays
