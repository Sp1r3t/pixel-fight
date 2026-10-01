--!strict
--[[
	Экран «Управление»: настройка сенсорного управления.
	  • элементы на краях экрана можно перетаскивать (редактор — TouchControls в режиме Editing);
	  • размер выбранного элемента и общая прозрачность — кнопками «−»/«+»;
	  • режим показа: Авто (только на сенсорных устройствах) / Всегда / Никогда;
	  • кнопка рывка вкл/выкл; «Сбросить» — раскладка по умолчанию; «Сохранить» — применить и
	    отправить на сервер (сервер проверяет значения, сохранение в профиль — этап 9).
	Также справка по клавишам ПК и геймпада.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local ControlsLayout = require(ReplicatedStorage.Shared.Config.ControlsLayout)
local KeyboardBindings = require(ReplicatedStorage.Shared.Config.KeyboardBindings)
local UserInputService = game:GetService("UserInputService")
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local Panel = require(script.Parent.Parent.Components.Panel)
local ScreenHeader = require(script.Parent.Parent.Components.ScreenHeader)

local Children, peek = Fusion.Children, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>
type Layout = ControlsLayout.Layout

local CONTROL_NAMES: { [string]: string } = {
	Joystick = "Джойстик",
	Light = "Рука",
	Heavy = "Нога",
	Special = "Приём",
	Super = "Супер",
	Dash = "Рывок",
	Jump = "Прыжок",
	Block = "Блок",
}

local MODE_NAMES: { [string]: string } = {
	Auto = "Авто",
	Always = "Всегда",
	Never = "Никогда",
}

local KEY_NAMES: { [string]: string } = {
	MoveLeft = "Влево",
	MoveRight = "Вправо",
	Jump = "Прыжок",
	Crouch = "Присесть",
	Light = "Рука",
	Heavy = "Нога",
	Special = "Приём",
	Super = "Супер",
	Block = "Блок",
	Dash = "Рывок",
}

local function KeyboardPanel(scope: Scope, state: AppState.AppState): Instance
	local selected = scope:Value("")
	local function assign(key: string)
		local action = peek(selected)
		if action == "" then
			return
		end
		if key == "Escape" then
			selected:set("")
			return
		end
		if not KeyboardBindings.isAllowed(key) then
			AppState.notify(state, "Эту клавишу нельзя назначить")
			return
		end
		local draft = ControlsLayout.copy(peek(state.controlsDraft))
		for other, keys in draft.keyboard do
			if other ~= action and table.find(keys, key) then
				AppState.notify(state, `Клавиша уже назначена: {KEY_NAMES[other]}`)
				return
			end
		end
		draft.keyboard[action] = { key }
		state.controlsDraft:set(draft)
		selected:set("")
	end
	table.insert(
		scope,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.UserInputType == Enum.UserInputType.Keyboard then
				assign(input.KeyCode.Name)
			end
		end)
	)
	local rows: { Instance } = {}
	for index, action in KeyboardBindings.actions do
		local x, y = 20 + ((index - 1) // 5) * 330, 44 + ((index - 1) % 5) * 44
		table.insert(
			rows,
			scope:New "TextLabel" {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Text = KEY_NAMES[action],
				TextColor3 = Theme.Colors.Text,
				TextSize = 19,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(150, 36),
			}
		)
		table.insert(
			rows,
			Button(scope, {
				Name = `Bind_{action}`,
				Position = UDim2.fromOffset(x + 150, y),
				Size = UDim2.fromOffset(160, 36),
				TextSize = 15,
				Text = scope:Computed(function(use)
					if use(selected) == action then
						return "Нажми клавишу…"
					end
					local keys = use(state.controlsDraft).keyboard[action]
					if #keys == 2 and keys[1] == "LeftShift" and keys[2] == "RightShift" then
						return "Shift"
					end
					return table
						.concat(keys, " / ")
						:gsub("LeftControl", "L Ctrl")
						:gsub("RightControl", "R Ctrl")
						:gsub("LeftShift", "L Shift")
						:gsub("RightShift", "R Shift")
				end),
				Color = scope:Computed(function(use)
					return if use(selected) == action then Theme.Colors.Accent else Theme.Colors.Button
				end),
				OnClick = function()
					selected:set(if peek(selected) == action then "" else action)
				end,
			})
		)
	end
	table.insert(
		rows,
		scope:New "TextLabel" {
			Name = "KeyboardHelp",
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyRegular,
			Text = "Нажми на действие, затем на новую клавишу. Esc — отмена. После настройки нажми «Сохранить».",
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 15,
			TextWrapped = true,
			Position = UDim2.fromOffset(20, 5),
			Size = UDim2.fromOffset(640, 32),
		}
	)
	table.insert(
		rows,
		Button(scope, {
			Name = "ResetKeyboard",
			Text = "Сбросить",
			Position = UDim2.fromOffset(20, 278),
			Size = UDim2.fromOffset(200, 42),
			OnClick = function()
				local draft = ControlsLayout.copy(peek(state.controlsDraft))
				draft.keyboard = KeyboardBindings.default()
				state.controlsDraft:set(draft)
				selected:set("")
			end,
		})
	)
	table.insert(
		rows,
		Button(scope, {
			Name = "SaveKeyboard",
			Text = "Сохранить",
			Color = Theme.Colors.Success,
			Position = UDim2.fromOffset(460, 278),
			Size = UDim2.fromOffset(200, 42),
			OnClick = function()
				selected:set("")
				state.actions.saveControls(peek(state.controlsDraft))
			end,
		})
	)
	return Panel(scope, {
		Name = "KeyboardPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(680, 334),
		Content = rows,
	})
end

local function Label(scope: Scope, text: Fusion.UsedAs<string>, position: UDim2, size: UDim2): Instance
	return scope:New "TextLabel" {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		Position = position,
		Size = size,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
end

local function ControlsSettings(scope: Scope, state: AppState.AppState): Instance
	-- Черновик: правки видны сразу, но применяются только по «Сохранить».
	state.controlsDraft:set(ControlsLayout.copy(peek(state.controlsLayout)))
	state.controlsTab:set(if peek(state.platform) == "Touch" then "Touch" else "Keyboard")
	local header = ScreenHeader(scope, {
		Title = "УПРАВЛЕНИЕ",
		OnBack = function()
			AppState.back(state)
		end,
	})
	if peek(state.controlsTab) == "Keyboard" then
		return scope:New "Frame" {
			Name = "ControlsSettings",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			[Children] = { header, KeyboardPanel(scope, state) },
		}
	end

	local function edit(mutator: (layout: Layout) -> ())
		local draft = ControlsLayout.copy(peek(state.controlsDraft))
		mutator(draft)
		state.controlsDraft:set(draft)
	end

	local function resize(delta: number)
		edit(function(layout)
			local id = peek(state.controlsSelected)
			local placement = layout.controls[id]
			if placement then
				placement.size =
					math.clamp(placement.size + delta, ControlsLayout.LIMITS.minSize, ControlsLayout.LIMITS.maxSize)
			end
		end)
	end

	local function changeOpacity(delta: number)
		edit(function(layout)
			layout.opacity =
				math.clamp(layout.opacity + delta, ControlsLayout.LIMITS.minOpacity, ControlsLayout.LIMITS.maxOpacity)
		end)
	end

	local modeButtons: { Instance } = {}
	local modes: { ControlsLayout.ShowMode } = { "Auto", "Always", "Never" }
	for index, mode in modes do
		table.insert(
			modeButtons,
			Button(scope, {
				Text = MODE_NAMES[mode],
				Position = UDim2.fromOffset(212 + (index - 1) * 110, 14),
				Size = UDim2.fromOffset(100, 40),
				TextSize = 16,
				Color = scope:Computed(function(use)
					return if use(state.controlsDraft).mode == mode
						then Theme.Colors.ButtonPrimary
						else Theme.Colors.Button
				end),
				OnClick = function()
					edit(function(layout)
						layout.mode = mode :: ControlsLayout.ShowMode
					end)
				end,
			})
		)
	end

	local selectedName = scope:Computed(function(use)
		local id = use(state.controlsSelected)
		local placement = use(state.controlsDraft).controls[id]
		local percent = if placement then math.floor(placement.size * 100 + 0.5) else 100
		return `Размер «{CONTROL_NAMES[id] or id}»: {percent}%`
	end)

	local opacityText = scope:Computed(function(use)
		return `Непрозрачность: {math.floor(use(state.controlsDraft).opacity * 100 + 0.5)}%`
	end)

	return scope:New "Frame" {
		Name = "ControlsSettings",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			header,
			Panel(scope, {
				Name = "Panel",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 70),
				Size = UDim2.fromOffset(560, 266),
				Transparency = 0.08,
				Content = {
					Label(
						scope,
						"Показывать кнопки:",
						UDim2.fromOffset(16, 20),
						UDim2.fromOffset(190, 28)
					),
					modeButtons,
					Label(scope, selectedName, UDim2.fromOffset(16, 66), UDim2.fromOffset(330, 28)),
					Button(scope, {
						Name = "SizeMinus",
						Text = "−",
						Position = UDim2.fromOffset(410, 62),
						Size = UDim2.fromOffset(60, 36),
						OnClick = function()
							resize(-0.1)
						end,
					}),
					Button(scope, {
						Name = "SizePlus",
						Text = "+",
						Position = UDim2.fromOffset(480, 62),
						Size = UDim2.fromOffset(60, 36),
						OnClick = function()
							resize(0.1)
						end,
					}),
					Label(scope, opacityText, UDim2.fromOffset(16, 110), UDim2.fromOffset(330, 28)),
					Button(scope, {
						Name = "OpacityMinus",
						Text = "−",
						Position = UDim2.fromOffset(410, 106),
						Size = UDim2.fromOffset(60, 36),
						OnClick = function()
							changeOpacity(-0.1)
						end,
					}),
					Button(scope, {
						Name = "OpacityPlus",
						Text = "+",
						Position = UDim2.fromOffset(480, 106),
						Size = UDim2.fromOffset(60, 36),
						OnClick = function()
							changeOpacity(0.1)
						end,
					}),
					Button(scope, {
						Name = "DashToggle",
						Text = scope:Computed(function(use)
							return if use(state.controlsDraft).dashButton
								then "Кнопка рывка: вкл"
								else "Кнопка рывка: выкл"
						end),
						Icon = "dash",
						Position = UDim2.fromOffset(16, 152),
						Size = UDim2.fromOffset(250, 40),
						TextSize = 16,
						OnClick = function()
							edit(function(layout)
								layout.dashButton = not layout.dashButton
							end)
						end,
					}),
					Button(scope, {
						Text = "Сбросить",
						Position = UDim2.fromOffset(282, 152),
						Size = UDim2.fromOffset(124, 40),
						TextSize = 16,
						OnClick = function()
							local draft = ControlsLayout.default()
							draft.keyboard = peek(state.controlsDraft).keyboard
							state.controlsDraft:set(draft)
						end,
					}),
					Button(scope, {
						Text = "Сохранить",
						Color = Theme.Colors.ButtonPrimary,
						Position = UDim2.fromOffset(418, 152),
						Size = UDim2.fromOffset(126, 40),
						TextSize = 16,
						OnClick = function()
							state.actions.saveControls(peek(state.controlsDraft))
						end,
					}),
					scope:New "TextLabel" {
						Name = "Help",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.BodyRegular,
						Position = UDim2.fromOffset(16, 204),
						Size = UDim2.fromOffset(528, 56),
						Text = scope:Computed(function(use)
							if use(state.platform) == "Touch" then
								return "Двигай кнопки пальцем. Нажми на кнопку — и меняй её размер «−» / «+». "
									.. "Рывок — двойной толчок джойстика в сторону или кнопка рывка."
							end
							local b = use(state.inputBindings)
							return `Движение: {b.Move}. Прыжок: {b.Jump}. Удары: {b.Light}, {b.Heavy}. `
								.. `Приём: {b.Special}. Супер: {b.Super}. Блок: {b.Block}. Рывок: {b.Dash}.`
						end),
						TextColor3 = Theme.Colors.TextDim,
						TextSize = 14,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
					},
				} :: { Fusion.Child },
			}),
		} :: { Fusion.Child },
	}
end

return ControlsSettings
