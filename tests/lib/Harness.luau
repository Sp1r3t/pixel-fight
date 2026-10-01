--!strict
--[[
	Harness — «игра целиком» в одном процессе Lune для интеграционных тестов:
	мир Roblox (RobloxRuntime), сервер, любое число клиентов и сетевая петля (NetHub)
	с настраиваемой задержкой и потерей пакетов.

	    local game = Harness.new({ latencyFrames = 3 })
	    local client = game.addClient("Alice")
	    client.click("Тренировка")
	    game.step(30)
]]

local RobloxRuntime = require("./RobloxRuntime")
local RobloxRequire = require("./RobloxRequire")
local NetHub = require("./NetHub")

local TRANSPORT_PATH = "src/shared/Net/Transport.luau"
local PROFILE_BACKEND_PATH = "src/server/Data/ProfileStoreBackend.luau"

export type Client = {
	player: any,
	runtime: RobloxRuntime.Runtime,
	loader: RobloxRequire.Loader,
	gui: () -> any,
	click: (text: string) -> (),
	press: (name: string) -> (),
	leaveBattle: () -> (),
	find: (name: string) -> any,
	findText: (text: string, className: string?) -> any,
	require: (...string) -> any,
}

export type Game = {
	world: RobloxRuntime.World,
	hub: NetHub.Hub,
	server: RobloxRuntime.Runtime,
	serverLoader: RobloxRequire.Loader,
	clients: { Client },
	addClient: (name: string, teleportData: any?, userId: number?) -> Client,
	removeClient: (client: Client) -> (),
	step: (frames: number?) -> (),
	serverRequire: (...string) -> any,
	backend: any, -- хранилище профилей в памяти (вместо ProfileStore)
	errors: () -> { string },
	warnings: () -> { string },
}

local Harness = {}

export type Options = {
	latencyFrames: number?,
	dropEveryNth: number?,
	screenSize: Vector2?,
	-- Опубликованная игра / отдельный сервер: для проверки межсерверного подбора.
	studio: boolean?,
	placeId: number?,
	jobId: string?,
	privateServerId: string?,
	memoryStore: any?,
	backend: any?, -- общее хранилище профилей (несколько «серверов» — один объект)
	-- Подмена модулей на сервере и клиентах: путь файла → значение (например, конфиг с тестовыми ID).
	overrides: { [string]: any }?,
	firstUserId: number?, -- с какого UserId нумеровать клиентов (разные «серверы» — разные игроки)
}

function Harness.new(options: Options?): Game
	local function withOverrides(base: { [string]: any }): { [string]: any }
		-- Production access rules remain covered; feature tests explicitly enable test access.
		base["src/shared/Config/TestMode.luau"] = { UnlockAllCharacters = false }
		if options and options.overrides then
			for path, value in options.overrides do
				base[path] = value
			end
		end
		return base
	end

	local world = RobloxRuntime.newWorld({
		screenSize = if options then options.screenSize else nil,
		studio = if options then options.studio else nil,
		memoryStore = if options then options.memoryStore else nil,
	})
	local channelsLoader = RobloxRequire.new()
	local channels = channelsLoader.require(channelsLoader.get("ReplicatedStorage", "Shared", "Net", "Channels"))
	local hub = NetHub.new({
		latencyFrames = if options then options.latencyFrames else 0,
		dropEveryNth = if options then options.dropEveryNth else nil,
		channels = channels,
	})
	table.insert(world.stepHooks, hub.step)

	local server = world.runtime({ isClient = false })
	-- Профили — в памяти (ProfileStore требует DataStore и task.wait, которых в Lune нет).
	local backend = if options and options.backend then options.backend else nil
	if backend == nil then
		local backendLoader = RobloxRequire.new({ globals = server.globals, services = server.services })
		backend =
			backendLoader.require(backendLoader.get("ServerScriptService", "Server", "Data", "MemoryBackend")).new()
	end
	local serverLoader = RobloxRequire.new({
		globals = server.globals,
		services = server.services,
		overrides = withOverrides({ [TRANSPORT_PATH] = hub.serverTransport(), [PROFILE_BACKEND_PATH] = backend }),
		gameProperties = {
			PlaceId = if options and options.placeId then options.placeId else 0,
			JobId = if options and options.jobId then options.jobId else "test-job",
			PrivateServerId = if options and options.privateServerId then options.privateServerId else "",
			PrivateServerOwnerId = 0,
		},
	})
	serverLoader.run(serverLoader.get("ServerScriptService", "Server"))

	local game = {} :: Game
	game.world = world
	game.hub = hub
	game.server = server
	game.serverLoader = serverLoader
	game.backend = backend
	game.clients = {}

	function game.serverRequire(...: string): any
		return serverLoader.require(serverLoader.get("ServerScriptService", "Server", ...))
	end

	local nextUserId = if options and options.firstUserId then options.firstUserId else 1
	function game.addClient(name: string, teleportData: any?, userId: number?): Client
		local player = world.addPlayer(name, userId or nextUserId, teleportData)
		if userId == nil then
			nextUserId += 1
		end
		local runtime = world.runtime({ isClient = true, localPlayer = player })
		local loader = RobloxRequire.new({
			globals = runtime.globals,
			services = runtime.services,
			overrides = withOverrides({ [TRANSPORT_PATH] = hub.clientTransport(player) }),
		})
		loader.run(loader.get("StarterPlayer", "StarterPlayerScripts", "Client"))

		local client = {} :: Client
		client.player = player
		client.runtime = runtime
		client.loader = loader
		function client.gui(): any
			return player:FindFirstChild("PlayerGui"):FindFirstChild("PixelFightUI")
		end
		function client.find(name: string): any
			return runtime.findByName(client.gui(), name)
		end
		function client.findText(text: string, className: string?): any
			return runtime.findGuiByText(client.gui(), text, className)
		end
		function client.click(text: string)
			local button = runtime.findGuiByText(client.gui(), text)
			assert(button, `кнопка "{text}" не найдена`)
			runtime.fire(button, "Activated")
		end
		-- Нажать кнопку-компонент Button по имени (её «лицо» Face).
		function client.press(name: string)
			local node = runtime.findByName(client.gui(), name)
			assert(node, `кнопка {name} не найдена`)
			runtime.fire(node:FindFirstChild("Face") or node, "Activated")
		end
		-- Выйти из боя: пауза → «Выйти».
		function client.leaveBattle()
			client.press("Pause")
			client.click("Выйти")
		end
		function client.require(...: string): any
			return loader.require(loader.get("StarterPlayer", "StarterPlayerScripts", "Client", ...))
		end
		table.insert(game.clients, client)
		return client
	end

	function game.removeClient(client: Client)
		world.removePlayer(client.player)
	end

	function game.step(frames: number?)
		world.step(frames)
	end

	function game.errors(): { string }
		return world.errors
	end

	function game.warnings(): { string }
		return world.warnings
	end

	return game
end

return Harness
