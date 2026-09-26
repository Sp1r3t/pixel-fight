-- Боссы: конфиг и кривая сложности, автомат состояний, ИИ, механики боссов в симуляции.

local BossRegistry = requireShared("Characters", "BossRegistry")
local BossesConfig = requireShared("Config", "Bosses")
local Balance = requireShared("Config", "Balance")
local GameConfig = requireShared("Config", "GameConfig")
local Simulation = requireShared("Combat", "Simulation")
local MatchFlow = requireShared("Combat", "MatchFlow")
local InputBits = requireShared("Combat", "InputBits")
local Rng = requireShared("Util", "Rng")
local StateMachine = requireServer("AI", "StateMachine")
local BossAI = requireServer("AI", "BossAI")

-- Бой ИИ против ИИ до одной победы. Возвращает победителя, кадры, события, посещённые состояния.
local function aiDuel(levelA, levelB, seed, character)
	local sim = Simulation.new({ characters = { character or "rook", character or "rook" } })
	sim.fighters[1].tapDash = false
	sim.fighters[2].tapDash = false
	local flow = MatchFlow.new({ roundsToWin = 1 })
	MatchFlow.start(flow, sim)
	local a = BossAI.new(BossRegistry.profileForLevel(levelA), seed * 7919)
	local b = BossAI.new(BossRegistry.profileForLevel(levelB), seed * 104729)
	local events, visited = {}, {}
	local frames = 0
	while not flow.finished and frames < 20000 do
		Simulation.step(sim, { BossAI.think(a, sim, 1), BossAI.think(b, sim, 2) })
		for _, event in sim.events do
			events[event.kind] = (events[event.kind] or 0) + 1
		end
		MatchFlow.step(flow, sim)
		frames += 1
	end
	for _, brain in { a, b } do
		for state in brain.machine.entries do
			visited[state] = true
		end
	end
	return flow.matchWinner, frames, events, visited, sim
end

-- Простой «напористый» бот-игрок: идёт вперёд и часто бьёт вблизи. Против него проверяем защиту ИИ.
local function rushBot(seed)
	local rng = Rng.new(seed)
	local cooldown = 0
	return function(sim, slot)
		local me, opponent = sim.fighters[slot], sim.fighters[3 - slot]
		local forward = if opponent.x > me.x then InputBits.Right else InputBits.Left
		cooldown -= 1
		if math.abs(opponent.x - me.x) > 3 then
			return { held = forward, pressed = 0 }
		elseif cooldown <= 0 then
			cooldown = Rng.integer(rng, 8, 20)
			local pressed = if Rng.chance(rng, 0.6) then InputBits.Light else InputBits.Heavy
			return { held = 0, pressed = pressed }
		end
		return { held = 0, pressed = 0 }
	end
end

-- Какую долю атак бота ИИ заблокировал за frames кадров.
local function blockRateAgainstRush(level, frames)
	local sim = Simulation.new({ characters = { "rook", "rook" } })
	sim.fighters[2].tapDash = false
	local bot = rushBot(level * 13)
	local brain = BossAI.new(BossRegistry.profileForLevel(level), level * 31)
	local blocks, hits = 0, 0
	for _ = 1, frames do
		Simulation.step(sim, { bot(sim, 1), BossAI.think(brain, sim, 2) })
		for _, event in sim.events do
			if event.kind == "Block" and event.slot == 2 then
				blocks += 1
			elseif event.kind == "Hit" and event.slot == 2 then
				hits += 1
			end
		end
		-- Бесконечный бой: восстанавливаем HP и позиции после нокаута.
		if sim.fighters[1].ko or sim.fighters[2].ko then
			Simulation.resetPositions(sim)
			Simulation.restoreHealth(sim)
		end
	end
	return blocks / math.max(1, blocks + hits)
end

describe("Боссы: конфиг", function()
	it("20 боссов, конфиг проходит все проверки", function()
		expect(BossRegistry.validate()).toBeEmpty()
		expect(BossRegistry.count()).toBe(GameConfig.BossCount)
		for order, boss in BossRegistry.list() do
			expect(boss.order).toBe(order)
			expect(BossRegistry.get(boss.id)).toBe(boss)
		end
	end)

	it("тиры: 1–5, 6–10, 11–14, 15–19, 20", function()
		local expected = {
			[1] = "Easy",
			[5] = "Easy",
			[6] = "Medium",
			[10] = "Medium",
			[11] = "Hard",
			[14] = "Hard",
			[15] = "VeryHard",
			[19] = "VeryHard",
			[20] = "Final",
		}
		for order, tier in expected do
			expect(BossRegistry.tierOf(order).id).toBe(tier)
		end
	end)

	it("мастерство ИИ растёт с номером босса", function()
		local rising = { "blockChance", "guardRead", "punishChance", "antiAirChance", "comboSkill", "superUsage" }
		local falling = { "reactionFrames", "thinkInterval", "mistakeChance" }
		local previous = BossRegistry.coreSkill(1)
		for order = 2, BossRegistry.count() do
			local current = BossRegistry.coreSkill(order)
			for _, name in rising do
				expect(current[name] >= previous[name]).toBeTruthy()
			end
			for _, name in falling do
				expect(current[name] <= previous[name]).toBeTruthy()
			end
			previous = current
		end
		local final = BossRegistry.profile(BossRegistry.byOrder(20))
		expect(final.reactionFrames <= 6).toBeTruthy()
		expect(final.mistakeChance <= 0.02).toBeTruthy()
		local first = BossRegistry.profile(BossRegistry.byOrder(1))
		expect(first.reactionFrames >= 24).toBeTruthy()
		expect(first.blockChance <= 0.2).toBeTruthy()
	end)

	it("бонус HP умеренный и не падает к концу башни", function()
		local previous = 1
		for _, boss in BossRegistry.list() do
			expect(boss.hpMultiplier >= 1).toBeTruthy()
			expect(boss.hpMultiplier <= Balance.BossMaxHpMultiplier).toBeTruthy()
			expect(boss.hpMultiplier >= previous).toBeTruthy()
			previous = boss.hpMultiplier
		end
	end)

	it("валидатор находит ошибки в конфиге", function()
		local broken = table.clone(BossesConfig)
		local copy = table.clone(broken[1])
		copy.hpMultiplier = 2
		copy.character = "nobody"
		copy.arena = "moon"
		broken[1] = copy
		local errors = BossRegistry.validate(broken)
		expect(errors).toContainMatch("hpMultiplier")
		expect(errors).toContainMatch("nobody")
		expect(errors).toContainMatch("moon")
		table.remove(broken, 5)
		expect(BossRegistry.validate(broken)).toContainMatch("номером 5")
	end)
end)

describe("Конечный автомат", function()
	it("вход, выход и переходы по результату update", function()
		local log = {}
		local ctx = { goB = false }
		local machine = StateMachine.new({
			A = {
				enter = function()
					table.insert(log, "enterA")
				end,
				update = function(c)
					return if c.goB then "B" else nil
				end,
				exit = function()
					table.insert(log, "exitA")
				end,
			},
			B = {
				enter = function()
					table.insert(log, "enterB")
				end,
				update = function()
					return nil
				end,
			},
		}, "A", ctx)
		StateMachine.step(machine)
		expect(machine.current).toBe("A")
		ctx.goB = true
		StateMachine.step(machine)
		expect(machine.current).toBe("B")
		expect(table.concat(log, ",")).toBe("enterA,exitA,enterB")
		expect(machine.frames).toBe(1)
	end)

	it("зацикленные переходы не вешают кадр", function()
		local machine = StateMachine.new({
			A = {
				update = function()
					return "B"
				end,
			},
			B = {
				update = function()
					return "A"
				end,
			},
		}, "A", {})
		StateMachine.step(machine)
		expect(machine.transitions).toBe(4)
	end)
end)

describe("ИИ боссов", function()
	it("выдаёт только ввод и не меняет симуляцию сам", function()
		local sim = Simulation.new({ characters = { "rook", "mira" } })
		local brain = BossAI.new(BossRegistry.profileForLevel(20), 1)
		for _ = 1, 300 do
			local before = {}
			for slot, fighter in sim.fighters do
				before[slot] = { fighter.x, fighter.health, fighter.state, fighter.meter, fighter.stateFrame }
			end
			local input = BossAI.think(brain, sim, 2)
			for slot, fighter in sim.fighters do
				local snapshot = before[slot]
				expect(fighter.x).toBe(snapshot[1])
				expect(fighter.health).toBe(snapshot[2])
				expect(fighter.state).toBe(snapshot[3])
				expect(fighter.meter).toBe(snapshot[4])
				expect(fighter.stateFrame).toBe(snapshot[5])
			end
			expect(InputBits.sanitize(input.held)).toBe(input.held)
			expect(InputBits.sanitize(input.pressed)).toBe(input.pressed)
			Simulation.step(sim, { InputBits.empty(), input })
		end
	end)

	it(
		"бой воспроизводим: одинаковые зёрна — одинаковый итог",
		function()
			local winnerA, framesA, _, _, simA = aiDuel(8, 12, 3)
			local winnerB, framesB, _, _, simB = aiDuel(8, 12, 3)
			expect(winnerA).toBe(winnerB)
			expect(framesA).toBe(framesB)
			expect(simA.fighters[1].health).toBe(simB.fighters[1].health)
			expect(simA.fighters[2].health).toBe(simB.fighters[2].health)
		end
	)

	it("босс старшего тира уверенно побеждает младшего", function()
		for _, pair in { { 3, 9 }, { 8, 16 }, { 13, 20 } } do
			local strongWins = 0
			for seed = 1, 4 do
				-- Меняем стороны, чтобы исключить преимущество слота.
				if seed % 2 == 0 then
					strongWins += if aiDuel(pair[1], pair[2], seed) == 2 then 1 else 0
				else
					strongWins += if aiDuel(pair[2], pair[1], seed) == 1 then 1 else 0
				end
			end
			expect(strongWins >= 3).toBeTruthy()
		end
	end)

	it("сильный ИИ блокирует натиск намного чаще слабого", function()
		local weak = blockRateAgainstRush(1, 3600)
		local strong = blockRateAgainstRush(18, 3600)
		expect(strong > weak + 0.15).toBeTruthy()
		expect(weak < 0.3).toBeTruthy()
	end)

	it(
		"использует весь арсенал: атаки, блок, прыжки, особые приёмы, анти-эйр",
		function()
			local events, visited = {}, {}
			for seed = 1, 3 do
				local _, _, duelEvents, duelVisited = aiDuel(15, 15, seed)
				for kind, count in duelEvents do
					events[kind] = (events[kind] or 0) + count
				end
				for state in duelVisited do
					visited[state] = true
				end
			end
			for _, kind in { "Hit", "Block", "Jump", "Special", "KO" } do
				expect((events[kind] or 0) > 0).toBeTruthy()
			end
			for _, state in { "Neutral", "Attack", "Defend", "Punish", "AntiAir", "JumpIn", "Recover" } do
				expect(visited[state] == true).toBeTruthy()
			end
		end
	)
end)

describe("Механики в симуляции", function()
	-- Прямой удар «Рукой» бойца 1 по стоящему бойцу 2. Возвращает урон.
	local function jab(sim)
		sim.fighters[1].x = -1.25
		sim.fighters[2].x = 1.25
		local health = sim.fighters[2].health
		Simulation.step(sim, { { held = 0, pressed = InputBits.Light }, InputBits.empty() })
		for _ = 1, 12 do
			Simulation.step(sim, { InputBits.empty(), InputBits.empty() })
		end
		return health - sim.fighters[2].health
	end

	it(
		"«Железная кожа»: первый удар серии — вполсилы, следующие — как обычно",
		function()
			local normal = jab(Simulation.new({ characters = { "rook", "rook" } }))
			local sim = Simulation.new({ characters = { "rook", "rook" } })
			sim.fighters[2].modifiers.firstHitTaken = 0.5
			local first = jab(sim)
			expect(first).toBeCloseTo(normal * 0.5, 1)
			-- Удар внутри серии (защитник уже пропустил удар) — без «железной кожи», как обычно.
			local combo = Simulation.new({ characters = { "rook", "rook" } })
			combo.fighters[2].modifiers.firstHitTaken = 0.5
			combo.fighters[2].comboHits = 1
			local plainCombo = Simulation.new({ characters = { "rook", "rook" } })
			plainCombo.fighters[2].comboHits = 1
			expect(jab(combo)).toBe(jab(plainCombo))
		end
	)

	it("«Вампиризм» лечит атакующего, «Напор» ускоряет шкалу", function()
		local plain = Simulation.new({ characters = { "rook", "rook" } })
		plain.fighters[1].health = 500
		local plainDamage = jab(plain)
		local plainMeter = plain.fighters[1].meter

		local sim = Simulation.new({ characters = { "rook", "rook" } })
		sim.fighters[1].health = 500
		sim.fighters[1].modifiers.lifesteal = 0.2
		sim.fighters[1].modifiers.meterGain = 1.35
		local damage = jab(sim)
		expect(damage).toBe(plainDamage)
		expect(sim.fighters[1].health).toBe(500 + math.floor(damage * 0.2 + 0.5))
		expect(sim.fighters[1].meter).toBeCloseTo(plainMeter * 1.35, 1e-6)
	end)

	it("«Ярость»: множитель наносимого урона", function()
		local normal = jab(Simulation.new({ characters = { "rook", "rook" } }))
		local sim = Simulation.new({ characters = { "rook", "rook" } })
		sim.fighters[1].modifiers.damageDealt = 1.2
		expect(jab(sim)).toBeCloseTo(normal * 1.2, 1)
	end)

	it("ИИ не делает случайных рывков двойным нажатием", function()
		local sim = Simulation.new({ characters = { "rook", "rook" } })
		sim.fighters[1].tapDash = false
		local directions = { InputBits.Right, 0, InputBits.Right }
		for _, held in directions do
			Simulation.step(sim, { { held = held, pressed = 0 }, InputBits.empty() })
		end
		expect(sim.fighters[1].state).toBe("Walk")
	end)
end)
