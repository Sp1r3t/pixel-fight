-- Мультиплеер: эстафета 2 на 2 (MatchFlow), очередь и комнаты на сервере, бой с компьютером,
-- межсерверный подбор через MemoryStore (несколько «серверов» с общим хранилищем), сервер матча.

local Simulation = requireShared("Combat", "Simulation")
local MatchFlow = requireShared("Combat", "MatchFlow")
local GameConfig = requireShared("Config", "GameConfig")

local RELAY_FRAMES = GameConfig.Team.RelayPauseFrames

----------------------------------------------------------------------------------------------
-- Эстафета в MatchFlow
----------------------------------------------------------------------------------------------

local function relayMatch()
	local sim = Simulation.new({ characters = { "rook", "brakk" } })
	local flow = MatchFlow.new({ roundsToWin = 2, teams = { { "rook", "mira" }, { "brakk", "zip" } } })
	MatchFlow.start(flow, sim)
	return sim, flow
end

local function run(sim, flow, frames, collect)
	for _ = 1, frames do
		Simulation.step(sim, { { held = 0, pressed = 0 }, { held = 0, pressed = 0 } })
		MatchFlow.step(flow, sim)
		if collect then
			for _, event in flow.events do
				table.insert(collect, event)
			end
		end
	end
end

local function runUntil(sim, flow, phase, collect)
	for _ = 1, 2000 do
		if flow.phase == phase then
			return
		end
		run(sim, flow, 1, collect)
	end
	error(`фаза {phase} не наступила`)
end

local function knockOut(sim, slot)
	sim.fighters[slot].health = 0
	sim.fighters[slot].ko = true
end

describe("Эстафета 2 на 2", function()
	it(
		"выбывшего сменяет напарник; победитель остаётся и восстанавливает часть HP",
		function()
			local sim, flow = relayMatch()
			runUntil(sim, flow, "Fight")
			local winner = sim.fighters[1]
			winner.health = 600
			sim.fighters[2].meter = 500
			knockOut(sim, 2)
			local events = {}
			run(sim, flow, 1, events)
			expect(flow.phase).toBe("Relay")
			expect(events[1].kind).toBe("DuelEnd")
			expect(events[1].winner).toBe(1)
			expect(sim.inputEnabled).toBe(false)

			run(sim, flow, RELAY_FRAMES, events)
			expect(flow.phase).toBe("RoundStart")
			local incoming = sim.fighters[2]
			expect(incoming.characterId).toBe("zip")
			expect(incoming.health).toBe(incoming.maxHealth)
			expect(incoming.meter).toBe(500)
			expect(sim.fighters[1].characterId).toBe("rook")
			local lost = winner.maxHealth - 600
			expect(sim.fighters[1].health).toBe(600 + math.floor(lost * GameConfig.Team.RegainFraction + 0.5))
			local relay = events[#events]
			expect(relay.kind).toBe("Relay")
			expect(relay.slot).toBe(2)
			expect(relay.members[1]).toBe(1)
			expect(relay.members[2]).toBe(2)
			-- Новая дуэль: снова «Fight!» и свой таймер.
			runUntil(sim, flow, "Fight")
			expect(flow.timer).toBe(flow.roundFrames)
		end
	)

	it(
		"раунд выигрывает команда, выбившая обоих; во втором раунде порядок обратный",
		function()
			local sim, flow = relayMatch()
			runUntil(sim, flow, "Fight")
			knockOut(sim, 2)
			run(sim, flow, 1)
			runUntil(sim, flow, "Fight")
			expect(sim.fighters[2].characterId).toBe("zip")
			knockOut(sim, 2)
			run(sim, flow, 1)
			expect(flow.phase).toBe("RoundEnd")
			expect(flow.wins[1]).toBe(1)
			expect(flow.wins[2]).toBe(0)

			runUntil(sim, flow, "RoundStart")
			expect(flow.round).toBe(2)
			expect(sim.fighters[1].characterId).toBe("mira")
			expect(sim.fighters[2].characterId).toBe("zip")
			expect(MatchFlow.activeMember(flow, 1)).toBe(2)
			expect(sim.fighters[1].health).toBe(sim.fighters[1].maxHealth)
		end
	)

	it("время вышло: выбывает боец с меньшим % HP", function()
		local sim, flow = relayMatch()
		runUntil(sim, flow, "Fight")
		sim.fighters[1].health = math.floor(sim.fighters[1].maxHealth * 0.4)
		sim.fighters[2].health = math.floor(sim.fighters[2].maxHealth * 0.6)
		flow.timer = 1
		local events = {}
		run(sim, flow, 1, events)
		expect(events[1].kind).toBe("DuelEnd")
		expect(events[1].result).toBe("Time")
		expect(events[1].winner).toBe(2)
		runUntil(sim, flow, "RoundStart")
		expect(sim.fighters[1].characterId).toBe("mira")
		expect(sim.fighters[2].characterId).toBe("brakk")
	end)

	it(
		"двойной K.O. — выходят оба напарника; если выбиты все — ничья раунда",
		function()
			local sim, flow = relayMatch()
			runUntil(sim, flow, "Fight")
			knockOut(sim, 1)
			knockOut(sim, 2)
			runUntil(sim, flow, "RoundStart")
			expect(sim.fighters[1].characterId).toBe("mira")
			expect(sim.fighters[2].characterId).toBe("zip")
			runUntil(sim, flow, "Fight")
			knockOut(sim, 1)
			knockOut(sim, 2)
			local events = {}
			run(sim, flow, 1, events)
			expect(events[1].kind).toBe("RoundEnd")
			expect(events[1].winner).toBe(0)
		end
	)
end)

----------------------------------------------------------------------------------------------
-- Сервер: очередь, комнаты, бой с компьютером
----------------------------------------------------------------------------------------------

local function press(client, name)
	local button = client.find(name)
	assert(button, `нет кнопки {name}`)
	client.runtime.fire(button:FindFirstChild("Face"), "Activated")
end

local function appState(client)
	return client.require("Controllers", "UIController").getState()
end

local function clientPeek(client, value)
	local Fusion = client.loader.require(client.loader.get("ReplicatedStorage", "Packages", "Fusion"))
	return Fusion.peek(value)
end

local function services(game)
	return {
		match = game.serverRequire("Services", "MatchService"),
		mm = game.serverRequire("Services", "MatchmakingService"),
		data = game.serverRequire("Services", "DataService"),
		router = game.serverRequire("Net", "RequestRouter"),
	}
end

local function openMultiplayer(game, clients)
	game.step(3)
	for _, client in clients do
		client.click("Мультиплеер")
	end
	game.step(2)
end

local function stepUntilPhase(game, match, phase)
	for _ = 1, 1500 do
		if match.ended or (match.flow and match.flow.phase == phase) then
			return
		end
		game.step(1)
	end
	error(`фаза {phase} не наступила`)
end

local function finishByKnockouts(game, match, loserSlot)
	for _ = 1, 20 do
		if match.ended then
			return
		end
		stepUntilPhase(game, match, "Fight")
		if match.ended then
			return
		end
		match.sim.fighters[loserSlot].health = 0
		match.sim.fighters[loserSlot].ko = true
		game.step(1)
	end
end

describe("Очередь на сервере", function()
	it(
		"1 на 1: двое в очереди сразу получают матч друг с другом и управляют своими бойцами",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice")
			local bob = game.addClient("Bob")
			openMultiplayer(game, { alice, bob })
			press(alice, "QueueVersus")
			game.step(3)
			expect(alice.find("QueueStatus").Visible).toBe(true)
			expect(alice.find("Headline").Text).toContainMatch("Поиск")
			local s = services(game)
			expect(s.mm.isQueued(alice.player)).toBe(true)

			press(bob, "QueueVersus")
			game.step(8)
			local match = s.match.getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(s.match.getMatchOf(bob.player)).toBe(match)
			expect(match.mode).toBe("Versus")
			expect(match.ranked).toBe(true)
			expect(match.flow.roundsToWin).toBe(GameConfig.RoundsToWin.Versus)
			expect(match.controllers[1].player).toBe(alice.player)
			expect(match.controllers[2].player).toBe(bob.player)
			expect(s.mm.isQueued(alice.player)).toBe(false)
			expect(alice.find("Battle") ~= nil).toBeTruthy()
			expect(bob.find("Battle") ~= nil).toBeTruthy()

			stepUntilPhase(game, match, "Fight")
			local a, b = match.sim.fighters[1], match.sim.fighters[2]
			local ax, bx = a.x, b.x
			alice.runtime.pressKey("A")
			bob.runtime.pressKey("D")
			game.step(20)
			alice.runtime.releaseKey("A")
			bob.runtime.releaseKey("D")
			expect(a.x < ax - 1).toBeTruthy()
			expect(b.x > bx + 1).toBeTruthy()
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)

	it("отмена поиска убирает из очереди", function()
		local game = Harness.new()
		local alice = game.addClient("Alice")
		openMultiplayer(game, { alice })
		press(alice, "QueueTeam")
		game.step(3)
		press(alice, "CancelQueue")
		game.step(3)
		expect(services(game).mm.isQueued(alice.player)).toBe(false)
		expect(alice.find("QueueStatus").Visible).toBe(false)
	end)

	it("победа в онлайн-бою даёт монеты, поражение — нет", function()
		local game = Harness.new()
		local alice = game.addClient("Alice")
		local bob = game.addClient("Bob")
		openMultiplayer(game, { alice, bob })
		press(alice, "QueueVersus")
		press(bob, "QueueVersus")
		game.step(8)
		local s = services(game)
		local match = s.match.getMatchOf(alice.player)
		finishByKnockouts(game, match, 2)
		game.step(5)
		expect(match.ended).toBe(true)
		expect(s.data.getCoins(alice.player)).toBe(GameConfig.Matchmaking.WinReward)
		expect(s.data.getCoins(bob.player)).toBe(0)
		expect(alice.find("Notice").Text).toContainMatch("монет")
	end)

	it("сервер проверяет запросы: режим, персонаж, уже в бою", function()
		local game = Harness.new()
		local alice = game.addClient("Alice")
		game.step(3)
		local s = services(game)
		local cases = {
			{ "QueueJoin", { mode = "Royale", characterId = "rook" }, "BadRequest" },
			{ "QueueJoin", { mode = "Versus", characterId = "ashka" }, "CharacterNotAvailable" },
			{ "RoomCreate", "junk", "BadRequest" },
			{ "RoomJoin", { code = "abc", characterId = "rook" }, "BadCode" },
			{ "RoomJoin", { code = "ZZZZZZ", characterId = "rook" }, "RoomNotFound" },
			{ "StartCpu", { level = 99, characterId = "rook" }, "BadRequest" },
		}
		for index, case in cases do
			local ok, code = s.router.handle(alice.player, case[1], case[2], index * 2)
			expect(ok).toBe(false)
			expect(code).toBe(case[3])
		end
		s.router.handle(alice.player, "StartTraining", { characterId = "rook" }, 50)
		local ok, code = s.router.handle(alice.player, "QueueJoin", { mode = "Versus", characterId = "rook" }, 52)
		expect(ok).toBe(false)
		expect(code).toBe("InMatch")
	end)
end)

describe("2 на 2 (эстафета) по сети", function()
	local function teamGame()
		local game = Harness.new()
		local clients = {}
		for _, name in { "Alice", "Bob", "Cara", "Dan" } do
			table.insert(clients, game.addClient(name))
		end
		openMultiplayer(game, clients)
		game.step(1)
		-- Напарница Alice (Cara) выбирает другого бойца.
		appState(clients[3]).selectedCharacterId:set("mira")
		for _, client in clients do
			press(client, "QueueTeam")
			game.step(1)
		end
		game.step(8)
		local match = services(game).match.getMatchOf(clients[1].player)
		return game, clients, match
	end

	it("команды чередуются по очереди; составы видны всем", function()
		local game, clients, match = teamGame()
		local alice, bob, cara, dan = clients[1], clients[2], clients[3], clients[4]
		expect(match ~= nil).toBeTruthy()
		expect(match.mode).toBe("Team")
		expect(match.teams[1][1].controller.player).toBe(alice.player)
		expect(match.teams[1][2].controller.player).toBe(cara.player)
		expect(match.teams[2][1].controller.player).toBe(bob.player)
		expect(match.teams[2][2].controller.player).toBe(dan.player)
		expect(match.controllers[1].player).toBe(alice.player)
		for _, client in clients do
			expect(client.find("Battle") ~= nil).toBeTruthy()
			expect(client.find("TeamRoster1"):FindFirstChild("Member2") ~= nil).toBeTruthy()
		end
		expect(clientPeek(cara, appState(cara).hud.controlling)).toBe(false)
		expect(cara.find("ControlsHint").Text).toContainMatch("напарник")
		expect(game.errors()).toBeEmpty()
	end)

	it("выбыл первый боец — управление переходит к напарнику", function()
		local game, clients, match = teamGame()
		local alice, cara = clients[1], clients[3]
		stepUntilPhase(game, match, "Fight")
		match.sim.fighters[1].health = 0
		match.sim.fighters[1].ko = true
		game.step(1)
		expect(match.flow.phase).toBe("Relay")
		stepUntilPhase(game, match, "Fight")
		expect(match.controllers[1].player).toBe(cara.player)
		expect(match.sim.fighters[1].characterId).toBe("mira")
		game.step(10)
		expect(clientPeek(cara, appState(cara).hud.controlling)).toBe(true)
		expect(clientPeek(alice, appState(alice).hud.controlling)).toBe(false)
		expect(alice.find("TeamRoster1"):FindFirstChild("Member1"):FindFirstChild("Out").Visible).toBe(true)

		local fighter = match.sim.fighters[1]
		local startX = fighter.x
		alice.runtime.pressKey("A") -- Alice уже не управляет
		game.step(20)
		alice.runtime.releaseKey("A")
		expect(fighter.x).toBeCloseTo(startX, 1e-6)
		cara.runtime.pressKey("D")
		game.step(20)
		cara.runtime.releaseKey("D")
		expect(fighter.x > startX + 1).toBeTruthy()
		expect(game.errors()).toBeEmpty()
	end)

	it("игрок покинул матч — его команда проигрывает", function()
		local game, clients, match = teamGame()
		game.removeClient(clients[4]) -- Dan, команда 2 (ещё ждёт своей очереди)
		game.step(2)
		expect(match.ended).toBe(true)
		local s = services(game)
		expect(s.match.getMatchOf(clients[1].player)).toBe(nil)
		expect(clients[1].find("Notice").Text).toContainMatch("победа")
	end)
end)

describe("Приватные комнаты", function()
	it(
		"хозяин получает код, друг входит по коду — начинается матч без наград",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice")
			local bob = game.addClient("Bob")
			openMultiplayer(game, { alice, bob })
			press(alice, "RoomVersus")
			game.step(3)
			local code = alice.find("RoomCode").Text
			expect(#code).toBe(GameConfig.Matchmaking.RoomCodeLength)
			expect(alice.find("QueueStatus").Visible).toBe(true)

			bob.find("CodeInput").Text = " " .. string.lower(code) .. " "
			press(bob, "JoinRoom")
			game.step(8)
			local s = services(game)
			local match = s.match.getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(match.controllers[2].player).toBe(bob.player)
			expect(match.ranked).toBe(false)
			finishByKnockouts(game, match, 2)
			game.step(5)
			expect(s.data.getCoins(alice.player)).toBe(0)
			expect(game.errors()).toBeEmpty()
		end
	)

	it("неверный код и закрытая комната — понятные сообщения", function()
		local game = Harness.new()
		local alice = game.addClient("Alice")
		local bob = game.addClient("Bob")
		openMultiplayer(game, { alice, bob })
		bob.find("CodeInput").Text = "ab"
		press(bob, "JoinRoom")
		game.step(3)
		expect(bob.find("Notice").Text).toContainMatch("6 букв")
		bob.find("CodeInput").Text = "ZZZZZZ"
		press(bob, "JoinRoom")
		game.step(3)
		expect(bob.find("Notice").Text).toContainMatch("не найдена")

		-- Комната 2 на 2: Bob вошёл, хозяйка вышла — комната закрыта.
		press(alice, "RoomTeam")
		game.step(3)
		bob.find("CodeInput").Text = alice.find("RoomCode").Text
		press(bob, "JoinRoom")
		game.step(3)
		expect(bob.find("Details").Text).toContainMatch("2/4")
		press(alice, "CancelQueue")
		game.step(3)
		expect(bob.find("QueueStatus").Visible).toBe(false)
		expect(bob.find("Notice").Text).toContainMatch("закрыл")
	end)
end)

describe("Против компьютера", function()
	it("кнопка уровня запускает бой до 2 побед с ИИ", function()
		local game = Harness.new()
		local alice = game.addClient("Alice")
		openMultiplayer(game, { alice })
		press(alice, "Cpu8")
		game.step(6)
		local match = services(game).match.getMatchOf(alice.player)
		expect(match ~= nil).toBeTruthy()
		expect(match.mode).toBe("Cpu")
		expect(match.controllers[2].kind).toBe("AI")
		expect(match.flow.roundsToWin).toBe(GameConfig.RoundsToWin.Versus)
		expect(alice.find("FighterPanel2"):FindFirstChild("Name").Text).toContainMatch("%(CPU%)")
		stepUntilPhase(game, match, "Fight")
		game.step(300)
		local player = match.sim.fighters[1]
		expect(player.health < player.maxHealth).toBeTruthy()
		expect(game.errors()).toBeEmpty()
	end)
end)

----------------------------------------------------------------------------------------------
-- Межсерверная очередь (MemoryStore)
----------------------------------------------------------------------------------------------

local quietLoader = newLoader({ globals = { Enum = Enum, warn = function() end } })
local function serverModule(...)
	return quietLoader.require(quietLoader.get("ServerScriptService", "Server", ...))
end
local CrossServer = serverModule("Matchmaking", "CrossServer")
local Protocol = serverModule("Matchmaking", "Protocol")

local function fakeTeleport()
	local count = 0
	return {
		ReserveServer = function()
			count += 1
			return `access-{count}`, `ps-{count}`
		end,
	}
end

local function crossPair()
	local time = 0
	local store = FakeMemoryStore.new(function()
		return time
	end)
	local function make(jobId)
		return CrossServer.new({
			memoryStore = store,
			teleport = fakeTeleport(),
			placeId = 1,
			jobId = jobId,
			now = function()
				return time
			end,
		})
	end
	return store, make("A"), make("B"), function(seconds)
		time += seconds
	end
end

describe("Межсерверная очередь", function()
	it(
		"игроки с разных серверов попадают в один матч; билеты читаются один раз",
		function()
			local _, a, b = crossPair()
			expect(CrossServer.join(a, "Versus", 1, "rook", 10)).toBe(true)
			expect(CrossServer.join(b, "Versus", 2, "mira", 11)).toBe(true)
			local ticket = CrossServer.form(b, "Versus", 2)
			expect(ticket ~= nil).toBeTruthy()
			expect(ticket.roster[1].userId).toBe(1)
			expect(ticket.roster[1].team).toBe(1)
			expect(ticket.roster[2].userId).toBe(2)
			expect(ticket.roster[2].team).toBe(2)
			expect(CrossServer.form(a, "Versus", 2)).toBe(nil)
			local ticketA = CrossServer.takeTicket(a, 1)
			expect(ticketA.accessCode).toBe(ticket.accessCode)
			expect(CrossServer.takeTicket(b, 2).matchKey).toBe(ticket.matchKey)
			expect(CrossServer.takeTicket(a, 1)).toBe(nil)
		end
	)

	it(
		"первым пришёл — первым подобран; 2 на 2 — команды чередуются",
		function()
			local _, a = crossPair()
			for userId = 1, 5 do
				CrossServer.join(a, "Team", userId, "rook", 100 - userId) -- позже вошёл — меньше номер
			end
			local ticket = CrossServer.form(a, "Team", 4)
			local order = {}
			for _, entry in ticket.roster do
				table.insert(order, `{entry.userId}:{entry.team}`)
			end
			expect(table.concat(order, ",")).toBe("5:1,4:2,3:1,2:2")
		end
	)

	it(
		"гонка: запись захвачена другим сервером — свои захваты отпускаются, позже матч собирается",
		function()
			local store, a = crossPair()
			CrossServer.join(a, "Versus", 1, "rook", 1)
			CrossServer.join(a, "Versus", 2, "rook", 2)
			-- Второй захват (3-й запрос после чтения очереди) «перехватывает» другой сервер.
			store.failAt = store.calls + 3
			expect(CrossServer.form(a, "Versus", 2)).toBe(nil)
			local first = store:GetSortedMap("mm_queue_Versus"):GetAsync("1")
			expect(first.claimed).toBe(nil)
			store.failAt = nil
			expect(CrossServer.form(a, "Versus", 2) ~= nil).toBeTruthy()
		end
	)

	it("записи истекают; недоступный MemoryStore не роняет сервер", function()
		local store, a, _, advance = crossPair()
		CrossServer.join(a, "Versus", 1, "rook", 1)
		advance(GameConfig.Matchmaking.TicketSeconds + 1)
		CrossServer.join(a, "Versus", 2, "rook", 2)
		expect(CrossServer.form(a, "Versus", 2)).toBe(nil)
		store.failNext = 100
		expect(CrossServer.join(a, "Versus", 3, "rook", 3)).toBe(false)
		expect(CrossServer.form(a, "Versus", 2)).toBe(nil)
		expect(CrossServer.takeTicket(a, 3)).toBe(nil)
		expect(CrossServer.findRoom(a, "ABCDEF")).toBe(nil)
	end)

	it("данные телепорта проверяются строго", function()
		local good = Protocol.encodeMatch({
			matchKey = "k",
			accessCode = "c",
			mode = "Versus",
			roster = { { userId = 1, characterId = "rook", team = 1 }, { userId = 2, characterId = "zip", team = 2 } },
		})
		expect(Protocol.readMatch(good) ~= nil).toBeTruthy()
		local bad = table.clone(good)
		bad.roster = { good.roster[1], good.roster[1] }
		expect(Protocol.readMatch(bad)).toBe(nil)
		bad.roster = { good.roster[1], { userId = 3, characterId = "nobody", team = 2 } }
		expect(Protocol.readMatch(bad)).toBe(nil)
		bad.kind = "Other"
		expect(Protocol.readMatch(bad)).toBe(nil)
		expect(Protocol.readMatch("junk")).toBe(nil)
		expect(Protocol.normalizeCode(" ab-cd ef")).toBe("ABCDEF")
		expect(Protocol.normalizeCode("ABCDE0")).toBe(nil)
	end)
end)

describe("Мультиплеер между серверами (Harness)", function()
	local function twoServers()
		local store = FakeMemoryStore.new(os.clock)
		local common = { studio = false, placeId = 777, memoryStore = store }
		local optionsA = table.clone(common)
		optionsA.jobId = "job-A"
		local optionsB = table.clone(common)
		optionsB.jobId = "job-B"
		optionsB.firstUserId = 100
		return Harness.new(optionsA), Harness.new(optionsB)
	end

	local function stepBoth(a, b, frames)
		for _ = 1, frames do
			a.step(1)
			b.step(1)
		end
	end

	it(
		"соперник на другом сервере: оба телепортируются на один зарезервированный сервер",
		function()
			local serverA, serverB = twoServers()
			local alice = serverA.addClient("Alice")
			local bob = serverB.addClient("Bob")
			stepBoth(serverA, serverB, 3)
			alice.click("Мультиплеер")
			bob.click("Мультиплеер")
			stepBoth(serverA, serverB, 2)
			press(alice, "QueueVersus")
			stepBoth(serverA, serverB, 2)
			press(bob, "QueueVersus")
			stepBoth(serverA, serverB, 60 * (GameConfig.Matchmaking.PollSeconds * 2 + 1))

			local teleportA = serverA.world.teleports[1]
			local teleportB = serverB.world.teleports[1]
			expect(teleportA ~= nil and teleportB ~= nil).toBeTruthy()
			expect(teleportA.players[1]).toBe(alice.player)
			expect(teleportB.players[1]).toBe(bob.player)
			expect(teleportA.accessCode).toBe(teleportB.accessCode)
			expect(teleportA.placeId).toBe(777)
			local ticket = Protocol.readMatch(teleportA.data)
			expect(ticket ~= nil).toBeTruthy()
			expect(ticket.matchKey).toBe(Protocol.readMatch(teleportB.data).matchKey)
			expect(alice.find("Headline").Text).toContainMatch("Подключение")
			expect(serverA.errors()).toBeEmpty()
			expect(serverB.errors()).toBeEmpty()
		end
	)

	it(
		"друг на другом сервере: код комнаты переносит к хозяину, и там начинается матч",
		function()
			local serverA, serverB = twoServers()
			local alice = serverA.addClient("Alice")
			local bob = serverB.addClient("Bob")
			stepBoth(serverA, serverB, 3)
			alice.click("Мультиплеер")
			bob.click("Мультиплеер")
			stepBoth(serverA, serverB, 2)
			press(alice, "RoomVersus")
			stepBoth(serverA, serverB, 3)
			local code = alice.find("RoomCode").Text
			bob.find("CodeInput").Text = code
			press(bob, "JoinRoom")
			stepBoth(serverA, serverB, 3)
			local teleport = serverB.world.teleports[1]
			expect(teleport ~= nil).toBeTruthy()
			expect(teleport.serverInstanceId).toBe("job-A")
			local join = Protocol.readRoomJoin(teleport.data)
			expect(join.code).toBe(code)

			-- Bob «прибыл» на сервер A с данными телепорта.
			local arrived = serverA.addClient("Bob", teleport.data)
			serverA.step(10)
			local match = serverA.serverRequire("Services", "MatchService").getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(match.controllers[2].player).toBe(arrived.player)
			expect(serverA.errors()).toBeEmpty()
		end
	)
end)

describe("Сервер матча (зарезервированный)", function()
	local function ticketData()
		return Protocol.encodeMatch({
			matchKey = "match-1",
			accessCode = "access-1",
			mode = "Versus",
			roster = { { userId = 1, characterId = "mira", team = 1 }, { userId = 2, characterId = "zip", team = 2 } },
		})
	end

	local function matchServer()
		return Harness.new({ studio = false, placeId = 777, privateServerId = "ps-1" })
	end

	it(
		"ждёт всех из состава, начинает матч, чужих и всех после матча возвращает в лобби",
		function()
			local game = matchServer()
			local alice = game.addClient("Alice", ticketData())
			game.step(5)
			local MatchService = game.serverRequire("Services", "MatchService")
			expect(MatchService.getMatchOf(alice.player)).toBe(nil)
			local bob = game.addClient("Bob", ticketData())
			game.step(5)
			local match = MatchService.getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(match.characters[1]).toBe("mira")
			expect(match.characters[2]).toBe("zip")
			expect(match.controllers[2].player).toBe(bob.player)
			expect(match.ranked).toBe(true)

			local stranger = game.addClient("Eve")
			game.step(3)
			expect(game.world.teleports[1].players[1]).toBe(stranger.player)

			finishByKnockouts(game, match, 1)
			game.step(60 * 5)
			local last = game.world.teleports[#game.world.teleports]
			expect(#last.players).toBe(2)
			expect(last.accessCode).toBe(nil)
			expect(game.errors()).toBeEmpty()
		end
	)

	it("соперник не пришёл — пришедший возвращается в лобби", function()
		local game = matchServer()
		local alice = game.addClient("Alice", ticketData())
		game.step(60 * (GameConfig.Matchmaking.ArrivalSeconds + 1))
		expect(alice.find("Notice").Text).toContainMatch("не подключился")
		game.step(60 * 4)
		expect(game.world.teleports[1].players[1]).toBe(alice.player)
	end)
end)
