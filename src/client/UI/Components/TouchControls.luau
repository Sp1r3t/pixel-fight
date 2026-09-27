--!strict
--[[
	Сенсорное управление в стиле мобильных файтингов — понятное детям.

	  • слева — «плавающий» джойстик: палец можно поставить в любое место левой части экрана,
	    джойстик появится под ним (не нужно попадать в кружок). Вправо/влево — ходьба, вверх — прыжок,
	    вниз — присед, «назад» от противника — блок, двойной толчок в сторону — рывок;
	  • справа — компактная дуга круглых кнопок с крупными иконками и подписями:
	    👊 Рука, 🦶 Нога, ⬆ Прыжок, 🛡 Блок, ✨ Приём, ⚡ Супер (полоска заряда, светится, когда
	    можно бить), 💨 Рывок (по желанию — включается в настройках);
	  • нажатие засчитывается В МОМЕНТ КАСАНИЯ (не при отпускании) — важно для файтинга;
	  • несколько касаний одновременно (джойстик + кнопка) работают независимо.

	Режим редактирования (экран «Управление»): элементы перетаскиваются, выбранный элемент
	подсвечен; размер и прозрачность меняются кнопками на экране настроек.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local ControlsLayout = require(ReplicatedStorage.Shared.Config.ControlsLayout)
local InputBits = require(ReplicatedStorage.Shared.Combat.InputBits)
local Theme = require(script.Parent.Parent.Theme)

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

type Scope = Fusion.Scope<typeof(Fusion)>
type Layout = ControlsLayout.Layout

export type Props = {
	Layout: Fusion.Value<Layout>,
	UiScale: Fusion.Value<number>,
	Editing: boolean,
	Selected: Fusion.Value<string>?,
	SuperReady: Fusion.UsedAs<boolean>?,
	SuperFill: Fusion.UsedAs<number>?, -- заряд супера 0..1 (полоска на кнопке)
	OnPress: ((bit: number) -> ())?,
	OnHeld: ((mask: number) -> ())?,
}

-- Пороги джойстика в логических пикселях: вверх — с запасом, чтобы не прыгать случайно.
local DEAD_ZONE_X = 18
local DEAD_ZONE_UP = 34
local DEAD_ZONE_DOWN = 26

-- Зона плавающего джойстика: левая часть экрана ниже HUD (доли экрана).
local ZONE_WIDTH = 0.42
local ZONE_TOP = 0.26

type ButtonDef = { id: string, icon: string, label: string, bit: number, color: Color3 }

local BUTTONS: { ButtonDef } = {
	{ id = "Light", icon = "👊", label = "Рука", bit = InputBits.Light, color = Color3.fromHex("#3AA8F0") },
	{ id = "Heavy", icon = "🦶", label = "Нога", bit = InputBits.Heavy, color = Color3.fromHex("#FF7A2E") },
	{ id = "Special", icon = "✨", label = "Приём", bit = InputBits.Special, color = Color3.fromHex("#B45CF0") },
	{ id = "Super", icon = "⚡", label = "Супер", bit = InputBits.Super, color = Color3.fromHex("#FFC21A") },
	{ id = "Dash", icon = "💨", label = "Рывок", bit = InputBits.Dash, color = Color3.fromHex("#2FC46F") },
	{ id = "Jump", icon = "⬆️", label = "Прыжок", bit = InputBits.Up, color = Color3.fromHex("#27B8A0") },
	{ id = "Block", icon = "🛡️", label = "Блок", bit = InputBits.Block, color = Color3.fromHex("#7C8BB0") },
}

local WHITE = Color3.new(1, 1, 1)

-- Стрелки по краям джойстика.
local ARROWS: { { text: string, x: number, y: number } } = {
	{ text = "◀", x = 0.12, y = 0.5 },
	{ text = "▶", x = 0.88, y = 0.5 },
	{ text = "▲", x = 0.5, y = 0.12 },
	{ text = "▼", x = 0.5, y = 0.88 },
}

local function isPointer(input: InputObject): boolean
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.Touch or inputType == Enum.UserInputType.MouseButton1
end

-- Маска направлений по смещению пальца (логические пиксели, Y вниз).
local function directionMask(dx: number, dy: number): number
	local mask = 0
	if dx > DEAD_ZONE_X then
		mask = bit32.bor(mask, InputBits.Right)
	elseif dx < -DEAD_ZONE_X then
		mask = bit32.bor(mask, InputBits.Left)
	end
	if dy < -DEAD_ZONE_UP then
		mask = bit32.bor(mask, InputBits.Up)
	elseif dy > DEAD_ZONE_DOWN then
		mask = bit32.bor(mask, InputBits.Down)
	end
	return mask
end

local TouchControls = {}
TouchControls.directionMask = directionMask
TouchControls.BUTTONS = BUTTONS

local function placementPosition(id: string, placement: ControlsLayout.Placement): UDim2
	if ControlsLayout.SIDE[id] == "Left" then
		return UDim2.new(0, placement.x, 1, -placement.y)
	end
	return UDim2.new(1, -placement.x, 1, -placement.y)
end

function TouchControls.new(scope: Scope, props: Props): Instance
	local layout = props.Layout
	local editing = props.Editing

	local joystickMask = 0
	local buttonMask = 0
	local function publishHeld()
		if props.OnHeld then
			props.OnHeld(bit32.bor(joystickMask, buttonMask))
		end
	end

	-- Перетаскивание в режиме редактирования.
	type Drag = { input: InputObject, id: string, start: Vector3, placement: ControlsLayout.Placement }
	local drag: Drag? = nil

	local function beginDrag(id: string, input: InputObject)
		if props.Selected then
			props.Selected:set(id)
		end
		local placement = peek(layout).controls[id]
		drag = { input = input, id = id, start = input.Position, placement = table.clone(placement) }
	end

	local function updateDrag(input: InputObject)
		local current = drag
		if current == nil then
			return
		end
		if input ~= current.input and input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local scale = math.max(peek(props.UiScale), 0.1)
		local delta = input.Position - current.start
		local sign = if ControlsLayout.SIDE[current.id] == "Left" then 1 else -1
		local updated = ControlsLayout.copy(peek(layout))
		updated.controls[current.id] = {
			x = math.clamp(current.placement.x + sign * delta.X / scale, 20, ControlsLayout.LIMITS.maxX),
			y = math.clamp(current.placement.y - delta.Y / scale, 20, ControlsLayout.LIMITS.maxY),
			size = current.placement.size,
		}
		layout:set(updated)
	end

	-- Джойстик: «ноль» — точка первого касания; кружок переезжает под палец.
	local joystickInput: InputObject? = nil
	local joystickOrigin = Vector3.zero
	local thumbOffset = scope:Value(Vector2.zero)
	-- Где стоит кружок, пока палец держит джойстик (логические пиксели от левого нижнего угла).
	local floatingAt = scope:Value(nil :: Vector2?)

	local function updateJoystick(input: InputObject)
		local scale = math.max(peek(props.UiScale), 0.1)
		local delta = input.Position - joystickOrigin
		local dx, dy = delta.X / scale, delta.Y / scale
		local radius = ControlsLayout.diameter(peek(layout), "Joystick") / 2
		local length = math.sqrt(dx * dx + dy * dy)
		local limit = radius * 0.6
		if length > limit then
			thumbOffset:set(Vector2.new(dx / length * limit, dy / length * limit))
		else
			thumbOffset:set(Vector2.new(dx, dy))
		end
		joystickMask = directionMask(dx, dy)
		publishHeld()
	end

	local function beginJoystick(input: InputObject, float: boolean)
		if joystickInput ~= nil then
			return
		end
		joystickInput = input
		joystickOrigin = input.Position
		if float then
			-- Экранная точка касания → логические координаты от левого нижнего угла.
			-- Position касания считается без верхней панели Roblox, а интерфейс — с ней (IgnoreGuiInset).
			local scale = math.max(peek(props.UiScale), 0.1)
			local camera = Workspace.CurrentCamera
			local screenHeight = if camera then camera.ViewportSize.Y else 0
			if screenHeight > 0 then
				local inset = GuiService:GetGuiInset()
				local radius = ControlsLayout.diameter(peek(layout), "Joystick") / 2
				local x = math.max(input.Position.X / scale, radius * 0.7)
				local y = math.max((screenHeight - input.Position.Y - inset.Y) / scale, radius * 0.7)
				floatingAt:set(Vector2.new(x, y))
			end
		end
		updateJoystick(input)
	end

	local function releaseJoystick()
		joystickInput = nil
		thumbOffset:set(Vector2.zero)
		floatingAt:set(nil)
		joystickMask = 0
		publishHeld()
	end

	-- Кнопки: какие касания держат какие кнопки.
	local buttonInputs: { [InputObject]: number } = {}
	local pressedButtons = scope:Value({} :: { [string]: boolean })

	local function setPressed(id: string, value: boolean)
		local pressed = table.clone(peek(pressedButtons))
		if value then
			pressed[id] = true
		else
			pressed[id] = nil
		end
		pressedButtons:set(pressed)
	end

	local function releaseButton(input: InputObject)
		local bit = buttonInputs[input]
		if bit == nil then
			return
		end
		buttonInputs[input] = nil
		buttonMask = 0
		for _, heldBit in buttonInputs do
			buttonMask = bit32.bor(buttonMask, heldBit)
		end
		for _, button in BUTTONS do
			if button.bit == bit then
				setPressed(button.id, false)
			end
		end
		publishHeld()
	end

	table.insert(
		scope,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if editing then
				updateDrag(input)
			elseif input == joystickInput then
				updateJoystick(input)
			end
		end)
	)
	table.insert(
		scope,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if editing then
				if drag and (input == drag.input or input.UserInputType == Enum.UserInputType.MouseButton1) then
					drag = nil
				end
				return
			end
			if input == joystickInput then
				releaseJoystick()
			end
			releaseButton(input)
		end)
	)
	-- При уходе с экрана ничего не должно остаться «зажатым».
	table.insert(scope, function()
		joystickMask = 0
		buttonMask = 0
		publishHeld()
	end)

	local function isSelected(use: Fusion.Use, id: string): boolean
		return editing and props.Selected ~= nil and use(props.Selected) == id
	end

	local function sizeOf(use: Fusion.Use, id: string): UDim2
		local diameter = ControlsLayout.diameter(use(layout), id)
		return UDim2.fromOffset(diameter, diameter)
	end

	local opacity = scope:Computed(function(use)
		return use(layout).opacity
	end)

	local joystick = scope:New "Frame" {
		Name = "Joystick",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromHex("#1A1433"),
		BackgroundTransparency = scope:Computed(function(use)
			return 1 - use(opacity) * 0.55
		end),
		Position = scope:Computed(function(use)
			local at = use(floatingAt)
			if at then
				return UDim2.new(0, at.X, 1, -at.Y)
			end
			return placementPosition("Joystick", use(layout).controls.Joystick)
		end),
		Size = scope:Computed(function(use)
			return sizeOf(use, "Joystick")
		end),
		ZIndex = 2,
		[OnEvent "InputBegan"] = function(input: InputObject)
			if not isPointer(input) then
				return
			end
			if editing then
				beginDrag("Joystick", input)
			else
				beginJoystick(input, false)
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			scope:New "UIStroke" {
				Color = scope:Computed(function(use)
					return if isSelected(use, "Joystick") then Theme.Colors.Accent else WHITE
				end),
				Thickness = scope:Computed(function(use)
					return if isSelected(use, "Joystick") then 5 else 3
				end),
				Transparency = scope:Computed(function(use)
					return 1 - use(opacity)
				end),
			},
			-- Стрелки-подсказки по краям круга.
			(function(): { Instance }
				local arrows: { Instance } = {}
				for _, arrow in ARROWS do
					table.insert(
						arrows,
						scope:New "TextLabel" {
							Name = "Arrow",
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundTransparency = 1,
							Font = Theme.Fonts.Title,
							Position = UDim2.fromScale(arrow.x, arrow.y),
							Size = UDim2.fromScale(0.2, 0.2),
							Text = arrow.text,
							TextColor3 = WHITE,
							TextScaled = true,
							TextTransparency = scope:Computed(function(use)
								return 1 - use(opacity) * 0.8
							end),
							ZIndex = 3,
						}
					)
				end
				return arrows
			end)(),
			scope:New "Frame" {
				Name = "Thumb",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = scope:Computed(function(use)
					return 1 - use(opacity) * 0.9
				end),
				Position = scope:Computed(function(use)
					local offset = use(thumbOffset)
					return UDim2.new(0.5, offset.X, 0.5, offset.Y)
				end),
				Size = UDim2.fromScale(0.42, 0.42),
				ZIndex = 4,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					scope:New "UIStroke" {
						Color = Theme.Colors.Outline,
						Thickness = 3,
						Transparency = scope:Computed(function(use)
							return 1 - use(opacity)
						end),
					},
				},
			},
		} :: { Fusion.Child },
	}

	-- Невидимая зона слева: касание в любом её месте ставит джойстик под палец.
	local zone: { Instance } = {}
	if not editing then
		table.insert(
			zone,
			scope:New "Frame" {
				Name = "JoystickZone",
				Active = true,
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0, ZONE_TOP),
				Size = UDim2.fromScale(ZONE_WIDTH, 1 - ZONE_TOP),
				ZIndex = 1,
				[OnEvent "InputBegan"] = function(input: InputObject)
					if isPointer(input) then
						beginJoystick(input, true)
					end
				end,
			}
		)
	end

	local superReady = scope:Computed(function(use)
		return if props.SuperReady ~= nil then use(props.SuperReady) else true
	end)

	local buttons: { Instance } = {}
	for _, button in BUTTONS do
		local id = button.id
		local isSuper = id == "Super"
		local pressed = scope:Computed(function(use)
			return use(pressedButtons)[id] == true
		end)
		local ready = scope:Computed(function(use)
			return not isSuper or use(superReady)
		end)
		local pressScale = scope:Spring(
			scope:Computed(function(use)
				return if use(pressed) then 0.86 else 1
			end),
			40,
			0.7
		)

		local extras: { Instance } = {}
		if isSuper and not editing then
			-- Полоска заряда супера под иконкой; когда полная — прячется, кнопка светится.
			local fill = scope:Computed(function(use)
				return if props.SuperFill ~= nil then math.clamp(use(props.SuperFill), 0, 1) else 1
			end)
			table.insert(
				extras,
				scope:New "Frame" {
					Name = "Charge",
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = Theme.Colors.Outline,
					BackgroundTransparency = 0.2,
					BorderSizePixel = 0,
					Position = UDim2.fromScale(0.5, 0.64),
					Size = UDim2.fromScale(0.56, 0.1),
					Visible = scope:Computed(function(use)
						return not use(ready)
					end),
					ZIndex = 6,
					[Children] = {
						scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
						scope:New "Frame" {
							Name = "Fill",
							BackgroundColor3 = Theme.Colors.Accent,
							BorderSizePixel = 0,
							Size = scope:Computed(function(use)
								return UDim2.fromScale(use(fill), 1)
							end),
							ZIndex = 7,
							[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
						},
					},
				}
			)
		end

		table.insert(
			buttons,
			scope:New "TextButton" {
				Name = `{id}Button`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = button.color,
				BackgroundTransparency = scope:Computed(function(use)
					local base = 1 - use(opacity)
					if not use(ready) then
						return math.min(0.85, base + 0.3)
					end
					return if use(pressed) then math.max(0, base - 0.3) else base
				end),
				Font = Theme.Fonts.Title,
				Position = scope:Computed(function(use)
					return placementPosition(id, use(layout).controls[id])
				end),
				Size = scope:Computed(function(use)
					return sizeOf(use, id)
				end),
				Text = "",
				Visible = scope:Computed(function(use)
					return id ~= "Dash" or use(layout).dashButton
				end),
				ZIndex = 5,
				[OnEvent "InputBegan"] = function(input: InputObject)
					if not isPointer(input) then
						return
					end
					if editing then
						beginDrag(id, input)
						return
					end
					buttonInputs[input] = button.bit
					buttonMask = bit32.bor(buttonMask, button.bit)
					setPressed(id, true)
					if props.OnPress then
						props.OnPress(button.bit)
					end
					publishHeld()
				end,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = scope:Computed(function(use)
							if isSelected(use, id) then
								return Theme.Colors.Accent
							end
							return if isSuper and use(ready) then Theme.Colors.Accent else WHITE
						end),
						Thickness = scope:Computed(function(use)
							if isSelected(use, id) or (isSuper and use(ready) and not editing) then
								return 5
							end
							return 3
						end),
						Transparency = scope:Computed(function(use)
							return if use(ready) then 0.05 else 0.55
						end),
					},
					scope:New "TextLabel" {
						Name = "Icon",
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Title,
						Position = UDim2.fromScale(0.5, 0.42),
						Size = UDim2.fromScale(0.5, 0.5),
						Text = button.icon,
						TextColor3 = WHITE,
						TextScaled = true,
						TextTransparency = scope:Computed(function(use)
							return if use(ready) then 0 else 0.45
						end),
						ZIndex = 6,
					},
					scope:New "TextLabel" {
						Name = "Label",
						AnchorPoint = Vector2.new(0.5, 0),
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Title,
						Position = UDim2.fromScale(0.5, 0.7),
						Size = UDim2.fromScale(0.8, 0.18),
						Text = button.label,
						TextColor3 = WHITE,
						TextScaled = true,
						TextStrokeTransparency = 0.4,
						TextTransparency = scope:Computed(function(use)
							return if use(ready) then 0 else 0.45
						end),
						Visible = scope:Computed(function(use)
							-- У супера во время зарядки вместо подписи — полоска заряда.
							return not isSuper or use(ready) or editing
						end),
						ZIndex = 6,
					},
					scope:New "UIScale" {
						Scale = pressScale,
					},
					extras,
				} :: { Fusion.Child },
			}
		)
	end

	return scope:New "Frame" {
		Name = "TouchControls",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			zone,
			joystick,
			buttons,
		} :: { Fusion.Child },
	}
end

return TouchControls
