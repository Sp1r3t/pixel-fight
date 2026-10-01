-- Боевая система: удары, блок, комбо, урон, хитстоп, нокдаун, супер, компенсация пинга.

local Simulation = requireShared("Combat", "Simulation")
local InputBits = requireShared("Combat", "InputBits")
local GameConfig = requireShared("Config", "GameConfig")
local Moves = requireShared("Config", "Moves")
local CharacterRegistry = requireShared("Characters", "CharacterRegistry")

local Combat = GameConfig.Combat
local L, R, U, D = InputBits.Left, InputBits.Right, InputBits.Up, InputBits.Down
local LIGHT, HEAVY, SPECIAL, SUPER = InputBits.Light, InputBits.Heavy, InputBits.Special, InputBits.Super

-- Бой двух персонажей на заданном расстоянии (боец 1 слева).
local function setup(distance, a, b)
	local sim = Simulation.new({ characters = { a or "rook", b or "rook" } })
	sim.fighters[1].x = -distance / 2
	sim.fighters[2].x = distance / 2
	return sim
end

-- Один кадр: ввод первого и второго бойца { held, pressed }.
local function frame(sim, input1, input2)
	Simulation.step(sim, {
		{ held = input1 and input1[1] or 0, pressed = input1 and input1[2] or 0 },
		{ held = input2 and input2[1] or 0, pressed = input2 and input2[2] or 0 },
	})
	return sim.events
end

-- N кадров; нажатие pressed1 — только в первом кадре; held2 — удержание второго бойца.
local function run(sim, frames, held1, pressed1, held2)
	local events = {}
	for index = 1, frames do
		for _, event in frame(sim, { held1 or 0, if index == 1 then pressed1 or 0 else 0 }, { held2 or 0, 0 }) do
			table.insert(events, event)
		end
	end
	return events
end

local function count(events, kind)
	local total = 0
	for _, event in events do
		if event.kind == kind then
			total += 1
		end
	end
	return total
end

local function totalDamage(events)
	local total = 0
	for _, event in events do
		if event.kind == "Hit" or event.kind == "CinematicHit" then
			total += event.value or 0
		end
	end
	return total
end

describe("Удары", function()
	it(
		"удар в прыжке обрывается при приземлении (можно сразу продолжить комбо)",
		function()
			local sim = setup(8.5)
			-- Прыжок вперёд, «Нога» на снижении, затем приземление.
			frame(sim, { bit32.bor(U, R), U })
			for _ = 1, 33 do
				frame(sim, { R, 0 })
			end
			local a = sim.fighters[1]
			frame(sim, { 0, HEAVY })
			expect(a.move).toBe("AirHeavy")
			local landedAt = nil
			for index = 1, 40 do
				frame(sim)
				if a.y <= 0 and landedAt == nil then
					landedAt = index
				end
				if landedAt and a.state ~= "Attack" then
					break
				end
			end
			expect(landedAt ~= nil).toBeTruthy()
			-- Сразу после касания пола — приземление (несколько кадров), а не продолжение удара стоя.
			expect(a.state == "Landing" or a.state == "Idle").toBeTruthy()
			expect(a.move).toBe(nil)
		end
	)

	it("«Рука» попадает вплотную: урон, оглушение, хитстоп", function()
		local sim = setup(2)
		local b = sim.fighters[2]
		local events = run(sim, 8, 0, LIGHT)
		expect(count(events, "Hit")).toBe(1)
		expect(b.health).toBe(b.maxHealth - Moves.normals.Light1.data.damage)
		expect(b.state).toBe("Hitstun")
		expect(b.hitstop > 0 or b.stun > 0).toBeTruthy()
	end)

	it("вне дальности удар промахивается", function()
		local sim = setup(4)
		local events = run(sim, 20, 0, LIGHT)
		expect(count(events, "Hit")).toBe(0)
		expect(sim.fighters[2].health).toBe(sim.fighters[2].maxHealth)
	end)

	it("во время хитстопа бойцы не двигаются", function()
		local sim = setup(2)
		run(sim, 30, 0, HEAVY) -- «Нога» — длинный хитстоп
		local sim2 = setup(2)
		local positions = {}
		for _ = 1, 20 do
			frame(sim2, { 0, if #positions == 0 then HEAVY else 0 })
			table.insert(positions, { sim2.fighters[2].x, sim2.fighters[2].hitstop })
		end
		local frozenSeen = false
		for index = 2, #positions do
			if positions[index][2] > 0 and positions[index - 1][2] > 0 then
				expect(positions[index][1]).toBeCloseTo(positions[index - 1][1])
				frozenSeen = true
			end
		end
		expect(frozenSeen).toBeTruthy()
	end)

	it("персонаж с высоким уроном бьёт сильнее", function()
		local strong = setup(2, "brakk", "rook")
		run(strong, 10, 0, LIGHT)
		local weak = setup(2, "juno", "rook")
		run(weak, 10, 0, LIGHT)
		local strongDamage = strong.fighters[2].maxHealth - strong.fighters[2].health
		local weakDamage = weak.fighters[2].maxHealth - weak.fighters[2].health
		expect(strongDamage > weakDamage).toBeTruthy()
	end)

	it(
		"дальность персонажа увеличивает досягаемость обычных ударов",
		function()
			-- Pike (дальность 8) достаёт там, где Dax (дальность 2) промахивается.
			local long = setup(3.4, "pike", "rook")
			local longEvents = run(long, 20, 0, LIGHT)
			local short = setup(3.4, "dax", "rook")
			local shortEvents = run(short, 20, 0, LIGHT)
			expect(count(longEvents, "Hit")).toBe(1)
			expect(count(shortEvents, "Hit")).toBe(0)
		end
	)
end)

describe("Блок", function()
	it("удержание «назад» блокирует обычный удар", function()
		local sim = setup(2)
		local events = run(sim, 10, 0, LIGHT, R) -- боец 2 справа: «назад» = вправо
		expect(count(events, "Block")).toBe(1)
		expect(count(events, "Hit")).toBe(0)
		expect(sim.fighters[2].health).toBe(sim.fighters[2].maxHealth)
	end)

	it(
		"низкий удар проходит через блок стоя, но блокируется сидя",
		function()
			local stand = setup(2)
			local hits = run(stand, 10, D, LIGHT, R)
			expect(count(hits, "Hit")).toBe(1)
			local crouch = setup(2)
			local blocked = run(crouch, 10, D, LIGHT, bit32.bor(R, D))
			expect(count(blocked, "Block")).toBe(1)
		end
	)

	it(
		"удар в прыжке (сверху) проходит через блок сидя, но блокируется стоя",
		function()
			local function jumpAttack(defenderHeld)
				-- Вертикальный прыжок вплотную, «Нога» в прыжке на снижении.
				local sim = setup(2.5)
				local events = {}
				for index = 1, 70 do
					local pressed = if index == 36 then HEAVY else 0
					local held = if index <= 2 then U else 0
					local guard = if index >= 30 then defenderHeld else 0
					for _, event in frame(sim, { held, pressed }, { guard, 0 }) do
						table.insert(events, event)
					end
				end
				return events
			end
			expect(count(jumpAttack(bit32.bor(R, D)), "Hit")).toBe(1)
			expect(count(jumpAttack(R), "Block")).toBe(1)
		end
	)

	it(
		"удержание «назад» рядом с атакующим включает стойку блока",
		function()
			local sim = setup(4)
			frame(sim, { 0, HEAVY }, { R, 0 })
			frame(sim, { 0, 0 }, { R, 0 })
			expect(sim.fighters[2].state).toBe("Block")
			expect(sim.fighters[2].vx).toBe(0)
		end
	)

	it(
		"блоком нельзя проиграть обычным ударом (урон по блоку не убивает)",
		function()
			local sim = setup(2, "rook", "rook")
			sim.fighters[2].health = 1
			run(sim, 30, 0, HEAVY, R)
			expect(sim.fighters[2].health).toBe(1)
			expect(sim.fighters[2].ko).toBe(false)
		end
	)
end)

describe("Комбо", function()
	it(
		"цепочка «Рука» ×3 с уменьшением урона каждого следующего удара",
		function()
			local sim = setup(2)
			local events = {}
			for index = 1, 100 do
				local pressed = if index == 1 or index == 12 or index == 24 then LIGHT else 0
				for _, event in frame(sim, { 0, pressed }) do
					table.insert(events, event)
				end
			end
			local hits = {}
			for _, event in events do
				if event.kind == "Hit" then
					table.insert(hits, event.value)
				end
			end
			expect(#hits).toBe(3)
			local d = Moves.normals
			expect(hits[1]).toBe(d.Light1.data.damage)
			expect(hits[2]).toBe(math.floor(d.Light2.data.damage * 0.9 + 0.5))
			expect(hits[3]).toBe(math.floor(d.Light3.data.damage * 0.8 + 0.5))
			expect(count(events, "ComboEnd")).toBe(1)
		end
	)

	it("без попадания цепочка не продолжается", function()
		local sim = setup(6)
		local moves = {}
		for index = 1, 40 do
			local pressed = if index == 1 or index == 10 then LIGHT else 0
			frame(sim, { 0, pressed })
			if sim.fighters[1].move then
				moves[sim.fighters[1].move] = true
			end
		end
		expect(moves.Light2).toBe(nil)
	end)

	it("обычный удар отменяется в особый приём при попадании", function()
		local sim = setup(2)
		local sawSpecial = false
		for index = 1, 60 do
			local pressed = if index == 1 then LIGHT elseif index == 8 then SPECIAL else 0
			frame(sim, { 0, pressed })
			if sim.fighters[1].move == "Special" then
				sawSpecial = true
			end
		end
		expect(sawSpecial).toBeTruthy()
	end)

	it("урон в длинном комбо не падает ниже минимума", function()
		local sim = setup(2)
		sim.fighters[2].comboHits = 20
		local events = run(sim, 20, 0, HEAVY)
		local expected = math.floor(Moves.normals.Heavy.data.damage * Combat.ComboScalingMin + 0.5)
		expect(totalDamage(events)).toBe(expected)
	end)

	it(
		"контрудар: попадание в начинающего атаку наносит больше урона",
		function()
			local sim = setup(2)
			-- Боец 2 начинает «Ногу» (медленную), боец 1 успевает ударить «Рукой».
			frame(sim, { 0, 0 }, { 0, HEAVY })
			local events = run(sim, 10, 0, LIGHT)
			local counter = false
			for _, event in events do
				if event.kind == "Hit" and event.tag == "Counter" then
					counter = true
					expect(event.value).toBe(
						math.floor(Moves.normals.Light1.data.damage * Combat.CounterHitDamage + 0.5)
					)
				end
			end
			expect(counter).toBeTruthy()
		end
	)
end)

describe("Нокдаун и воздух", function()
	it("подсечка сбивает с ног; лежащий неуязвим и встаёт", function()
		local sim = setup(2.5)
		local states = {}
		for index = 1, 120 do
			frame(sim, { if index < 20 then D else 0, if index == 1 then HEAVY else 0 })
			states[sim.fighters[2].state] = true
		end
		expect(states.Knockdown).toBe(true)
		expect(states.WakeUp).toBe(true)
		expect(sim.fighters[2].state).toBe("Idle")
	end)

	it("по лежащему противнику удары не проходят", function()
		local sim = setup(2.5)
		for index = 1, 40 do
			frame(sim, { if index < 20 then D else 0, if index == 1 then HEAVY else 0 })
		end
		expect(sim.fighters[2].state).toBe("Knockdown")
		local health = sim.fighters[2].health
		local events = run(sim, 12, 0, LIGHT)
		expect(count(events, "Hit")).toBe(0)
		expect(sim.fighters[2].health).toBe(health)
	end)

	it(
		"попадание по противнику в воздухе подбрасывает и роняет его",
		function()
			local sim = setup(3)
			local states = {}
			for index = 1, 90 do
				-- Боец 2 прыгает на месте, боец 1 бьёт «Рукой», когда тот отрывается от земли.
				local pressed1 = if index == 1 then LIGHT else 0
				frame(sim, { 0, pressed1 }, { if index <= 2 then U else 0, 0 })
				states[sim.fighters[2].state] = true
			end
			expect(states.Juggle).toBe(true)
			expect(states.Knockdown).toBe(true)
		end
	)
end)

describe("Супер", function()
	it("без полной шкалы супер не выходит", function()
		local sim = setup(2)
		run(sim, 30, 0, SUPER)
		expect(sim.fighters[2].health).toBe(sim.fighters[2].maxHealth)
		expect(sim.fighters[1].move).toBe(nil)
	end)

	it("с полной шкалой: вспышка, ролик, урон супера, нокдаун", function()
		local sim = setup(2.5)
		local attacker, defender = sim.fighters[1], sim.fighters[2]
		attacker.meter = GameConfig.SuperMeter.Max
		local events = run(sim, 360, 0, SUPER)
		expect(attacker.meter < GameConfig.SuperMeter.Max).toBeTruthy()
		expect(count(events, "SuperFlash")).toBe(1)
		expect(count(events, "CinematicStart")).toBe(1)
		expect(count(events, "CinematicEnd")).toBe(1)
		local def = CharacterRegistry.get("rook")
		local expected = math.floor(def.super.move.damage * attacker.stats.damageMultiplier + 0.5)
		expect(defender.maxHealth - defender.health).toBe(expected)
		expect(count(events, "CinematicHit")).toBe(def.super.cinematic.hits)
		expect(defender.state ~= "Cinematic").toBeTruthy()
	end)

	it("во время вспышки и ролика симуляция на паузе", function()
		local sim = setup(2.5)
		sim.fighters[1].meter = GameConfig.SuperMeter.Max
		frame(sim, { 0, SUPER })
		expect(Simulation.isPaused(sim)).toBe(true)
		local x = sim.fighters[2].x
		run(sim, 10, 0, 0, L)
		expect(sim.fighters[2].x).toBeCloseTo(x)
	end)

	it("шкала растёт от нанесённого и полученного урона", function()
		local sim = setup(2)
		run(sim, 20, 0, HEAVY)
		local a, b = sim.fighters[1], sim.fighters[2]
		expect(a.meter > 0).toBeTruthy()
		expect(b.meter > 0).toBeTruthy()
		expect(a.meter > b.meter).toBeTruthy()
	end)
end)

describe("Пространство и защита", function()
	it("у стены отбрасывает атакующего", function()
		local sim = Simulation.new({ characters = { "rook", "rook" } })
		local wall = GameConfig.Physics.ArenaHalfWidth - GameConfig.Physics.PushWidth / 2
		sim.fighters[2].x = wall
		sim.fighters[1].x = wall - 2
		local startX = sim.fighters[1].x
		run(sim, 30, 0, HEAVY)
		expect(sim.fighters[2].x).toBeCloseTo(wall)
		expect(sim.fighters[1].x < startX - 0.3).toBeTruthy()
	end)

	it("отскок назад неуязвим: удар проходит насквозь", function()
		local sim = setup(2)
		-- Боец 2 делает отскок (кнопка рывка + «назад»), боец 1 сразу бьёт.
		frame(sim, { 0, LIGHT }, { R, InputBits.Dash })
		local events = run(sim, 6, 0, 0)
		expect(count(events, "Hit")).toBe(0)
	end)

	it(
		"компенсация пинга: попадание по недавнему положению цели",
		function()
			local function attempt(lagFrames)
				local sim = setup(2)
				Simulation.setLagFrames(sim, 1, lagFrames)
				local events = {}
				for index = 1, 12 do
					-- Цель стоит в зоне удара, а прямо перед активными кадрами оказывается вне её:
					-- атакующий с пингом видел её ещё в зоне удара.
					if index == Moves.normals.Light1.data.startup + 1 then
						sim.fighters[2].x = sim.fighters[1].x + 4
					end
					for _, event in frame(sim, { 0, if index == 1 then LIGHT else 0 }) do
						table.insert(events, event)
					end
				end
				return count(events, "Hit")
			end
			expect(attempt(0)).toBe(0)
			expect(attempt(6)).toBe(1)
		end
	)

	it("компенсация пинга ограничена сверху", function()
		local sim = setup(2)
		Simulation.setLagFrames(sim, 1, 1000)
		expect(sim.fighters[1].lagFrames).toBe(Combat.MaxLagCompensationFrames)
	end)

	it(
		"захват нельзя заблокировать, но нельзя схватить прыгнувшего",
		function()
			local grab = setup(2.4, "brakk", "rook")
			local events = run(grab, 20, 0, SPECIAL, R)
			expect(count(events, "Hit")).toBe(1)

			local airborne = setup(2.4, "brakk", "rook")
			local airEvents = {}
			for index = 1, 30 do
				for _, event in
					frame(airborne, { 0, if index == 5 then SPECIAL else 0 }, { if index == 1 then U else 0, 0 })
				do
					table.insert(airEvents, event)
				end
			end
			expect(count(airEvents, "Hit")).toBe(0)
		end
	)

	it("нокаут: HP кончилось — боец падает и больше не встаёт", function()
		local sim = setup(2)
		sim.fighters[2].health = 10
		local events = run(sim, 120, 0, HEAVY)
		expect(count(events, "KO")).toBe(1)
		expect(sim.fighters[2].health).toBe(0)
		expect(sim.fighters[2].state).toBe("KO")
	end)
end)
