--!strict
--[[
	Сенсорное управление в стиле мобильных файтингов.

	  • слева — джойстик: движение, вверх — прыжок, вниз — присед; «назад» от противника — блок.
	    Точка первого касания становится «нулём» (удобно: не нужно попадать в центр);
	  • справа — крупные полупрозрачные кнопки «Рука», «Нога», «Особый», «Супер» (светится, когда
	    шкала полная) и маленький «Рывок»;
	  • нажатие засчитывается В МОМЕНТ КАСАНИЯ (не при отпускании) — важно для файтинга;
	  • несколько касаний одновременно (джойстик + кнопка) работают независимо.

	Режим редактирования (экран «Управление»): элементы перетаскиваются, выбранный элемент
	подсвечен; размер и прозрачность меняются кнопками на экране настроек.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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
	OnPress: ((bit: number) -> ())?,
	OnHeld: ((mask: number) -> ())?,
}

-- Пороги джойстика в логических пикселях: вверх — с запасом, чтобы не прыгать случайно.
local DEAD_ZONE_X = 18
local DEAD_ZONE_UP = 34
local DEAD_ZONE_DOWN = 26

local BUTTONS: { { id: string, label: string, bit: number, color: Color3 } } = {
	{ id = "Light", label = "Рука", bit = InputBits.Light, color = Color3.fromHex("#4DC3FF") },
	{ id = "Heavy", label = "Нога", bit = InputBits.Heavy, color = Color3.fromHex("#FF8A3D") },
	{ id = "Special", label = "Особый", bit = InputBits.Special, color = Color3.fromHex("#C77DFF") },
	{ id = "Super", label = "Супер", bit = InputBits.Super, color = Color3.fromHex("#FFC845") },
	{ id = "Dash", label = "Рывок", bit = InputBits.Dash, color = Color3.fromHex("#5BD17A") },
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

	-- Джойстик.
	local joystickInput: InputObject? = nil
	local joystickOrigin = Vector3.zero
	local thumbOffset = scope:Value(Vector2.zero)

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

	local function releaseJoystick()
		joystickInput = nil
		thumbOffset:set(Vector2.zero)
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
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = scope:Computed(function(use)
			return 1 - use(opacity) * 0.35
		end),
		Position = scope:Computed(function(use)
			return placementPosition("Joystick", use(layout).controls.Joystick)
		end),
		Size = scope:Computed(function(use)
			return sizeOf(use, "Joystick")
		end),
		[OnEvent "InputBegan"] = function(input: InputObject)
			if not isPointer(input) then
				return
			end
			if editing then
				beginDrag("Joystick", input)
			elseif joystickInput == nil then
				joystickInput = input
				joystickOrigin = input.Position
				updateJoystick(input)
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			scope:New "UIStroke" {
				Color = scope:Computed(function(use)
					return if isSelected(use, "Joystick") then Theme.Colors.Accent else Color3.new(1, 1, 1)
				end),
				Thickness = scope:Computed(function(use)
					return if isSelected(use, "Joystick") then 4 else 3
				end),
				Transparency = scope:Computed(function(use)
					return 1 - use(opacity)
				end),
			},
			scope:New "Frame" {
				Name = "Thumb",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = scope:Computed(function(use)
					return 1 - use(opacity)
				end),
				Position = scope:Computed(function(use)
					local offset = use(thumbOffset)
					return UDim2.new(0.5, offset.X, 0.5, offset.Y)
				end),
				Size = UDim2.fromScale(0.42, 0.42),
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) },
			},
		},
	}

	local buttons: { Instance } = {}
	for _, button in BUTTONS do
		local id = button.id
		local isSuper = id == "Super"
		local pressed = scope:Computed(function(use)
			return use(pressedButtons)[id] == true
		end)
		local ready = scope:Computed(function(use)
			if not isSuper then
				return true
			end
			return if props.SuperReady ~= nil then use(props.SuperReady) else true
		end)
		local pressScale = scope:Spring(
			scope:Computed(function(use)
				return if use(pressed) then 0.88 else 1
			end),
			40,
			0.7
		)

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
						return math.min(0.9, base + 0.3)
					end
					return if use(pressed) then math.max(0, base - 0.25) else base
				end),
				Font = Theme.Fonts.Body,
				Position = scope:Computed(function(use)
					return placementPosition(id, use(layout).controls[id])
				end),
				Size = scope:Computed(function(use)
					return sizeOf(use, id)
				end),
				Text = button.label,
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextStrokeTransparency = 0.3,
				Visible = scope:Computed(function(use)
					return id ~= "Dash" or use(layout).dashButton
				end),
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
					scope:New "UIPadding" {
						PaddingLeft = UDim.new(0.18, 0),
						PaddingRight = UDim.new(0.18, 0),
						PaddingTop = UDim.new(0.3, 0),
						PaddingBottom = UDim.new(0.3, 0),
					},
					scope:New "UIStroke" {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = scope:Computed(function(use)
							if isSelected(use, id) then
								return Theme.Colors.Accent
							end
							return if isSuper and use(ready) then Theme.Colors.Accent else Color3.new(1, 1, 1)
						end),
						Thickness = scope:Computed(function(use)
							if isSelected(use, id) or (isSuper and use(ready) and not editing) then
								return 5
							end
							return 2
						end),
						Transparency = scope:Computed(function(use)
							return if use(ready) then 0.1 else 0.6
						end),
					},
					scope:New "UIScale" {
						Scale = pressScale,
					},
				},
			}
		)
	end

	return scope:New "Frame" {
		Name = "TouchControls",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		[Children] = {
			joystick,
			buttons,
		} :: { Fusion.Child },
	}
end

return TouchControls
