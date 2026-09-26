--!strict
--[[
	Эмуляция клиентского рантайма Roblox для смоук-тестов UI в Lune.

	• Инстансы — прокси над инстансами @lune/roblox: имена и типы свойств проверяются
	  по базе Roblox API (опечатка в свойстве = ошибка теста, как в Studio).
	• События (Activated, MouseEnter, ...) — фейковые сигналы, тест может их «нажать».
	• Сервисы Players / RunService / TweenService / ... — минимальные заглушки.
	• Время и планировщик управляются тестом: runtime.step(кадры).
	• Все ошибки (в т.ч. из task.spawn внутри Fusion) и warn() собираются в runtime.errors / runtime.warnings.
]]

local roblox = require("@lune/roblox")

local RobloxRuntime = {}

-- События, которые прокси отдаёт как фейковые сигналы (Lune их не эмулирует).
local EVENT_NAMES: { [string]: boolean } = {}
for _, name in
	{
		"Activated",
		"MouseEnter",
		"MouseLeave",
		"MouseMoved",
		"MouseButton1Down",
		"MouseButton1Up",
		"MouseButton1Click",
		"MouseButton2Click",
		"InputBegan",
		"InputEnded",
		"InputChanged",
		"FocusLost",
		"Focused",
		"Changed",
		"ChildAdded",
		"ChildRemoved",
		"DescendantAdded",
		"DescendantRemoving",
		"AncestryChanged",
		"Destroying",
	}
do
	EVENT_NAMES[name] = true
end

export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> any,
	Once: (self: Signal, callback: (...any) -> ()) -> any,
	Fire: (self: Signal, ...any) -> (),
}

export type Runtime = {
	globals: { [string]: any },
	services: { [string]: any },
	errors: { string },
	warnings: { string },
	screenSize: Vector2,
	localPlayer: any,
	step: (frames: number?) -> (),
	fire: (instance: any, eventName: string, ...any) -> (),
	findGuiByText: (root: any, text: string, className: string?) -> any,
	findByName: (root: any, name: string) -> any,
	unwrap: (instance: any) -> any,
}

function RobloxRuntime.new(options: { isClient: boolean?, screenSize: Vector2? }?): Runtime
	local isClient = if options and options.isClient ~= nil then options.isClient else true
	local runtime = {} :: Runtime
	runtime.errors = {}
	runtime.warnings = {}
	runtime.screenSize = if options and options.screenSize then options.screenSize else roblox.Vector2.new(1280, 720)

	local clock = 0
	local deferred: { { any } } = {}
	local delayed: { { at: number, args: { any } } } = {}

	local signalSet: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local connectionSet: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local tweenInfoSet: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	local function recordError(err: any)
		table.insert(runtime.errors, tostring(err))
	end

	local function safeCall(callback: (...any) -> ...any, ...: any)
		local ok, err = pcall(callback, ...)
		if not ok then
			recordError(err)
		end
	end

	local function newSignal(): Signal
		local listeners: { { callback: (...any) -> (), once: boolean } } = {}
		local signal = {}
		function signal.Connect(_self: any, callback: (...any) -> ()): any
			local entry = { callback = callback, once = false }
			table.insert(listeners, entry)
			local connection = { Connected = true }
			function connection.Disconnect(conn: any)
				conn.Connected = false
				local index = table.find(listeners, entry)
				if index then
					table.remove(listeners, index)
				end
			end
			connectionSet[connection] = true
			return connection
		end
		function signal.Once(self: any, callback: (...any) -> ()): any
			local connection
			connection = self:Connect(function(...)
				connection:Disconnect()
				callback(...)
			end)
			return connection
		end
		function signal.Fire(_self: any, ...: any)
			for _, entry in table.clone(listeners) do
				safeCall(entry.callback, ...)
			end
		end
		function signal.Wait(_self: any)
			error("Signal:Wait() не поддерживается в тестах")
		end
		signalSet[signal] = true
		return signal :: any
	end

	-- Прокси над инстансами Lune.
	type ProxyData = {
		real: any,
		signals: { [string]: Signal },
		propertySignals: { [string]: Signal },
	}
	local proxyData: { [any]: ProxyData } = setmetatable({}, { __mode = "k" }) :: any
	local proxyOfReal: { [any]: any } = setmetatable({}, { __mode = "v" }) :: any

	local proxyOf: (real: any) -> any
	local function unwrap(value: any): any
		local data = proxyData[value]
		return if data then data.real else value
	end
	runtime.unwrap = unwrap

	local function propertySignal(data: ProxyData, property: string): Signal
		local signal = data.propertySignals[property]
		if signal == nil then
			signal = newSignal()
			data.propertySignals[property] = signal
		end
		return signal
	end

	local methods: { [string]: (self: any, ...any) -> ...any } = {
		Destroy = function(self: any)
			local data = proxyData[self]
			local signal = data.signals.Destroying
			if signal then
				signal:Fire()
			end
			data.real.Parent = nil
		end,
		GetPropertyChangedSignal = function(self: any, property: string): Signal
			return propertySignal(proxyData[self], property)
		end,
		IsA = function(self: any, className: string): boolean
			return proxyData[self].real:IsA(className)
		end,
		FindFirstChild = function(self: any, name: string, recursive: boolean?): any
			local found = proxyData[self].real:FindFirstChild(name, recursive)
			return if found then proxyOf(found) else nil
		end,
		FindFirstChildOfClass = function(self: any, className: string): any
			local found = proxyData[self].real:FindFirstChildOfClass(className)
			return if found then proxyOf(found) else nil
		end,
		FindFirstChildWhichIsA = function(self: any, className: string): any
			local found = proxyData[self].real:FindFirstChildWhichIsA(className)
			return if found then proxyOf(found) else nil
		end,
		WaitForChild = function(self: any, name: string): any
			local found = proxyData[self].real:FindFirstChild(name)
			if found == nil then
				error(`WaitForChild: {name} не найден (в тестах нельзя ждать)`, 2)
			end
			return proxyOf(found)
		end,
		GetChildren = function(self: any): { any }
			local result = {}
			for _, child in proxyData[self].real:GetChildren() do
				table.insert(result, proxyOf(child))
			end
			return result
		end,
		GetDescendants = function(self: any): { any }
			local result = {}
			for _, child in proxyData[self].real:GetDescendants() do
				table.insert(result, proxyOf(child))
			end
			return result
		end,
		ClearAllChildren = function(self: any)
			proxyData[self].real:ClearAllChildren()
		end,
		GetFullName = function(self: any): string
			return proxyData[self].real:GetFullName()
		end,
		SetAttribute = function(self: any, name: string, value: any)
			proxyData[self].real:SetAttribute(name, value)
		end,
		GetAttribute = function(self: any, name: string): any
			return proxyData[self].real:GetAttribute(name)
		end,
	}

	local proxyMeta = {
		__index = function(self: any, key: string): any
			local data = proxyData[self]
			local method = methods[key]
			if method ~= nil then
				return method
			end
			if EVENT_NAMES[key] then
				local signal = data.signals[key]
				if signal == nil then
					signal = newSignal()
					data.signals[key] = signal
				end
				return signal
			end
			if key == "AbsoluteSize" then
				return if data.real:IsA("LayerCollector") then runtime.screenSize else roblox.Vector2.zero
			elseif key == "AbsolutePosition" then
				return roblox.Vector2.zero
			end
			local value = data.real[key]
			if typeof(value) == "Instance" then
				return proxyOf(value)
			end
			return value
		end,
		__newindex = function(self: any, key: string, value: any)
			local data = proxyData[self]
			data.real[key] = unwrap(value)
			local signal = data.propertySignals[key]
			if signal then
				signal:Fire()
			end
		end,
		__tostring = function(self: any): string
			return tostring(proxyData[self].real)
		end,
	}

	function proxyOf(real: any): any
		local existing = proxyOfReal[real]
		if existing ~= nil then
			return existing
		end
		local proxy = setmetatable({}, proxyMeta)
		proxyData[proxy] = { real = real, signals = {}, propertySignals = {} }
		proxyOfReal[real] = proxy
		return proxy
	end

	-- Глобальные функции и типы Roblox.
	local function fakeTypeof(value: any): string
		if proxyData[value] then
			return "Instance"
		elseif signalSet[value] then
			return "RBXScriptSignal"
		elseif connectionSet[value] then
			return "RBXScriptConnection"
		elseif tweenInfoSet[value] then
			return "TweenInfo"
		end
		return typeof(value)
	end

	local InstanceLib = {
		new = function(className: string, parent: any?): any
			local proxy = proxyOf(roblox.Instance.new(className))
			if parent ~= nil then
				proxy.Parent = parent
			end
			return proxy
		end,
	}

	local TweenInfoLib = {
		new = function(
			time: number?,
			easingStyle: any?,
			easingDirection: any?,
			repeatCount: number?,
			reverses: boolean?,
			delayTime: number?
		): any
			local info = table.freeze({
				Time = time or 1,
				EasingStyle = easingStyle or roblox.Enum.EasingStyle.Quad,
				EasingDirection = easingDirection or roblox.Enum.EasingDirection.Out,
				RepeatCount = repeatCount or 0,
				Reverses = reverses or false,
				DelayTime = delayTime or 0,
			})
			tweenInfoSet[info] = true
			return info
		end,
	}

	local fakeTask = {
		spawn = function(callback: any, ...: any)
			safeCall(callback, ...)
		end,
		defer = function(callback: any, ...: any)
			table.insert(deferred, { callback, ... })
		end,
		delay = function(seconds: number, callback: any, ...: any)
			table.insert(delayed, { at = clock + seconds, args = { callback, ... } })
		end,
		wait = function(): number
			error("task.wait() не поддерживается в тестах")
		end,
		cancel = function() end,
	}

	local fakeOs = table.clone(os)
	-- Как и в Roblox, os.clock() строго растёт даже внутри одного кадра
	-- (Fusion 0.3 сравнивает отметки времени изменений).
	fakeOs.clock = function(): number
		clock += 1e-7
		return clock
	end

	runtime.globals = {
		typeof = fakeTypeof,
		task = fakeTask,
		os = fakeOs,
		warn = function(...: any)
			local parts = {}
			for _, part in { ... } do
				table.insert(parts, tostring(part))
			end
			table.insert(runtime.warnings, table.concat(parts, " "))
		end,
		print = function() end, -- не засоряем вывод тестов
		Instance = InstanceLib,
		TweenInfo = TweenInfoLib,
		Enum = roblox.Enum,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		NumberRange = roblox.NumberRange,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Rect = roblox.Rect,
		Font = roblox.Font,
	}

	-- Сервисы.
	local renderSteps: { [string]: { priority: number, callback: (number) -> () } } = {}
	local guidCounter = 0
	local renderStepped, heartbeat, stepped = newSignal(), newSignal(), newSignal()

	local player = proxyOf(roblox.Instance.new("Player"))
	player.Name = "TestPlayer"
	local playerGui = proxyOf(roblox.Instance.new("PlayerGui"))
	playerGui.Parent = player
	runtime.localPlayer = player

	runtime.services = {
		Players = {
			LocalPlayer = if isClient then player else nil,
			PlayerAdded = newSignal(),
			PlayerRemoving = newSignal(),
			GetPlayers = function(): { any }
				return { player }
			end,
		},
		RunService = {
			RenderStepped = renderStepped,
			Heartbeat = heartbeat,
			Stepped = stepped,
			IsStudio = function(): boolean
				return true
			end,
			IsClient = function(): boolean
				return isClient
			end,
			IsServer = function(): boolean
				return not isClient
			end,
			BindToRenderStep = function(_self: any, name: string, priority: number, callback: (number) -> ())
				renderSteps[name] = { priority = priority, callback = callback }
			end,
			UnbindFromRenderStep = function(_self: any, name: string)
				renderSteps[name] = nil
			end,
		},
		HttpService = {
			GenerateGUID = function(): string
				guidCounter += 1
				return string.format("00000000-0000-0000-0000-%012d", guidCounter)
			end,
		},
		TweenService = {
			GetValue = function(_self: any, alpha: number): number
				return alpha
			end,
		},
		StarterGui = {
			SetCoreGuiEnabled = function() end,
			SetCore = function() end,
		},
	}

	-- Продвинуть время на N кадров по 1/60 с.
	function runtime.step(frames: number?)
		for _ = 1, frames or 1 do
			local dt = 1 / 60
			clock += dt
			local ready = deferred
			deferred = {}
			for _, entry in ready do
				safeCall(table.unpack(entry))
			end
			for index = #delayed, 1, -1 do
				local entry = delayed[index]
				if entry.at <= clock then
					table.remove(delayed, index)
					safeCall(table.unpack(entry.args))
				end
			end
			for _, step in renderSteps do
				safeCall(step.callback, dt)
			end
			renderStepped:Fire(dt)
			stepped:Fire(clock, dt)
			heartbeat:Fire(dt)
		end
	end

	-- «Нажать» событие инстанса: runtime.fire(button, "Activated").
	function runtime.fire(instance: any, eventName: string, ...: any)
		local data = proxyData[instance]
		assert(data, "fire: ожидался инстанс")
		local signal = data.signals[eventName]
		if signal then
			signal:Fire(...)
		end
	end

	function runtime.findGuiByText(root: any, text: string, className: string?): any
		for _, descendant in unwrap(root):GetDescendants() do
			if descendant:IsA(className or "TextButton") and descendant.Text == text then
				return proxyOf(descendant)
			end
		end
		return nil
	end

	function runtime.findByName(root: any, name: string): any
		local found = unwrap(root):FindFirstChild(name, true)
		return if found then proxyOf(found) else nil
	end

	return runtime
end

return RobloxRuntime
