-- Мультиплеер: 2 на 2 на сцене с двумя этажами (симуляция и MatchFlow), очередь и комнаты на сервере,
-- боты, бой с компьютером, межсерверный подбор через MemoryStore (несколько «серверов» с общим
-- хранилищем), сервер матча.

local Simulation = requireShared("Combat", "Simulation")
local MatchFlow = requireShared("Combat", "MatchFlow")
local InputBits = requireShared("Combat", "InputBits")
local Stage = requireShared("Combat", "Stage")
local GameConfig = requireShared("Config", "GameConfig")
local Arenas = requireShared("Config", "Arenas")

----------------------------------------------------------------------------------------------
-- 2 на 2: сцена с двумя этажами
----------------------------------------------------------------------------------------------

local IDLE = { held = 0, pressed = 0 }

local function teamSim()
	return Simulation.new({ characters = { "rook", "brakk", "mira", "zip" }, stage = "TwoFloors" })
end

-- Шаги симуляции; inputFor(slot, frame) → ввод бойца (по умолчанию ничего не нажато).
local function stepSim(sim, frames, inputFor)
	for frame = 1, frames do
		local inputs = {}
		for slot = 1, #sim.fighters do
			inputs[slot] = if inputFor then inputFor(slot, frame) or IDLE else IDLE
		end
		Simulation.step(sim, inputs)
	end
end

local function placeOnFloor(fighter, x, y)
	fighter.x = x
	fighter.y = y
	fighter.floorY = y
	fighter.vx = 0
	fighter.vy = 0
end

local function knockOut(sim, slot)
	sim.fighters[slot].health = 0
	sim.fighters[slot].ko = true
end

local function runFlow(sim, flow, frames, collect)
	for _ = 1, frames do
		stepSim(sim, 1)
		MatchFlow.step(flow, sim)
		if collect then
			for _, event in flow.events do
				table.insert(collect, event)
			end
		end
	end
end

local function runFlowUntil(sim, flow, phase)
	for _ = 1, 2000 do
		if flow.phase == phase then
			return
		end
		runFlow(sim, flow, 1)
	end
	error(`фаза {phase} не наступила`)
end

describe("2 на 2: два этажа", function()
	it(
		"нижние стоят внизу, верхние — на втором этаже; цели — на своём этаже",
		function()
			local sim = teamSim()
			local f = sim.fighters
			expect(f[1].team).toBe(1)
			expect(f[2].team).toBe(2)
			expect(f[3].team).toBe(1)
			expect(f[4].team).toBe(2)
			stepSim(sim, 30)
			expect(f[1].y).toBe(0)
			expect(f[2].y).toBe(0)
			expect(f[3].y).toBe(9)
			expect(f[4].y).toBe(9)
			expect(Stage.levelOf(sim.stage, f[3].floorY)).toBe(1)
			expect(f[1].target).toBe(2)
			expect(f[2].target).toBe(1)
			expect(f[3].target).toBe(4)
			expect(f[4].target).toBe(3)
			expect(f[3].facing).toBe(1)
			expect(f[4].facing).toBe(-1)
		end
	)

	it(
		"сверху можно спрыгнуть в дыру и оказаться внизу — цель меняется на нижнего",
		function()
			local sim = teamSim()
			local top = sim.fighters[3]
			placeOnFloor(top, -3.6, 9)
			local fell = false
			for _ = 1, 120 do
				stepSim(sim, 1, function(slot)
					if slot == 3 and not fell then
						return { held = InputBits.Right, pressed = 0 }
					end
					return nil
				end)
				fell = fell or top.state == "Air"
			end
			expect(fell).toBeTruthy()
			expect(top.y).toBe(0)
			expect(top.floorY).toBe(0)
			expect(math.abs(top.x) < 3).toBeTruthy()
			expect(top.target).toBe(2)
		end
	)

	it("снизу двойным прыжком можно запрыгнуть на второй этаж", function()
		local sim = teamSim()
		local bottom = sim.fighters[1]
		placeOnFloor(bottom, 0, 0)
		local doubleJumps = 0
		for frame = 1, 150 do
			stepSim(sim, 1, function(slot)
				if slot ~= 1 then
					return nil
				end
				if frame <= 2 then
					return { held = InputBits.Up, pressed = 0 }
				elseif frame >= 20 and frame <= 60 then
					return { held = bit32.bor(InputBits.Up, InputBits.Right), pressed = 0 }
				end
				return nil
			end)
			for _, event in sim.events do
				if event.kind == "Jump" and event.slot == 1 and event.tag == "Double" then
					doubleJumps += 1
				end
			end
		end
		expect(doubleJumps).toBe(1)
		expect(bottom.floorY).toBe(9)
		expect(bottom.y).toBe(9)
		expect(bottom.x > 3).toBeTruthy()
		expect(bottom.airJumps).toBe(1) -- после приземления двойной прыжок снова доступен
	end)

	it("под вторым этажом прыжок упирается головой в потолок", function()
		local sim = teamSim()
		local bottom = sim.fighters[1]
		placeOnFloor(bottom, -12, 0)
		local highest = 0
		for frame = 1, 80 do
			stepSim(sim, 1, function(slot)
				return if slot == 1 and frame <= 2 then { held = InputBits.Up, pressed = 0 } else nil
			end)
			highest = math.max(highest, bottom.y)
		end
		local platformBottom = 9 - sim.stage.platforms[1].thickness
		expect(highest <= platformBottom - GameConfig.Physics.AirPushTop + 1e-6).toBeTruthy()
		expect(highest > 1).toBeTruthy()
		expect(bottom.y).toBe(0)
	end)

	it("свои своих не бьют; бойцы проходят сквозь друг друга", function()
		local sim = teamSim()
		local f = sim.fighters
		placeOnFloor(f[3], 0, 0)
		placeOnFloor(f[1], 1.2, 0)
		placeOnFloor(f[2], 6, 0)
		placeOnFloor(f[4], 12, 9)
		stepSim(sim, 2)
		expect(f[3].facing).toBe(1)
		local hits = 0
		for frame = 1, 40 do
			stepSim(sim, 1, function(slot)
				return if slot == 3 and frame == 1 then { held = 0, pressed = InputBits.Light } else nil
			end)
			for _, event in sim.events do
				if event.kind == "Hit" or event.kind == "Block" then
					hits += 1
				end
			end
		end
		expect(hits).toBe(0)
		expect(f[1].health).toBe(f[1].maxHealth)
		expect(math.abs(f[1].x - 1.2) < 0.01).toBeTruthy() -- союзник не расталкивается
	end)

	it(
		"удар попадает в противника с любой стороны, пока он рядом",
		function()
			local sim = teamSim()
			local f = sim.fighters
			placeOnFloor(f[1], 0, 0)
			placeOnFloor(f[2], 2, 0)
			stepSim(sim, 2)
			local hit = false
			for frame = 1, 40 do
				stepSim(sim, 1, function(slot)
					return if slot == 1 and frame == 1 then { held = 0, pressed = InputBits.Light } else nil
				end)
				for _, event in sim.events do
					hit = hit or (event.kind == "Hit" and event.slot == 2 and event.attacker == 1)
				end
			end
			expect(hit).toBeTruthy()
			expect(f[2].health < f[2].maxHealth).toBeTruthy()
			expect(f[2].lastHitBy).toBe(1)
		end
	)

	it("кнопка блока защищает от удара с любой стороны", function()
		local sim = teamSim()
		local f = sim.fighters
		placeOnFloor(f[1], 0, 0)
		placeOnFloor(f[2], 2, 0)
		stepSim(sim, 2)
		local blocked = false
		for frame = 1, 40 do
			stepSim(sim, 1, function(slot)
				if slot == 1 and frame == 1 then
					return { held = 0, pressed = InputBits.Light }
				elseif slot == 2 then
					return { held = InputBits.Block, pressed = 0 }
				end
				return nil
			end)
			for _, event in sim.events do
				blocked = blocked or (event.kind == "Block" and event.slot == 2)
			end
		end
		expect(blocked).toBeTruthy()
		expect(f[2].health).toBe(f[2].maxHealth)
	end)

	it("удар с разбега у края не уносит с платформы", function()
		local sim = Simulation.new({ characters = { "rook", "brakk", "zip", "mira" }, stage = "TwoFloors" })
		local zip = sim.fighters[3]
		placeOnFloor(zip, -6, 9)
		stepSim(sim, 2)
		expect(zip.facing).toBe(1)
		local lowest = zip.y
		for frame = 1, 90 do
			stepSim(sim, 1, function(slot)
				return if slot == 3 and frame == 1 then { held = 0, pressed = InputBits.Special } else nil
			end)
			lowest = math.min(lowest, zip.y)
		end
		expect(lowest).toBe(9)
		expect(zip.x <= -3 + 1e-6).toBeTruthy()
		expect(zip.x > -5).toBeTruthy() -- рывок был, но остановился у края
	end)

	it(
		"сбили с платформы — после оглушения в воздухе можно двойным прыжком вернуться",
		function()
			local sim = teamSim()
			local top = sim.fighters[3]
			placeOnFloor(top, -2, 9) -- над дырой
			top.floorY = 0
			top.state = "Hitstun"
			top.stun = 4
			stepSim(sim, 6)
			expect(top.state).toBe("Air")
			expect(top.airJumps).toBe(1)
			local doubled = false
			stepSim(sim, 1, function(slot)
				return if slot == 3 then { held = bit32.bor(InputBits.Up, InputBits.Left), pressed = 0 } else nil
			end)
			for _, event in sim.events do
				doubled = doubled or (event.kind == "Jump" and event.tag == "Double")
			end
			expect(doubled).toBeTruthy()
			stepSim(sim, 60, function(slot)
				return if slot == 3 then { held = InputBits.Left, pressed = 0 } else nil
			end)
			expect(top.y).toBe(9)
			expect(top.x < -3).toBeTruthy()
		end
	)

	it(
		"бот наверху перепрыгивает дыру к сопернику, а не падает в неё",
		function()
			local BossAI = requireServer("AI", "BossAI")
			local BossRegistry = requireShared("Characters", "BossRegistry")
			for seed = 1, 3 do
				local sim = Simulation.new({ characters = { "rook", "brakk", "mira", "pike" }, stage = "TwoFloors" })
				local f = sim.fighters
				placeOnFloor(f[1], -20, 0)
				placeOnFloor(f[2], 20, 0)
				placeOnFloor(f[3], -12, 9)
				placeOnFloor(f[4], 12, 9)
				local think = BossAI.controller(BossRegistry.profileForLevel(8), seed)
				local crossed, fell = false, false
				for _ = 1, 600 do
					stepSim(sim, 1, function(slot)
						return if slot == 3 then think(sim, 3) else nil
					end)
					fell = fell or f[3].standY == 0
					crossed = crossed or (f[3].x > 3 and f[3].standY == 9)
					if crossed or fell then
						break
					end
				end
				expect(fell).toBe(false)
				expect(crossed).toBeTruthy()
			end
		end
	)

	it(
		"раунд кончается, только когда выбиты оба бойца команды",
		function()
			local sim = teamSim()
			local flow = MatchFlow.new({ roundsToWin = 2 })
			MatchFlow.start(flow, sim)
			runFlowUntil(sim, flow, "Fight")
			knockOut(sim, 2)
			runFlow(sim, flow, 30)
			expect(flow.phase).toBe("Fight")
			expect(MatchFlow.teamStatus(sim).alive[2]).toBe(1)
			-- Боец без противника на своём этаже переключается на оставшегося.
			expect(sim.fighters[1].target).toBe(4)
			knockOut(sim, 4)
			local events = {}
			runFlow(sim, flow, 1, events)
			expect(flow.phase).toBe("RoundEnd")
			expect(events[1].kind).toBe("RoundEnd")
			expect(events[1].winner).toBe(1)
			expect(flow.wins[1]).toBe(1)
			-- Новый раунд: все снова на своих местах с полным здоровьем.
			runFlowUntil(sim, flow, "RoundStart")
			expect(sim.fighters[4].ko).toBe(false)
			expect(sim.fighters[4].y).toBe(9)
			expect(sim.fighters[2].health).toBe(sim.fighters[2].maxHealth)
		end
	)

	it("время вышло: побеждает команда с большим общим % HP", function()
		local sim = teamSim()
		local flow = MatchFlow.new({ roundsToWin = 2 })
		MatchFlow.start(flow, sim)
		runFlowUntil(sim, flow, "Fight")
		local f = sim.fighters
		f[1].health = math.floor(f[1].maxHealth * 0.5)
		f[3].health = f[3].maxHealth -- команда 1: 75 %
		f[2].health = math.floor(f[2].maxHealth * 0.8)
		f[4].health = math.floor(f[4].maxHealth * 0.8) -- команда 2: 80 %
		flow.timer = 1
		local events = {}
		runFlow(sim, flow, 1, events)
		expect(events[1].result).toBe("Time")
		expect(events[1].winner).toBe(2)
	end)

	it(
		"выбиты все сразу — двойной K.O., обе команды получают очко",
		function()
			local sim = teamSim()
			local flow = MatchFlow.new({ roundsToWin = 2 })
			MatchFlow.start(flow, sim)
			runFlowUntil(sim, flow, "Fight")
			for slot = 1, 4 do
				knockOut(sim, slot)
			end
			local events = {}
			runFlow(sim, flow, 1, events)
			expect(events[1].result).toBe("DoubleKO")
			expect(events[1].winner).toBe(0)
			expect(flow.wins[1]).toBe(1)
			expect(flow.wins[2]).toBe(1)
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

--[[
	Пройти подготовку к бою: все жмут «ГОТОВ!», затем голосуют за карту arenaId (по умолчанию dojo),
	и ждём показа выбранной карты. step — шаг «мира» (у двух серверов свой).
]]
local function finishDraft(step, clients, arenaId)
	step(3)
	for _, client in clients do
		local ready = client.find("DraftReady")
		if ready then
			client.runtime.fire(ready:FindFirstChild("Face"), "Activated")
		end
	end
	step(3)
	for _, client in clients do
		local card = client.find(`Map_{arenaId or "dojo"}`)
		if card then
			client.runtime.fire(card, "Activated")
		end
	end
	step(math.ceil(60 * GameConfig.Draft.RevealSeconds) + 10)
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
			-- Сначала подготовка: экран выбора бойца у обоих.
			expect(alice.find("Draft") ~= nil).toBeTruthy()
			expect(bob.find("Draft") ~= nil).toBeTruthy()
			expect(s.match.getMatchOf(alice.player)).toBe(nil)
			finishDraft(game.step, { alice, bob })
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
		finishDraft(game.step, { alice, bob })
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

describe("2 на 2 по сети", function()
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
		finishDraft(game.step, clients)
		local match = services(game).match.getMatchOf(clients[1].player)
		return game, clients, match
	end

	it(
		"четверо на сцене с двумя этажами; у каждого свой боец и панель на 4 бойцов",
		function()
			local game, clients, match = teamGame()
			local alice, bob, cara, dan = clients[1], clients[2], clients[3], clients[4]
			expect(match ~= nil).toBeTruthy()
			expect(match.mode).toBe("Team")
			expect(match.stage).toBe("TwoFloors")
			expect(match.ranked).toBe(true)
			expect(#match.sim.fighters).toBe(4)
			local order = { alice, bob, cara, dan }
			for slot, client in order do
				expect(match.controllers[slot].player).toBe(client.player)
			end
			expect(match.characters[3]).toBe("mira")
			expect(match.sim.fighters[3].team).toBe(1)
			for _, client in clients do
				expect(client.find("Battle") ~= nil).toBeTruthy()
				for slot = 1, 4 do
					expect(client.find(`TeamRow{slot}`) ~= nil).toBeTruthy()
				end
				expect(client.find("FighterPanel1")).toBe(nil)
			end
			expect(cara.find("TeamRow3"):FindFirstChild("Name").Text).toContainMatch("ВЫ")
			-- Таблички над бойцами: свой — «ВЫ», остальные — имена игроков.
			stepUntilPhase(game, match, "Fight")
			game.step(5)
			local views = cara.require("Controllers", "FightController").getViews()
			local plate = views[3].anchor:FindFirstChild("Nameplate")
			expect(plate ~= nil).toBeTruthy()
			expect(plate:FindFirstChild("Label").Text).toBe("ВЫ")
			expect(views[2].anchor:FindFirstChild("Nameplate"):FindFirstChild("Label").Text).toBe("Bob")

			-- Cara (верхний этаж) управляет своим бойцом, а бойцы Alice стоят.
			local top = match.sim.fighters[3]
			local startX, aliceX = top.x, match.sim.fighters[1].x
			cara.runtime.pressKey("A")
			game.step(20)
			cara.runtime.releaseKey("A")
			expect(top.x < startX - 1).toBeTruthy()
			expect(top.y).toBe(9)
			expect(match.sim.fighters[1].x).toBeCloseTo(aliceX, 1e-6)
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)

	it("победа команды — монеты обоим игрокам команды", function()
		local game, clients, match = teamGame()
		local s = services(game)
		for _ = 1, 20 do
			if match.ended then
				break
			end
			stepUntilPhase(game, match, "Fight")
			if match.ended then
				break
			end
			knockOut(match.sim, 2)
			knockOut(match.sim, 4)
			game.step(1)
		end
		game.step(5)
		expect(match.ended).toBe(true)
		expect(s.data.getCoins(clients[1].player)).toBe(GameConfig.Matchmaking.WinReward)
		expect(s.data.getCoins(clients[3].player)).toBe(GameConfig.Matchmaking.WinReward)
		expect(s.data.getCoins(clients[2].player)).toBe(0)
		expect(s.data.getCoins(clients[4].player)).toBe(0)
	end)

	it("игрок покинул матч — его команда проигрывает", function()
		local game, clients, match = teamGame()
		game.removeClient(clients[4]) -- Dan, команда 2
		game.step(2)
		expect(match.ended).toBe(true)
		local s = services(game)
		expect(s.match.getMatchOf(clients[1].player)).toBe(nil)
		expect(clients[1].find("Notice").Text).toContainMatch("победа")
	end)
end)

describe("Боты", function()
	it(
		"никого нет в очереди — через несколько секунд места занимают боты",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice")
			openMultiplayer(game, { alice })
			press(alice, "QueueTeam")
			game.step(3)
			expect(alice.find("Details").Text).toContainMatch("ботов")
			local s = services(game)
			game.step(60 * (GameConfig.Matchmaking.BotFillSeconds - 2))
			expect(s.match.getMatchOf(alice.player)).toBe(nil)
			game.step(60 * 3)
			finishDraft(game.step, { alice })
			local match = s.match.getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(match.stage).toBe("TwoFloors")
			expect(match.ranked).toBe(false)
			expect(match.controllers[1].player).toBe(alice.player)
			for slot = 2, 4 do
				expect(match.controllers[slot].kind).toBe("AI")
			end
			expect(s.mm.isQueued(alice.player)).toBe(false)

			-- Боты дерутся: бой идёт, ошибок нет. Победа над ботами — уменьшенная награда.
			stepUntilPhase(game, match, "Fight")
			game.step(240)
			expect(game.errors()).toBeEmpty()
			for _ = 1, 20 do
				if match.ended then
					break
				end
				stepUntilPhase(game, match, "Fight")
				if match.ended then
					break
				end
				knockOut(match.sim, 2)
				knockOut(match.sim, 4)
				game.step(1)
			end
			game.step(5)
			expect(s.data.getCoins(alice.player)).toBe(GameConfig.Matchmaking.BotWinReward)
		end
	)

	it(
		"хозяин комнаты может начать сразу — с ботами и без наград",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice")
			openMultiplayer(game, { alice })
			press(alice, "RoomVersus")
			game.step(3)
			expect(alice.find("RoomStart").Visible).toBe(true)
			press(alice, "RoomStart")
			game.step(5)
			finishDraft(game.step, { alice })
			local s = services(game)
			local match = s.match.getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(match.controllers[2].kind).toBe("AI")
			expect(match.ranked).toBe(false)
			finishByKnockouts(game, match, 2)
			game.step(5)
			expect(s.data.getCoins(alice.player)).toBe(0)
			-- Начать может только хозяин.
			local ok, code = s.router.handle(alice.player, "RoomStart", nil, 99)
			expect(ok).toBe(false)
			expect(code).toBe("NotInRoom")
		end
	)
end)

describe("Подготовка к бою", function()
	local function fire(client, name)
		local target = client.find(name)
		assert(target, `нет элемента {name}`)
		client.runtime.fire(target, "Activated")
	end

	local function draftTitle(client)
		return client.find("Draft"):FindFirstChild("Title").Text
	end

	it(
		"сначала боец, потом карта; премиальную карту выбирает только владелец — играют на ней все",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice")
			local bob = game.addClient("Bob")
			openMultiplayer(game, { alice, bob })
			local s = services(game)
			s.data.grantArena(alice.player, "neon")
			press(alice, "QueueVersus")
			press(bob, "QueueVersus")
			game.step(8)
			expect(draftTitle(alice)).toContainMatch("БОЙЦА")
			-- Очередь больше не показывает «Соперники найдены» поверх меню.
			expect(clientPeek(alice, appState(alice).queue).status).toBe("Idle")

			fire(alice, "Pick_mira")
			local ok, code = s.router.handle(bob.player, "DraftPick", { characterId = "ashka" }, 10)
			expect(ok).toBe(false)
			expect(code).toBe("CharacterNotAvailable")
			game.step(3)
			expect(bob.find("Slot1"):FindFirstChild("Fighter").Text).toBe("MIRA VOSS")
			expect(alice.find("Pick_ashka"):FindFirstChild("Locked").Visible).toBe(true)

			press(alice, "DraftReady")
			game.step(2)
			expect(draftTitle(alice)).toContainMatch("БОЙЦА") -- ждём второго
			press(bob, "DraftReady")
			game.step(3)
			expect(draftTitle(alice)).toContainMatch("КАРТУ")
			expect(bob.find("Map_dragon"):FindFirstChild("Locked").Visible).toBe(true)
			expect(alice.find("Map_neon"):FindFirstChild("Locked").Visible).toBe(false)
			local okVote, voteCode = s.router.handle(bob.player, "DraftVote", { arenaId = "dragon" }, 20)
			expect(okVote).toBe(false)
			expect(voteCode).toBe("ArenaLocked")
			local _, lateCode = s.router.handle(bob.player, "DraftPick", { characterId = "rook" }, 22)
			expect(lateCode).toBe("TooLate")

			fire(alice, "Map_neon")
			game.step(3)
			expect(bob.find("Map_neon"):FindFirstChild("Votes").Text).toContainMatch("1")
			-- Bob не голосует — ждём конца времени.
			game.step(math.ceil(60 * (GameConfig.Draft.MapSeconds + GameConfig.Draft.RevealSeconds)) + 20)
			local match = s.match.getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(match.arenaId).toBe("neon")
			expect(match.characters[1]).toBe("mira")
			expect(match.characters[2]).toBe("rook")
			expect(bob.find("Battle") ~= nil).toBeTruthy()
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)

	it(
		"никто ничего не выбрал — бойцы из меню и случайная бесплатная карта",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice")
			local bob = game.addClient("Bob")
			openMultiplayer(game, { alice, bob })
			appState(bob).selectedCharacterId:set("zip")
			press(alice, "QueueVersus")
			press(bob, "QueueVersus")
			local draft = GameConfig.Draft
			game.step(math.ceil(60 * (draft.CharacterSeconds + draft.MapSeconds + draft.RevealSeconds)) + 30)
			local match = services(game).match.getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(match.characters[1]).toBe("rook")
			expect(match.characters[2]).toBe("zip")
			local arena = Arenas.byId[match.arenaId]
			expect(arena ~= nil and not arena.premium).toBeTruthy()
		end
	)

	it(
		"игрок вышел во время подготовки — вместо него бот; вышли все — бой отменён",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice")
			local bob = game.addClient("Bob")
			openMultiplayer(game, { alice, bob })
			press(alice, "QueueVersus")
			press(bob, "QueueVersus")
			game.step(8)
			game.removeClient(bob)
			game.step(3)
			expect(alice.find("Slot2"):FindFirstChild("Player").Text).toBe("BOT")
			finishDraft(game.step, { alice })
			local s = services(game)
			local match = s.match.getMatchOf(alice.player)
			expect(match ~= nil).toBeTruthy()
			expect(match.controllers[2].kind).toBe("AI")
			expect(match.ranked).toBe(false)

			-- Бой с компьютером: игрок сам вышел из подготовки — вернулся в меню, боя нет.
			local carol = game.addClient("Carol")
			openMultiplayer(game, { carol })
			press(carol, "Cpu3")
			game.step(4)
			expect(carol.find("Draft") ~= nil).toBeTruthy()
			press(carol, "DraftLeave")
			game.step(4)
			expect(carol.find("Draft")).toBe(nil)
			expect(carol.find("ModeSelect") ~= nil).toBeTruthy()
			game.step(math.ceil(60 * GameConfig.Draft.CharacterSeconds) + 10)
			expect(s.match.getMatchOf(carol.player)).toBe(nil)
			expect(game.errors()).toBeEmpty()
		end
	)
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
			finishDraft(game.step, { alice, bob })
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
		finishDraft(game.step, { alice })
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

	it("2 на 2: игрок с ботом-напарником против двух ботов", function()
		local game = Harness.new()
		local alice = game.addClient("Alice")
		openMultiplayer(game, { alice })
		press(alice, "CpuMode")
		game.step(1)
		expect(alice.find("CpuMode"):FindFirstChild("Face").Text).toContainMatch("2 на 2")
		press(alice, "Cpu3")
		game.step(6)
		finishDraft(game.step, { alice })
		local match = services(game).match.getMatchOf(alice.player)
		expect(match ~= nil).toBeTruthy()
		expect(match.stage).toBe("TwoFloors")
		expect(#match.sim.fighters).toBe(4)
		for slot = 2, 4 do
			expect(match.controllers[slot].kind).toBe("AI")
		end
		expect(match.sim.fighters[3].team).toBe(1)
		expect(alice.find("TeamRow3") ~= nil).toBeTruthy()
		stepUntilPhase(game, match, "Fight")
		-- Боты дерутся (урон получили хотя бы двое; персонажи ботов случайные — ждём до 30 с).
		local damaged = 0
		for _ = 1, 60 do
			game.step(30)
			damaged = 0
			for _, fighter in match.sim.fighters do
				if fighter.health < fighter.maxHealth then
					damaged += 1
				end
			end
			if damaged >= 2 or match.ended then
				break
			end
		end
		expect(damaged >= 2).toBeTruthy()
		expect(game.errors()).toBeEmpty()
		expect(game.warnings()).toBeEmpty()
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
			finishDraft(serverA.step, { alice, arrived })
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
			finishDraft(game.step, { alice, bob })
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
