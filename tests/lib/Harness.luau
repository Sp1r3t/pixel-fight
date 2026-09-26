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

export type Client = {
	player: any,
	runtime: RobloxRuntime.Runtime,
	loader: RobloxRequire.Loader,
	gui: () -> any,
	click: (text: string) -> (),
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
	addClient: (name: string) -> Client,
	step: (frames: number?) -> (),
	serverRequire: (...string) -> any,
	errors: () -> { string },
	warnings: () -> { string },
}

local Harness = {}

function Harness.new(options: { latencyFrames: number?, dropEveryNth: number?, screenSize: Vector2? }?): Game
	local world = RobloxRuntime.newWorld({ screenSize = if options then options.screenSize else nil })
	local channelsLoader = RobloxRequire.new()
	local channels = channelsLoader.require(channelsLoader.get("ReplicatedStorage", "Shared", "Net", "Channels"))
	local hub = NetHub.new({
		latencyFrames = if options then options.latencyFrames else 0,
		dropEveryNth = if options then options.dropEveryNth else nil,
		channels = channels,
	})
	table.insert(world.stepHooks, hub.step)

	local server = world.runtime({ isClient = false })
	local serverLoader = RobloxRequire.new({
		globals = server.globals,
		services = server.services,
		overrides = { [TRANSPORT_PATH] = hub.serverTransport() },
	})
	serverLoader.run(serverLoader.get("ServerScriptService", "Server"))

	local game = {} :: Game
	game.world = world
	game.hub = hub
	game.server = server
	game.serverLoader = serverLoader
	game.clients = {}

	function game.serverRequire(...: string): any
		return serverLoader.require(serverLoader.get("ServerScriptService", "Server", ...))
	end

	function game.addClient(name: string): Client
		local player = world.addPlayer(name, #game.clients + 1)
		local runtime = world.runtime({ isClient = true, localPlayer = player })
		local loader = RobloxRequire.new({
			globals = runtime.globals,
			services = runtime.services,
			overrides = { [TRANSPORT_PATH] = hub.clientTransport(player) },
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
		function client.require(...: string): any
			return loader.require(loader.get("StarterPlayer", "StarterPlayerScripts", "Client", ...))
		end
		table.insert(game.clients, client)
		return client
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
