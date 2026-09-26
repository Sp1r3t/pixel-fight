--!strict
--[[
	InputController — ввод игрока.

	  • ПК: A/D (←/→) — движение, W/Space (↑) — прыжок, S (↓) — присед,
	    J — «Рука» (лёгкий), K — «Нога» (тяжёлый), L — особый приём, I — супер,
	    Shift или двойное нажатие направления — рывок. Блок — движение назад от противника.
	  • Геймпад: левый стик/крестовина, A — прыжок, X — лёгкий, Y — тяжёлый, B — особый,
	    RB/RT — супер, LB/LT — рывок.
	  • Телефон (этап 5): виртуальный джойстик и кнопки через setVirtualHeld / pressVirtual.

	На сервер уходит только маска удерживаемых кнопок и счётчики нажатий (см. Combat/InputBits),
	не чаще 60 раз в секунду: при изменениях сразу, без изменений — раз в KEEPALIVE секунд.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local InputBits = require(ReplicatedStorage.Shared.Combat.InputBits)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local SEND_INTERVAL = 1 / 60
local KEEPALIVE = 0.1
local STICK_DEADZONE = 0.45
local ACTION_NAME = "PixelFightActions"

local KEY_DIRECTIONS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.A] = InputBits.Left,
	[Enum.KeyCode.Left] = InputBits.Left,
	[Enum.KeyCode.D] = InputBits.Right,
	[Enum.KeyCode.Right] = InputBits.Right,
	[Enum.KeyCode.W] = InputBits.Up,
	[Enum.KeyCode.Up] = InputBits.Up,
	[Enum.KeyCode.Space] = InputBits.Up,
	[Enum.KeyCode.S] = InputBits.Down,
	[Enum.KeyCode.Down] = InputBits.Down,
}

local GAMEPAD_DIRECTIONS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.DPadLeft] = InputBits.Left,
	[Enum.KeyCode.DPadRight] = InputBits.Right,
	[Enum.KeyCode.DPadUp] = InputBits.Up,
	[Enum.KeyCode.DPadDown] = InputBits.Down,
	[Enum.KeyCode.ButtonA] = InputBits.Up,
}

local ACTION_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.J] = InputBits.Light,
	[Enum.KeyCode.K] = InputBits.Heavy,
	[Enum.KeyCode.L] = InputBits.Special,
	[Enum.KeyCode.I] = InputBits.Super,
	[Enum.KeyCode.LeftShift] = InputBits.Dash,
	[Enum.KeyCode.RightShift] = InputBits.Dash,
	[Enum.KeyCode.ButtonX] = InputBits.Light,
	[Enum.KeyCode.ButtonY] = InputBits.Heavy,
	[Enum.KeyCode.ButtonB] = InputBits.Special,
	[Enum.KeyCode.ButtonR1] = InputBits.Super,
	[Enum.KeyCode.ButtonR2] = InputBits.Super,
	[Enum.KeyCode.ButtonL1] = InputBits.Dash,
	[Enum.KeyCode.ButtonL2] = InputBits.Dash,
}

export type Platform = "Keyboard" | "Touch" | "Gamepad"

local InputController = {
	Name = "InputController",
}

local platform: Platform = "Keyboard"
local platformListeners: { (Platform) -> () } = {}

local GAMEPAD_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}

local KEYBOARD_TYPES: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Keyboard] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseWheel] = true,
}

local function platformFromInput(inputType: Enum.UserInputType): Platform?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif GAMEPAD_TYPES[inputType] then
		return "Gamepad"
	elseif KEYBOARD_TYPES[inputType] then
		return "Keyboard"
	end
	return nil -- движение мыши и прочее не переключает платформу
end

local function setPlatform(newPlatform: Platform)
	if newPlatform == platform then
		return
	end
	platform = newPlatform
	for _, listener in platformListeners do
		task.spawn(listener, newPlatform)
	end
end

-- Текущая платформа ввода: определяет, показывать ли сенсорное управление и какие подсказки.
function InputController.getPlatform(): Platform
	return platform
end

function InputController.onPlatformChanged(listener: (Platform) -> ())
	table.insert(platformListeners, listener)
end

local active = false
local counters = table.create(#InputBits.ACTIONS, 0)
local virtualHeld = 0
local seq = 0
local lastSendTime = -math.huge
local lastSentHeld = -1
local lastSentCounters = -1
local actionKeys: { Enum.KeyCode } = {}
for key in ACTION_KEYS do
	table.insert(actionKeys, key)
end

local function actionIndex(bit: number): number?
	return table.find(InputBits.ACTIONS, bit)
end

-- Зарегистрировать нажатие кнопки действия (клавиатура, геймпад, экранная кнопка).
local function registerPress(bit: number)
	local index = actionIndex(bit)
	if index then
		counters[index] = (counters[index] + 1) % 16
	end
end

local function readHeld(): number
	if UserInputService:GetFocusedTextBox() ~= nil then
		return 0 -- игрок печатает в чате
	end
	local held = virtualHeld
	for key, bit in KEY_DIRECTIONS do
		if UserInputService:IsKeyDown(key) then
			held = bit32.bor(held, bit)
		end
	end
	for key, bit in ACTION_KEYS do
		if key.Name:sub(1, 6) ~= "Button" and UserInputService:IsKeyDown(key) then
			held = bit32.bor(held, bit)
		end
	end
	if not UserInputService.GamepadEnabled then
		return InputBits.sanitize(held)
	end
	for key, bit in GAMEPAD_DIRECTIONS do
		if UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key) then
			held = bit32.bor(held, bit)
		end
	end
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local position = input.Position
			if position.X < -STICK_DEADZONE then
				held = bit32.bor(held, InputBits.Left)
			elseif position.X > STICK_DEADZONE then
				held = bit32.bor(held, InputBits.Right)
			end
			if position.Y > STICK_DEADZONE then
				held = bit32.bor(held, InputBits.Up)
			elseif position.Y < -STICK_DEADZONE then
				held = bit32.bor(held, InputBits.Down)
			end
		end
	end
	return InputBits.sanitize(held)
end

local function onAction(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not active then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		local bit = ACTION_KEYS[input.KeyCode]
		if bit then
			registerPress(bit)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function send(now: number)
	local held = readHeld()
	local packed = InputBits.packCounters(counters)
	local changed = held ~= lastSentHeld or packed ~= lastSentCounters
	if not changed and now - lastSendTime < KEEPALIVE then
		return
	end
	seq += 1
	lastSendTime = now
	lastSentHeld = held
	lastSentCounters = packed
	Transport.fireServer("Input", seq, held, packed)
end

local function onRenderStep()
	if not active then
		return
	end
	local now = os.clock()
	if now - lastSendTime < SEND_INTERVAL * 0.95 then
		return
	end
	send(now)
end

-- Включить/выключить отправку ввода (только во время боя).
function InputController.setActive(enabled: boolean)
	if enabled == active then
		return
	end
	active = enabled
	virtualHeld = 0
	if enabled then
		ContextActionService:BindActionAtPriority(
			ACTION_NAME,
			onAction,
			false,
			Enum.ContextActionPriority.High.Value,
			table.unpack(actionKeys)
		)
		lastSentHeld = -1
	else
		ContextActionService:UnbindAction(ACTION_NAME)
		-- Сообщить серверу, что всё отпущено.
		seq += 1
		Transport.fireServer("Input", seq, 0, InputBits.packCounters(counters))
	end
end

function InputController.isActive(): boolean
	return active
end

-- Экранные элементы управления (телефон): удерживаемые направления.
function InputController.setVirtualHeld(mask: number)
	virtualHeld = InputBits.sanitize(mask)
end

-- Экранная кнопка действия нажата.
function InputController.pressVirtual(bit: number)
	if active then
		registerPress(bit)
	end
end

-- Текущая маска удерживаемых кнопок (для UI и тестов).
function InputController.getHeld(): number
	return readHeld()
end

function InputController.Init()
	-- Начальная платформа: телефон/планшет без клавиатуры — сенсор.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		platform = "Touch"
	else
		platform = platformFromInput(UserInputService:GetLastInputType()) or "Keyboard"
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local detected = platformFromInput(inputType)
		if detected then
			setPlatform(detected :: Platform)
		end
	end)
end

function InputController.Start()
	RunService:BindToRenderStep("PixelFightInput", Enum.RenderPriority.Input.Value, onRenderStep)
end

return InputController
