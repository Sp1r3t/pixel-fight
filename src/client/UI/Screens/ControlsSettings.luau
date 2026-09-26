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
local AppState = require(script.Parent.Parent.AppState)
local Theme = require(script.Parent.Parent.Theme)
local Button = require(script.Parent.Parent.Components.Button)
local ScreenHeader = require(script.Parent.Parent.Components.ScreenHeader)

local Children, peek = Fusion.Children, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>
type Layout = ControlsLayout.Layout

local CONTROL_NAMES: { [string]: string } = {
	Joystick = "Джойстик",
	Light = "Рука",
	Heavy = "Нога",
	Special = "Особый",
	Super = "Супер",
	Dash = "Рывок",
}

local MODE_NAMES: { [string]: string } = {
	Auto = "Авто",
	Always = "Всегда",
	Never = "Никогда",
}

local PC_HELP = "ПК: A/D — движение, W — прыжок, S — присед, Shift — рывок, J — рука, K — нога, "
	.. "L — особый, I — супер. Геймпад: стик, A — прыжок, X/Y/B — удары, RB — супер, LB — рывок."

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
				Position = UDim2.fromOffset(190 + (index - 1) * 110, 16),
				Size = UDim2.fromOffset(100, 36),
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
			ScreenHeader(scope, {
				Title = "УПРАВЛЕНИЕ",
				OnBack = function()
					AppState.back(state)
				end,
			}),
			scope:New "Frame" {
				Name = "Panel",
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Theme.Colors.Panel,
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, 0, 0, 70),
				Size = UDim2.fromOffset(560, 262),
				[Children] = {
					scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = Theme.Outline,
					},
					Label(
						scope,
						"Сенсорное управление:",
						UDim2.fromOffset(16, 20),
						UDim2.fromOffset(170, 28)
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
						Text = scope:Computed(function(use)
							return if use(state.controlsDraft).dashButton
								then "Кнопка рывка: вкл"
								else "Кнопка рывка: выкл"
						end),
						Position = UDim2.fromOffset(16, 152),
						Size = UDim2.fromOffset(250, 36),
						TextSize = 16,
						OnClick = function()
							edit(function(layout)
								layout.dashButton = not layout.dashButton
							end)
						end,
					}),
					Button(scope, {
						Text = "Сбросить",
						Position = UDim2.fromOffset(290, 152),
						Size = UDim2.fromOffset(120, 36),
						TextSize = 16,
						OnClick = function()
							state.controlsDraft:set(ControlsLayout.default())
						end,
					}),
					Button(scope, {
						Text = "Сохранить",
						Color = Theme.Colors.ButtonPrimary,
						Position = UDim2.fromOffset(420, 152),
						Size = UDim2.fromOffset(120, 36),
						TextSize = 16,
						OnClick = function()
							state.actions.saveControls(peek(state.controlsDraft))
						end,
					}),
					scope:New "TextLabel" {
						Name = "Help",
						BackgroundTransparency = 1,
						Font = Theme.Fonts.BodyRegular,
						Position = UDim2.fromOffset(16, 198),
						Size = UDim2.fromOffset(528, 56),
						Text = "Перетаскивайте кнопки по экрану; нажмите на элемент, чтобы менять его размер. "
							.. PC_HELP,
						TextColor3 = Theme.Colors.TextDim,
						TextSize = 13,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
					},
				} :: { Fusion.Child },
			},
		} :: { Fusion.Child },
	}
end

return ControlsSettings
