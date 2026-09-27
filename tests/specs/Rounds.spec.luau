-- Раунды и таймер (MatchFlow) + полный матч двух игроков через сеть с HUD.

local Simulation = requireShared("Combat", "Simulation")
local MatchFlow = requireShared("Combat", "MatchFlow")
local GameConfig = requireShared("Config", "GameConfig")

local TICK = GameConfig.TickRate

local function newMatch(roundsToWin, a, b)
	local sim = Simulation.new({ characters = { a or "rook", b or "rook" } })
	local flow = MatchFlow.new({ roundsToWin = roundsToWin or 2 })
	MatchFlow.start(flow, sim)
	return sim, flow
end

-- Прогнать кадры; collect — копить события раундов.
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

-- Дойти до фазы Fight.
local function toFight(sim, flow)
	local guard = 0
	while flow.phase ~= "Fight" and guard < 1000 do
		run(sim, flow, 1)
		guard += 1
	end
end

local function kinds(events)
	local list = {}
	for _, event in events do
		table.insert(list, event.kind)
	end
	return table.concat(list, ",")
end

describe("MatchFlow", function()
	it(
		"вступление → Round 1 → Fight; ввод включается только к «Fight!»",
		function()
			local sim, flow = newMatch()
			local events = {}
			expect(sim.inputEnabled).toBe(false)
			run(sim, flow, 100, events)
			expect(flow.phase).toBe("RoundStart")
			expect(sim.inputEnabled).toBe(false)
			run(sim, flow, 60, events)
			expect(sim.inputEnabled).toBe(true)
			expect(kinds(events)).toBe("RoundStart,Fight")
			expect(events[1].round).toBe(1)
		end
	)

	it(
		"таймер 60 секунд идёт только в бою и стоит во время супера",
		function()
			local sim, flow = newMatch()
			toFight(sim, flow)
			expect(MatchFlow.timerSeconds(flow)).toBe(60)
			run(sim, flow, TICK * 2)
			expect(MatchFlow.timerSeconds(flow)).toBe(58)
			sim.freeze = 30
			local before = flow.timer
			run(sim, flow, 20)
			expect(flow.timer).toBe(before)
		end
	)

	it(
		"время вышло: побеждает больший ПРОЦЕНТ HP, а не абсолютное HP",
		function()
			local sim, flow = newMatch(2, "rook", "brakk")
			toFight(sim, flow)
			local a, b = sim.fighters[1], sim.fighters[2]
			a.health = math.floor(a.maxHealth * 0.6) -- 600 из 1000
			b.health = math.floor(b.maxHealth * 0.55) -- 649 из 1180: больше HP, но меньше %
			expect(b.health > a.health).toBeTruthy()
			local events = {}
			run(sim, flow, TICK * 61, events)
			local roundEnd
			for _, event in events do
				if event.kind == "RoundEnd" then
					roundEnd = event
				end
			end
			expect(roundEnd ~= nil).toBeTruthy()
			expect(roundEnd.result).toBe("Time")
			expect(roundEnd.winner).toBe(1)
		end
	)

	it(
		"равный процент HP по времени — ничья, победа в раунде обоим",
		function()
			local sim, flow = newMatch(3)
			toFight(sim, flow)
			flow.timer = 1
			local events = {}
			run(sim, flow, 5, events)
			expect(flow.roundResult).toBe("Draw")
			expect(flow.wins[1]).toBe(1)
			expect(flow.wins[2]).toBe(1)
		end
	)

	it(
		"нокаут: раунд заканчивается, «Perfect» — если победитель не терял HP",
		function()
			local sim, flow = newMatch()
			toFight(sim, flow)
			sim.fighters[2].ko = true
			run(sim, flow, 1)
			expect(flow.phase).toBe("RoundEnd")
			expect(flow.roundWinner).toBe(1)
			expect(flow.roundResult).toBe("Perfect")
			expect(flow.wins[1]).toBe(1)
		end
	)

	it("двойной нокаут — ничья", function()
		local sim, flow = newMatch()
		toFight(sim, flow)
		sim.fighters[1].ko = true
		sim.fighters[2].ko = true
		run(sim, flow, 1)
		expect(flow.roundResult).toBe("DoubleKO")
		expect(flow.wins[1]).toBe(1)
		expect(flow.wins[2]).toBe(1)
	end)

	it(
		"новый раунд восстанавливает HP и позиции, шкала супера сохраняется",
		function()
			local sim, flow = newMatch()
			toFight(sim, flow)
			local a = sim.fighters[1]
			a.health = 100
			a.meter = 700
			a.x = 10
			sim.fighters[2].ko = true
			run(sim, flow, 200)
			expect(flow.round).toBe(2)
			expect(a.health).toBe(a.maxHealth)
			expect(a.meter).toBe(700)
			expect(a.x).toBeCloseTo(-GameConfig.Physics.StartDistance / 2)
		end
	)

	it("матч до 2 побед (PvP) и до 3 побед (босс)", function()
		for _, target in { 2, 3 } do
			local sim, flow = newMatch(target)
			local events = {}
			for _ = 1, target do
				toFight(sim, flow)
				sim.fighters[2].ko = true
				run(sim, flow, 200, events)
			end
			expect(flow.phase).toBe("MatchEnd")
			expect(flow.matchWinner).toBe(1)
			expect(flow.wins[1]).toBe(target)
			run(sim, flow, 200)
			expect(flow.finished).toBe(true)
		end
	end)

	it(
		"ничьи довели обоих до нужного числа побед — финальный раунд",
		function()
			local sim, flow = newMatch(2)
			local events = {}
			for _ = 1, 2 do
				toFight(sim, flow)
				flow.timer = 1
				run(sim, flow, 200, events)
			end
			expect(flow.phase).toBe("RoundStart")
			expect(flow.wins[1]).toBe(1)
			expect(flow.wins[2]).toBe(1)
			local last = events[#events]
			expect(last.kind).toBe("RoundStart")
			expect(last.final).toBe(true)
		end
	)
end)

describe("Матч двух игроков через сеть", function()
	local function versus()
		local game = Harness.new({ latencyFrames = 2 })
		local alice = game.addClient("Alice")
		local bob = game.addClient("Bob")
		game.step(2)
		local MatchService = game.serverRequire("Services", "MatchService")
		local finished = nil
		local match = MatchService.create({
			mode = "Versus",
			arenaId = "rooftop",
			characters = { "rook", "mira" },
			controllers = { { kind = "Player", player = alice.player }, { kind = "Player", player = bob.player } },
			participants = { alice.player, bob.player },
			roundsToWin = 2,
			onFinished = function(_, result)
				finished = result
			end,
		})
		game.step(5) -- задержка сети: начало матча доходит до клиентов не мгновенно
		return game, alice, bob, match, function()
			return finished
		end
	end

	local function bannerText(client)
		local banner = client.find("Banner")
		return if banner and banner.Visible then banner.Text else ""
	end

	local function stepUntil(game, predicate, limit)
		for _ = 1, limit or 600 do
			if predicate() then
				return true
			end
			game.step(1)
		end
		return predicate()
	end

	it(
		"оба видят раунды, таймер и HUD; K.O. засчитывается; матч до 2 побед",
		function()
			local game, alice, bob, match, result = versus()
			expect(alice.find("Battle") ~= nil).toBeTruthy()
			expect(bob.find("Battle") ~= nil).toBeTruthy()

			expect(stepUntil(game, function()
				return bannerText(alice) == "ROUND 1"
			end)).toBeTruthy()
			expect(stepUntil(game, function()
				return bannerText(bob) == "FIGHT!"
			end)).toBeTruthy()
			expect(alice.find("Timer").Text).toBe("60")

			for round = 1, 2 do
				stepUntil(game, function()
					return match.flow.phase == "Fight"
				end)
				-- Сводим бойцов и добиваем Mira ударом Alice.
				match.sim.fighters[1].x = -1
				match.sim.fighters[2].x = 1
				match.sim.fighters[2].health = 1
				alice.runtime.pressKey("J")
				game.step(1)
				alice.runtime.releaseKey("J")
				expect(stepUntil(game, function()
					return match.flow.phase == "RoundEnd"
				end, 60)).toBeTruthy()
				expect(match.flow.wins[1]).toBe(round)
				expect(stepUntil(game, function()
					local text = bannerText(bob)
					return text == "K.O." or text == "PERFECT"
				end, 30)).toBeTruthy()
			end

			expect(stepUntil(game, function()
				return bannerText(alice) == "YOU WIN!"
			end)).toBeTruthy()
			expect(bannerText(bob)).toBe("YOU LOSE")
			expect(stepUntil(game, function()
				return result() ~= nil
			end)).toBeTruthy()
			expect(result().winner).toBe(1)
			game.step(10)
			expect(alice.find("MainMenu") ~= nil).toBeTruthy()
			expect(bob.find("MainMenu") ~= nil).toBeTruthy()
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)

	it("полосы HP в HUD отражают урон", function()
		local game, alice, bob, match = versus()
		stepUntil(game, function()
			return match.flow.phase == "Fight"
		end)
		match.sim.fighters[1].x = -1
		match.sim.fighters[2].x = 1
		bob.runtime.pressKey("K")
		game.step(1)
		bob.runtime.releaseKey("K")
		game.step(40)
		local bar = alice.runtime.findByName(alice.find("FighterPanel1"), "Current")
		expect(bar.Size.X.Scale < 1).toBeTruthy()
		expect(game.errors()).toBeEmpty()
	end)

	it("выход игрока из PvP — победа сопернику", function()
		local game, alice, bob, _, result = versus()
		game.step(30)
		bob.leaveBattle()
		game.step(5)
		expect(result() ~= nil).toBeTruthy()
		expect(result().winner).toBe(1)
		expect(result().reason).toBe("Left")
		expect(alice.find("MainMenu") ~= nil).toBeTruthy()
	end)
end)
