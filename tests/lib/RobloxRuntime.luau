--!strict
--[[
	Эмуляция рантайма Roblox для тестов в Lune.

	World (мир) — общие для сервера и клиентов: инстансы, часы, планировщик задач, игроки,
	ошибки. Runtime — «точка зрения» внутри мира: сервер или конкретный клиент со своими
	сервисами (Players.LocalPlayer, RunService:IsClient() и т.д.) и глобальными переменными.

	• Инстансы — прокси над инстансами @lune/roblox: имена и типы свойств проверяются
	  по базе Roblox API (опечатка в свойстве = ошибка теста, как в Studio).
	• События (Activated, MouseEnter, ...) — фейковые сигналы, тест может их «нажать».
	• Время и планировщик управляются тестом: world.step(кадры).
	• Все ошибки (в т.ч. из task.spawn внутри Fusion) и warn() собираются в world.errors / world.warnings.
]]

local roblox = require("@lune/roblox")
local FakeMemoryStore = require("./FakeMemoryStore")

local RobloxRuntime = {}

--[[
	В Roblox значения Enum уникальны, поэтому их можно использовать как ключи таблиц
	(например, KEYMAP[input.KeyCode]). В Lune каждое обращение создаёт новый объект,
	поэтому оборачиваем Enum кешем: одно и то же значение — один и тот же объект.
]]
local enumItemCache: { [string]: any } = {}

local function canonicalItem(item: any): any
	if typeof(item) ~= "EnumItem" then
		return item
	end
	local key = tostring(item)
	local cached = enumItemCache[key]
	if cached == nil then
		enumItemCache[key] = item
		cached = item
	end
	return cached
end

local enumProxies: { [string]: any } = {}
local CanonicalEnum = setmetatable({}, {
	__index = function(_, enumName: string): any
		local proxy = enumProxies[enumName]
		if proxy then
			return proxy
		end
		local realEnum = (roblox.Enum :: any)[enumName]
		proxy = setmetatable({}, {
			__index = function(_, itemName: string): any
				local value = realEnum[itemName]
				if type(value) == "function" then
					return function(_self: any, ...: any): any
						local result = value(realEnum, ...)
						if type(result) == "table" then
							for index, item in result do
								result[index] = canonicalItem(item)
							end
						end
						return result
					end
				end
				return canonicalItem(value)
			end,
		})
		enumProxies[enumName] = proxy
		return proxy
	end,
})
RobloxRuntime.Enum = CanonicalEnum
RobloxRuntime.canonicalItem = canonicalItem

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
		"OnServerEvent",
		"OnClientEvent",
		"Touched",
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
	world: World,
	isClient: boolean,
	globals: { [string]: any },
	services: { [string]: any },
	errors: { string },
	warnings: { string },
	localPlayer: any,
	keysDown: { [string]: boolean }, -- клавиши, «зажатые» тестом (UserInputService:IsKeyDown)
	pressKey: (keyName: string) -> (),
	releaseKey: (keyName: string) -> (),
	step: (frames: number?) -> (),
	fire: (instance: any, eventName: string, ...any) -> (),
	findGuiByText: (root: any, text: string, className: string?) -> any,
	findByName: (root: any, name: string) -> any,
	unwrap: (instance: any) -> any,
}

export type Teleport = {
	placeId: number,
	players: { any },
	accessCode: string?,
	serverInstanceId: string?,
	data: any?,
}

export type World = {
	errors: { string },
	studio: boolean,
	teleports: { Teleport }, -- все вызовы TeleportService:TeleportAsync
	prompts: { { kind: string, player: any, id: number } }, -- окна покупок, открытые клиентами
	ownedPasses: { [string]: boolean }, -- "UserId:PassId" → куплен ли Game Pass
	reservedCount: number,
	memoryStore: any,
	warnings: { string },
	screenSize: Vector2,
	players: { any },
	runtimes: { Runtime },
	clock: () -> number,
	newSignal: () -> Signal,
	addPlayer: (name: string, userId: number) -> any,
	removePlayer: (player: any) -> (),
	runtime: (options: { isClient: boolean, localPlayer: any? }) -> Runtime,
	step: (frames: number?) -> (),
	stepHooks: { () -> () },
	proxyOf: (real: any) -> any,
	unwrap: (value: any) -> any,
}

export type WorldOptions = {
	screenSize: Vector2?,
	studio: boolean?, -- RunService:IsStudio() (по умолчанию true)
	memoryStore: any?, -- общий FakeMemoryStore (несколько «серверов» — один объект)
}

function RobloxRuntime.newWorld(options: WorldOptions?): World
	local world = {} :: World
	world.errors = {}
	world.warnings = {}
	world.screenSize = if options and options.screenSize then options.screenSize else roblox.Vector2.new(1280, 720)
	world.players = {}
	world.runtimes = {}
	world.stepHooks = {}
	world.studio = if options and options.studio ~= nil then options.studio else true
	world.teleports = {}
	world.reservedCount = 0
	world.prompts = {}
	world.ownedPasses = {}

	local clock = 0
	local deferred: { { any } } = {}
	local delayed: { { at: number, args: { any } } } = {}

	local signalSet: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local connectionSet: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local tweenInfoSet: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local randomSet: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

	-- Как и в Roblox, os.clock() строго растёт даже внутри одного кадра
	-- (Fusion 0.3 сравнивает отметки времени изменений).
	function world.clock(): number
		clock += 1e-7
		return clock
	end

	world.memoryStore = if options and options.memoryStore
		then options.memoryStore
		else FakeMemoryStore.new(world.clock)

	local function recordError(err: any)
		table.insert(world.errors, tostring(err))
	end

	local function safeCall(callback: (...any) -> ...any, ...: any)
		local ok, err = pcall(callback, ...)
		if not ok then
			recordError(err)
		end
	end

	function world.newSignal(): Signal
		local listeners: { { callback: (...any) -> () } } = {}
		local signal = {}
		function signal.Connect(_self: any, callback: (...any) -> ()): any
			local entry = { callback = callback }
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
	local newSignal = world.newSignal

	------------------------------------------------------------------------------------------
	-- Прокси над инстансами Lune (общие для всего мира).
	------------------------------------------------------------------------------------------
	type ProxyData = {
		real: any,
		signals: { [string]: Signal },
		propertySignals: { [string]: Signal },
		overrides: { [string]: any }, -- свойства, которых Lune не хранит (UserId, CurrentCamera, ...)
	}
	local proxyData: { [any]: ProxyData } = setmetatable({}, { __mode = "k" }) :: any
	local proxyOfReal: { [any]: any } = setmetatable({}, { __mode = "v" }) :: any

	local proxyOf: (real: any) -> any
	local function unwrap(value: any): any
		local data = proxyData[value]
		return if data then data.real else value
	end
	world.unwrap = unwrap

	local function getSignal(data: ProxyData, name: string): Signal
		local signal = data.signals[name]
		if signal == nil then
			signal = newSignal()
			data.signals[name] = signal
		end
		return signal
	end

	local function propertySignal(data: ProxyData, property: string): Signal
		local signal = data.propertySignals[property]
		if signal == nil then
			signal = newSignal()
			data.propertySignals[property] = signal
		end
		return signal
	end

	local function wrapOrNil(real: any): any
		return if real then proxyOf(real) else nil
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
			return wrapOrNil(proxyData[self].real:FindFirstChild(name, recursive))
		end,
		FindFirstChildOfClass = function(self: any, className: string): any
			return wrapOrNil(proxyData[self].real:FindFirstChildOfClass(className))
		end,
		FindFirstChildWhichIsA = function(self: any, className: string): any
			return wrapOrNil(proxyData[self].real:FindFirstChildWhichIsA(className))
		end,
		FindFirstAncestorOfClass = function(self: any, className: string): any
			return wrapOrNil(proxyData[self].real:FindFirstAncestorOfClass(className))
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
		IsDescendantOf = function(self: any, ancestor: any): boolean
			return proxyData[self].real:IsDescendantOf(unwrap(ancestor))
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
		Clone = function(self: any): any
			return proxyOf(proxyData[self].real:Clone())
		end,
		GetJoinData = function(self: any): { [string]: any }
			local joinData = proxyData[self].overrides.JoinData
			return if type(joinData) == "table" then joinData else {}
		end,
		SetTeleportData = function(self: any, data: any)
			proxyData[self].overrides.TeleportData = data
		end,
		GetTeleportData = function(self: any): any
			return proxyData[self].overrides.TeleportData
		end,
		GetNetworkPing = function(self: any): number
			local ping = proxyData[self].overrides.NetworkPing
			return if type(ping) == "number" then ping else 0
		end,
		Kick = function(self: any, message: string?)
			proxyData[self].overrides.Kicked = message or ""
		end,
		-- Сетевые методы в тестах не используются (Transport подменяется «петлёй»).
		FireServer = function() end,
		FireClient = function() end,
		FireAllClients = function() end,
	}

	-- Свойства, которые вычисляет движок во время работы (Lune их не знает).
	local function runtimeProperty(data: ProxyData, key: string): (boolean, any)
		local override = data.overrides[key]
		if override ~= nil then
			return true, override
		end
		local real = data.real
		if key == "AbsoluteSize" then
			return true, if real:IsA("LayerCollector") then world.screenSize else roblox.Vector2.zero
		elseif key == "AbsolutePosition" then
			return true, roblox.Vector2.zero
		elseif key == "ViewportSize" and real:IsA("Camera") then
			return true, world.screenSize
		elseif key == "UserId" and real:IsA("Player") then
			return true, 0
		elseif key == "DisplayName" and real:IsA("Player") then
			return true, real.Name
		end
		return false, nil
	end

	local WRITABLE_OVERRIDES: { [string]: boolean } = {
		NetworkPing = true,
		Kicked = true,
		CurrentCamera = true,
		UserId = true,
		DisplayName = true,
		OnServerInvoke = true,
		OnClientInvoke = true,
	}

	local proxyMeta = {
		__index = function(self: any, key: string): any
			local data = proxyData[self]
			local method = methods[key]
			if method ~= nil then
				return method
			end
			if EVENT_NAMES[key] then
				return getSignal(data, key)
			end
			local handled, value = runtimeProperty(data, key)
			if handled then
				return value
			end
			local realValue = data.real[key]
			local valueType = typeof(realValue)
			if valueType == "Instance" then
				return proxyOf(realValue)
			elseif valueType == "EnumItem" then
				return canonicalItem(realValue)
			end
			return realValue
		end,
		__newindex = function(self: any, key: string, value: any)
			local data = proxyData[self]
			if WRITABLE_OVERRIDES[key] then
				data.overrides[key] = value
			else
				data.real[key] = unwrap(value)
			end
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
		proxyData[proxy] = { real = real, signals = {}, propertySignals = {}, overrides = {} }
		proxyOfReal[real] = proxy
		return proxy
	end
	world.proxyOf = proxyOf

	local function newInstance(className: string, parent: any?): any
		local proxy = proxyOf(roblox.Instance.new(className))
		if parent ~= nil then
			proxy.Parent = parent
		end
		return proxy
	end

	------------------------------------------------------------------------------------------
	-- Глобальные функции и типы Roblox.
	------------------------------------------------------------------------------------------
	local function fakeTypeof(value: any): string
		if proxyData[value] then
			return "Instance"
		elseif signalSet[value] then
			return "RBXScriptSignal"
		elseif connectionSet[value] then
			return "RBXScriptConnection"
		elseif tweenInfoSet[value] then
			return "TweenInfo"
		elseif randomSet[value] then
			return "Random"
		end
		return typeof(value)
	end

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

	-- Детерминированный Random (генератор Лемера).
	local RandomLib = {
		new = function(seed: number?): any
			local state = math.floor(seed or 12345) % 2147483647
			if state <= 0 then
				state += 2147483646
			end
			local rng = {}
			local function nextUnit(): number
				state = (state * 48271) % 2147483647
				return state / 2147483647
			end
			function rng.NextNumber(_self: any, min: number?, max: number?): number
				local lo, hi = min or 0, max or 1
				return lo + (hi - lo) * nextUnit()
			end
			function rng.NextInteger(_self: any, min: number, max: number): number
				return min + math.floor(nextUnit() * (max - min + 1))
			end
			randomSet[rng] = true
			return rng
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
	fakeOs.clock = world.clock

	local sharedGlobals: { [string]: any } = {
		typeof = fakeTypeof,
		task = fakeTask,
		os = fakeOs,
		tick = world.clock,
		time = world.clock,
		warn = function(...: any)
			local parts = {}
			for _, part in { ... } do
				table.insert(parts, tostring(part))
			end
			table.insert(world.warnings, table.concat(parts, " "))
		end,
		print = function() end, -- не засоряем вывод тестов
		Instance = { new = newInstance },
		TweenInfo = TweenInfoLib,
		Random = RandomLib,
		Enum = CanonicalEnum,
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
		BrickColor = roblox.BrickColor,
		PhysicalProperties = roblox.PhysicalProperties,
	}

	------------------------------------------------------------------------------------------
	-- Общие сервисы мира.
	------------------------------------------------------------------------------------------
	local workspace = newInstance("Workspace")
	local camera = newInstance("Camera", workspace)
	camera.Name = "Camera"
	workspace.CurrentCamera = camera
	local lighting = newInstance("Lighting")
	local soundService = newInstance("SoundService")

	local playerAdded, playerRemoving = newSignal(), newSignal()

	function world.addPlayer(name: string, userId: number, teleportData: any?): any
		local player = newInstance("Player")
		if teleportData ~= nil then
			proxyData[player].overrides.JoinData = { TeleportData = teleportData }
		end
		player.Name = name
		player.UserId = userId
		player.DisplayName = name
		local playerGui = newInstance("PlayerGui", player)
		playerGui.Name = "PlayerGui"
		-- В Roblox у игрока в игре есть Parent (Players).
		proxyData[player].overrides.Parent = "Players"
		table.insert(world.players, player)
		playerAdded:Fire(player)
		return player
	end

	function world.removePlayer(player: any)
		local index = table.find(world.players, player)
		if index then
			table.remove(world.players, index)
		end
		playerRemoving:Fire(player)
		proxyData[player].overrides.Parent = nil
	end

	------------------------------------------------------------------------------------------
	-- Runtime: сервер или клиент.
	------------------------------------------------------------------------------------------
	function world.runtime(runtimeOptions: { isClient: boolean, localPlayer: any? }): Runtime
		local runtime = {} :: Runtime
		runtime.world = world
		runtime.isClient = runtimeOptions.isClient
		runtime.errors = world.errors
		runtime.warnings = world.warnings
		runtime.keysDown = {}
		runtime.unwrap = unwrap

		local isClient = runtime.isClient
		local localPlayer = runtimeOptions.localPlayer
		if isClient and localPlayer == nil then
			localPlayer = world.addPlayer("TestPlayer", 1)
		end
		runtime.localPlayer = localPlayer

		local renderSteps: { [string]: { priority: number, callback: (number) -> () } } = {}
		local renderStepped, heartbeat, stepped = newSignal(), newSignal(), newSignal()
		local guidCounter = 0

		local inputBegan, inputEnded, inputChanged = newSignal(), newSignal(), newSignal()
		local boundActions: { [string]: { callback: (...any) -> any, keys: { any } } } = {}

		local userInputService = {
			TouchEnabled = false,
			KeyboardEnabled = true,
			GamepadEnabled = false,
			MouseEnabled = true,
			InputBegan = inputBegan,
			InputEnded = inputEnded,
			InputChanged = inputChanged,
			LastInputTypeChanged = newSignal(),
			GamepadConnected = newSignal(),
			GamepadDisconnected = newSignal(),
			IsKeyDown = function(_self: any, keyCode: any): boolean
				return runtime.keysDown[keyCode.Name] == true
			end,
			IsGamepadButtonDown = function(): boolean
				return false
			end,
			GetGamepadState = function(): { any }
				return {}
			end,
			GetConnectedGamepads = function(): { any }
				return {}
			end,
			GetLastInputType = function(): any
				return CanonicalEnum.UserInputType.Keyboard
			end,
			GetFocusedTextBox = function(): any
				return nil
			end,
		}

		runtime.services = {
			Players = {
				LocalPlayer = localPlayer,
				PlayerAdded = playerAdded,
				PlayerRemoving = playerRemoving,
				GetPlayers = function(): { any }
					return table.clone(world.players)
				end,
				GetPlayerByUserId = function(_self: any, userId: number): any
					for _, player in world.players do
						if player.UserId == userId then
							return player
						end
					end
					return nil
				end,
			},
			RunService = {
				RenderStepped = renderStepped,
				Heartbeat = heartbeat,
				Stepped = stepped,
				IsStudio = function(): boolean
					return world.studio
				end,
				IsClient = function(): boolean
					return isClient
				end,
				IsServer = function(): boolean
					return not isClient
				end,
				IsRunning = function(): boolean
					return true
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
			UserInputService = userInputService,
			ContextActionService = {
				BindAction = function(_self: any, name: string, callback: (...any) -> any, _touch: boolean, ...: any)
					boundActions[name] = { callback = callback, keys = { ... } }
				end,
				BindActionAtPriority = function(
					_self: any,
					name: string,
					callback: (...any) -> any,
					_touch: boolean,
					_priority: number,
					...: any
				)
					boundActions[name] = { callback = callback, keys = { ... } }
				end,
				UnbindAction = function(_self: any, name: string)
					boundActions[name] = nil
				end,
			},
			GuiService = {
				GetGuiInset = function(): (Vector2, Vector2)
					return roblox.Vector2.zero, roblox.Vector2.zero
				end,
			},
			Workspace = workspace,
			Lighting = lighting,
			SoundService = soundService,
			MemoryStoreService = world.memoryStore,
			MarketplaceService = {
				ProcessReceipt = nil :: any,
				PromptGamePassPurchaseFinished = newSignal(),
				PromptProductPurchaseFinished = newSignal(),
				UserOwnsGamePassAsync = function(_self: any, userId: number, passId: number): boolean
					return world.ownedPasses[`{userId}:{passId}`] == true
				end,
				PromptGamePassPurchase = function(_self: any, player: any, passId: number)
					table.insert(world.prompts, { kind = "GamePass", player = player, id = passId })
				end,
				PromptProductPurchase = function(_self: any, player: any, productId: number)
					table.insert(world.prompts, { kind = "Product", player = player, id = productId })
				end,
			},
			TeleportService = {
				ReserveServer = function(_self: any, _placeId: number): (string, string)
					world.reservedCount += 1
					return `access-{world.reservedCount}`, `private-{world.reservedCount}`
				end,
				TeleportAsync = function(_self: any, placeId: number, players: { any }, teleportOptions: any?): any
					local entry: Teleport = { placeId = placeId, players = table.clone(players) }
					if teleportOptions ~= nil then
						local data = proxyData[teleportOptions]
						entry.accessCode = teleportOptions.ReservedServerAccessCode
						entry.serverInstanceId = teleportOptions.ServerInstanceId
						entry.data = if data then data.overrides.TeleportData else nil
					end
					table.insert(world.teleports, entry)
					return nil
				end,
			},
		}

		runtime.globals = table.clone(sharedGlobals)
		runtime.globals.workspace = workspace

		-- Нажать/отпустить клавишу: IsKeyDown + InputBegan/InputEnded + привязанные действия.
		local function keyInput(keyName: string, state: any): any
			return {
				KeyCode = (CanonicalEnum.KeyCode :: any)[keyName],
				UserInputType = CanonicalEnum.UserInputType.Keyboard,
				UserInputState = state,
				Position = roblox.Vector3.zero,
				Delta = roblox.Vector3.zero,
			}
		end
		local function dispatchAction(keyName: string, state: any, input: any)
			for name, action in boundActions do
				for _, key in action.keys do
					if key == (CanonicalEnum.KeyCode :: any)[keyName] then
						safeCall(action.callback, name, state, input)
					end
				end
			end
		end
		function runtime.pressKey(keyName: string)
			runtime.keysDown[keyName] = true
			local input = keyInput(keyName, CanonicalEnum.UserInputState.Begin)
			inputBegan:Fire(input, false)
			dispatchAction(keyName, CanonicalEnum.UserInputState.Begin, input)
		end
		function runtime.releaseKey(keyName: string)
			runtime.keysDown[keyName] = nil
			local input = keyInput(keyName, CanonicalEnum.UserInputState.End)
			inputEnded:Fire(input, false)
			dispatchAction(keyName, CanonicalEnum.UserInputState.End, input)
		end

		-- Сигналы кадра этого рантайма (вызывается из world.step).
		(runtime :: any)._stepSignals = function(dt: number)
			if isClient then
				for _, step in renderSteps do
					safeCall(step.callback, dt)
				end
				renderStepped:Fire(dt)
			end
			stepped:Fire(clock, dt)
			heartbeat:Fire(dt)
		end

		runtime.step = world.step
		runtime.fire = function(instance: any, eventName: string, ...: any)
			local data = proxyData[instance]
			assert(data, "fire: ожидался инстанс")
			local signal = data.signals[eventName]
			if signal then
				signal:Fire(...)
			end
		end
		runtime.findGuiByText = function(root: any, text: string, className: string?): any
			for _, descendant in unwrap(root):GetDescendants() do
				if descendant:IsA(className or "TextButton") and descendant.Text == text then
					return proxyOf(descendant)
				end
			end
			return nil
		end
		runtime.findByName = function(root: any, name: string): any
			return wrapOrNil(unwrap(root):FindFirstChild(name, true))
		end

		table.insert(world.runtimes, runtime)
		return runtime
	end

	-- Продвинуть время мира на N кадров по 1/60 с (сервер, клиенты, сеть — синхронно).
	function world.step(frames: number?)
		for _ = 1, frames or 1 do
			local dt = 1 / 60
			clock += dt
			for _, hook in world.stepHooks do
				safeCall(hook)
			end
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
			for _, runtime in world.runtimes do
				((runtime :: any)._stepSignals)(dt)
			end
		end
	end

	return world
end

-- Упрощённый вариант: отдельный мир с одним рантаймом (для простых тестов).
function RobloxRuntime.new(options: { isClient: boolean?, screenSize: Vector2? }?): Runtime
	local world = RobloxRuntime.newWorld({ screenSize = if options then options.screenSize else nil })
	local isClient = if options and options.isClient ~= nil then options.isClient else true
	return world.runtime({ isClient = isClient })
end

return RobloxRuntime
