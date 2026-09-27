-- Особые приёмы всех 16 бойцов и 6 способов доставки суперов (симуляция на сервере).

local Simulation = requireShared("Combat", "Simulation")
local InputBits = requireShared("Combat", "InputBits")
local Snapshot = requireShared("Combat", "Snapshot")
local Projectiles = requireShared("Combat", "Projectiles")
local CharacterRegistry = requireShared("Characters", "CharacterRegistry")
local GameConfig = requireShared("Config", "GameConfig")

local EMPTY = { held = 0, pressed = 0 }
local METER_MAX = GameConfig.SuperMeter.Max

-- Бой a против b на дистанции distance (a слева).
local function duel(a, b, distance)
	local sim = Simulation.new({ characters = { a, b or "rook" } })
	sim.fighters[1].x = -distance / 2
	sim.fighters[2].x = distance / 2
	return sim
end

--[[
	Прогнать кадры. input1/input2 — таблица ввода или функция(frame) → ввод.
	Возвращает список событий.
]]
local function run(sim, frames, input1, input2)
	local events = {}
	for frame = 1, frames do
		local a = if type(input1) == "function" then input1(frame) else (input1 or EMPTY)
		local b = if type(input2) == "function" then input2(frame) else (input2 or EMPTY)
		Simulation.step(sim, { a, b })
		for _, event in sim.events do
			event.frame = frame
			table.insert(events, event)
		end
	end
	return events
end

-- Нажать кнопку на первом кадре (дальше держать held).
local function tap(bit, held)
	return function(frame)
		return { held = held or 0, pressed = if frame == 1 then bit else 0 }
	end
end

local function find(events, kind, slot)
	for _, event in events do
		if event.kind == kind and (slot == nil or event.slot == slot) then
			return event
		end
	end
	return nil
end

local function count(events, kind, slot)
	local total = 0
	for _, event in events do
		if event.kind == kind and (slot == nil or event.slot == slot) then
			total += 1
		end
	end
	return total
end

-- Удержание «назад» для бойца 2 (стоит справа, назад — вправо).
local BLOCK2 = { held = InputBits.Right, pressed = 0 }
local LOW_BLOCK2 = { held = bit32.bor(InputBits.Right, InputBits.Down), pressed = 0 }

describe("Снаряды", function()
	it(
		"Rook: снаряд летит, попадает, исчезает; бросающий не «застывает»",
		function()
			local sim = duel("rook", "brakk", 14)
			local events = run(sim, 60, tap(InputBits.Special))
			local spawn = find(events, "Projectile", 1)
			expect(spawn ~= nil).toBeTruthy()
			expect(spawn.tag).toBe("Orb")
			local hit = find(events, "Hit", 2)
			expect(hit ~= nil).toBeTruthy()
			expect(hit.value > 0).toBeTruthy()
			expect(#sim.projectiles).toBe(0)
			expect(find(events, "ProjectileEnd", 1).tag).toBe("Hit")
			expect(sim.fighters[1].hitstop).toBe(0)
		end
	)

	it("одновременно — только один свой снаряд", function()
		local sim = duel("rook", "rook", 24)
		run(sim, 16, tap(InputBits.Special))
		expect(#sim.projectiles).toBe(1)
		run(sim, 30, function(frame)
			return { held = 0, pressed = if frame % 5 == 0 then InputBits.Special else 0 }
		end)
		expect(#sim.projectiles <= 1).toBeTruthy()
		expect(Projectiles.countOwned(sim, 1, "Orb") <= 1).toBeTruthy()
	end)

	it("встречные снаряды гасят друг друга", function()
		local sim = duel("rook", "rook", 30)
		local events = run(sim, 60, tap(InputBits.Special), tap(InputBits.Special))
		expect(count(events, "ProjectileEnd")).toBe(2)
		expect(find(events, "ProjectileEnd").tag).toBe("Clash")
		expect(find(events, "Hit")).toBe(nil)
	end)

	it("снаряд блокируется (урон по блоку, без падения)", function()
		local sim = duel("rook", "brakk", 14)
		local health = sim.fighters[2].health
		local events = run(sim, 60, tap(InputBits.Special), BLOCK2)
		expect(find(events, "Block", 2) ~= nil).toBeTruthy()
		expect(find(events, "Hit", 2)).toBe(nil)
		expect(sim.fighters[2].health < health).toBeTruthy()
	end)

	it(
		"Juno: бумеранг долетает до разворота и возвращается в руки",
		function()
			local sim = duel("juno", "rook", 24)
			sim.fighters[1].x = -20
			sim.fighters[2].x = 4
			sim.fighters[2].invulnerable = 1000 -- диск пролетает сквозь
			local events = run(sim, 150, tap(InputBits.Special))
			local ended = find(events, "ProjectileEnd", 1)
			expect(ended ~= nil).toBeTruthy()
			expect(ended.tag).toBe("Caught")
		end
	)

	it("Juno: бумеранг бьёт и по пути обратно", function()
		local sim = duel("juno", "brakk", 8)
		local events = run(sim, 150, tap(InputBits.Special))
		expect(count(events, "Hit", 2) >= 2).toBeTruthy()
	end)

	it(
		"Astra: навесной снаряд падает на пол вдали и попадает на средней дистанции",
		function()
			local far = duel("astra", "rook", 24)
			local farEvents = run(far, 150, tap(InputBits.Special))
			expect(find(farEvents, "ProjectileEnd", 1).tag).toBe("Ground")
			local sim = duel("astra", "brakk", 14)
			local events = run(sim, 120, tap(InputBits.Special))
			expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
		end
	)

	it(
		"Glacia: волна по земле — низкая: стоячий блок не спасает, сидячий — да",
		function()
			local standing = duel("glacia", "brakk", 12)
			expect(find(run(standing, 90, tap(InputBits.Special), BLOCK2), "Hit", 2) ~= nil).toBeTruthy()
			local crouching = duel("glacia", "brakk", 12)
			local events = run(crouching, 90, tap(InputBits.Special), LOW_BLOCK2)
			expect(find(events, "Block", 2) ~= nil).toBeTruthy()
			expect(find(events, "Hit", 2)).toBe(nil)
		end
	)

	it(
		"Byte: мина лежит, взводится и срабатывает под противником на земле; новая заменяет старую",
		function()
			local sim = duel("byte", "rook", 12)
			run(sim, 30, tap(InputBits.Special))
			expect(#sim.projectiles).toBe(1)
			local mine = sim.projectiles[1]
			expect(mine.kind).toBe("Mine")
			-- Противник заходит на мину.
			local events = run(sim, 90, EMPTY, { held = InputBits.Left, pressed = 0 })
			expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
			expect(#sim.projectiles).toBe(0)

			local again = duel("byte", "rook", 24)
			run(again, 45, tap(InputBits.Special))
			local first = again.projectiles[1]
			run(again, 45, tap(InputBits.Special))
			expect(#again.projectiles).toBe(1)
			expect(again.projectiles[1] ~= first).toBeTruthy()
		end
	)

	it("луч супера сносит снаряды соперника", function()
		local sim = duel("pike", "rook", 30)
		sim.fighters[1].meter = METER_MAX
		-- Rook бросает снаряд, Pike отвечает супером-лучом.
		local events = run(sim, 50, function(frame)
			return { held = 0, pressed = if frame == 14 then InputBits.Super else 0 }
		end, tap(InputBits.Special))
		local swept = false
		for _, event in events do
			if event.kind == "ProjectileEnd" and event.tag == "Swept" then
				swept = true
			end
		end
		expect(swept).toBeTruthy()
	end)

	it("снаряды попадают в снапшот", function()
		local sim = duel("rook", "rook", 30)
		run(sim, 16, tap(InputBits.Special))
		local projectiles = {}
		for _, projectile in sim.projectiles do
			table.insert(projectiles, {
				id = projectile.id,
				owner = projectile.owner,
				kind = Projectiles.kindToIndex(projectile.kind),
				x = projectile.x,
				y = projectile.y,
				direction = projectile.facing,
				age = projectile.age,
			})
		end
		local decoded = Snapshot.decode(Snapshot.encode({
			frame = sim.frame,
			phase = 0,
			timer = 0,
			fighters = { Snapshot.fromFighter(sim.fighters[1]), Snapshot.fromFighter(sim.fighters[2]) },
			projectiles = projectiles,
		}))
		expect(#decoded.projectiles).toBe(1)
		expect(Projectiles.indexToKind(decoded.projectiles[1].kind)).toBe("Orb")
		expect(decoded.projectiles[1].x).toBeCloseTo(sim.projectiles[1].x, 1e-3)
	end)
end)

describe("Рывки и прыжки", function()
	it(
		"Zip: рывок-удар проходит дистанцию при промахе и останавливается при попадании",
		function()
			local sim = duel("zip", "rook", 24)
			local start = sim.fighters[1].x
			run(sim, 45, tap(InputBits.Special))
			local travel = CharacterRegistry.get("zip").special.params.travelDistance
			expect(sim.fighters[1].x - start).toBeCloseTo(travel, 0.6)

			local close = duel("zip", "brakk", 5)
			local events = run(close, 45, tap(InputBits.Special))
			expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
			expect(close.fighters[1].x < close.fighters[2].x).toBeTruthy()
		end
	)

	it("Mira: вращение продвигается вперёд и бьёт несколько раз", function()
		local sim = duel("mira", "brakk", 6)
		local events = run(sim, 60, tap(InputBits.Special))
		expect(count(events, "Hit", 2) >= 2).toBeTruthy()
	end)

	it("Dax: рывок с бронёй выдерживает удар и попадает", function()
		local sim = duel("dax", "rook", 7)
		local events = run(sim, 60, tap(InputBits.Special), function(frame)
			return { held = 0, pressed = if frame == 8 then InputBits.Light else 0 }
		end)
		expect(find(events, "Armor", 1) ~= nil).toBeTruthy()
		expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
	end)

	it("Ashka: апперкот неуязвим на старте и взлетает", function()
		local sim = duel("ashka", "rook", 2.6)
		local highest = 0
		local events = run(sim, 40, tap(InputBits.Special), function(frame)
			highest = math.max(highest, sim.fighters[1].y)
			return { held = 0, pressed = if frame == 1 then InputBits.Light else 0 }
		end)
		expect(find(events, "Hit", 1)).toBe(nil) -- удар Rook прошёл сквозь неуязвимость
		expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
		expect(highest > 2).toBeTruthy()
	end)

	it("Wren: пике — атака сверху, сидячий блок не помогает", function()
		local sim = duel("wren", "brakk", 8)
		local events = run(sim, 60, tap(InputBits.Special), LOW_BLOCK2)
		expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
	end)

	it(
		"Tempest: прыжок-дуга приземляется на дистанции и бьёт сверху",
		function()
			local sim = duel("tempest", "rook", 24)
			local start = sim.fighters[1].x
			local highest = 0
			run(sim, 30, function(frame)
				highest = math.max(highest, sim.fighters[1].y)
				return { held = 0, pressed = if frame == 1 then InputBits.Special else 0 }
			end)
			local params = CharacterRegistry.get("tempest").special.params
			expect(sim.fighters[1].x - start).toBeCloseTo(params.travelDistance, 0.5)
			expect(highest > params.arcHeight * 0.8).toBeTruthy()
			expect(sim.fighters[1].y).toBe(0)

			local hit = duel("tempest", "brakk", 7)
			local events = run(hit, 45, tap(InputBits.Special), LOW_BLOCK2)
			expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
		end
	)

	it("Sable: исчезает (неуязвим) и бьёт из-за спины", function()
		local sim = duel("sable", "brakk", 8)
		local events = run(sim, 40, tap(InputBits.Special), function(frame)
			return { held = 0, pressed = if frame == 3 then InputBits.Heavy else 0 }
		end)
		expect(find(events, "Vanish", 1) ~= nil).toBeTruthy()
		expect(find(events, "Appear", 1) ~= nil).toBeTruthy()
		expect(find(events, "Hit", 1)).toBe(nil)
		expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
		expect(sim.fighters[1].x > sim.fighters[2].x).toBeTruthy()
	end)
end)

describe("Захваты, крюк, контратака", function()
	it("Brakk: захват не блокируется", function()
		local sim = duel("brakk", "rook", 2.6)
		local events = run(sim, 30, tap(InputBits.Special), BLOCK2)
		expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
		expect(find(events, "Block", 2)).toBe(nil)
	end)

	it("Morrow: крюк достаёт издалека и притягивает", function()
		local sim = duel("morrow", "brakk", 9)
		local before = math.abs(sim.fighters[2].x - sim.fighters[1].x)
		local events = run(sim, 45, tap(InputBits.Special))
		expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
		local after = math.abs(sim.fighters[2].x - sim.fighters[1].x)
		expect(before - after > 3).toBeTruthy()
	end)

	it("Pike: выпад бьёт дальше обычных ударов", function()
		local sim = duel("pike", "brakk", 8)
		local events = run(sim, 45, tap(InputBits.Special))
		expect(find(events, "Hit", 2) ~= nil).toBeTruthy()
	end)

	it(
		"Sorren: стойка перехватывает удар и отвечает; захват стойку пробивает",
		function()
			local sim = duel("sorren", "rook", 3)
			local sorrenHealth = sim.fighters[1].health
			local events = run(sim, 40, tap(InputBits.Special), function(frame)
				return { held = 0, pressed = if frame == 3 then InputBits.Heavy else 0 }
			end)
			expect(find(events, "Parry", 1) ~= nil).toBeTruthy()
			expect(sim.fighters[1].health).toBe(sorrenHealth)
			expect(find(events, "Hit", 2) ~= nil).toBeTruthy()

			local grab = duel("sorren", "brakk", 2.6)
			local grabEvents = run(grab, 40, tap(InputBits.Special), function(frame)
				return { held = 0, pressed = if frame == 3 then InputBits.Special else 0 }
			end)
			expect(find(grabEvents, "Parry")).toBe(nil)
			expect(find(grabEvents, "Hit", 1) ~= nil).toBeTruthy()
		end
	)
end)

describe("Суперы", function()
	-- Супер бойца 1 с полной шкалой; возвращает события и был ли ролик.
	local function superFrom(character, distance, opponentInput)
		local sim = duel(character, "brakk", distance)
		sim.fighters[1].meter = METER_MAX
		local events = run(sim, 260, tap(InputBits.Super), opponentInput)
		return events, find(events, "CinematicStart", 1) ~= nil, sim
	end

	it("Rush: рывок через полэкрана — и ролик", function()
		local _, cinematic = superFrom("rook", 9)
		expect(cinematic).toBeTruthy()
	end)

	it("Launcher: неуязвимый взлёт — и ролик", function()
		local _, cinematic = superFrom("ashka", 3)
		expect(cinematic).toBeTruthy()
	end)

	it("Beam: луч достаёт через весь экран", function()
		local _, cinematic = superFrom("pike", 22)
		expect(cinematic).toBeTruthy()
	end)

	it("Barrage: обстрел площади вдали", function()
		local _, cinematic = superFrom("juno", 12)
		expect(cinematic).toBeTruthy()
	end)

	it("Grab: захват-супер не блокируется", function()
		local _, cinematic = superFrom("brakk", 2.6, BLOCK2)
		expect(cinematic).toBeTruthy()
	end)

	it("Counter: стойка-супер срабатывает только на удар", function()
		local _, idle = superFrom("sorren", 3)
		expect(idle).toBe(false)
		local events, cinematic = superFrom("sorren", 3, function(frame)
			return { held = 0, pressed = if frame == 30 then InputBits.Heavy else 0 }
		end)
		expect(find(events, "Parry", 1) ~= nil).toBeTruthy()
		expect(cinematic).toBeTruthy()
	end)

	it(
		"у каждого из 16 бойцов супер попадает в подходящей ситуации",
		function()
			for _, def in CharacterRegistry.list() do
				local distance = if def.super.delivery == "Beam" or def.super.delivery == "Barrage" then 12 else 2.8
				local opponent = if def.super.delivery == "Counter"
					then function(frame)
						return { held = 0, pressed = if frame == 30 then InputBits.Heavy else 0 }
					end
					else nil
				local _, cinematic = superFrom(def.id, distance, opponent)
				if not cinematic then
					error(`супер {def.id} ({def.super.delivery}) не сработал`)
				end
			end
		end
	)
end)

describe("Эффекты на клиенте", function()
	local function training(characterId)
		local game = Harness.new()
		local client = game.addClient("Alice")
		game.step(3)
		local DataService = game.serverRequire("Services", "DataService")
		DataService.get(client.player).ownedCharacters[characterId] = true
		local router = game.serverRequire("Net", "RequestRouter")
		router.handle(client.player, "StartTraining", { characterId = characterId }, 10)
		game.step(12)
		local match = game.serverRequire("Services", "MatchService").getMatchOf(client.player)
		return game, client, match
	end

	local function arenaChild(client, name)
		local arena = client.runtime.services.Workspace:FindFirstChild("Arena")
		return arena and arena:FindFirstChild(name)
	end

	local function effectsCount(client)
		local folder = client.runtime.services.Workspace:FindFirstChild("Effects")
		return if folder then #folder:GetChildren() else 0
	end

	local function tapKey(game, client, key)
		client.runtime.pressKey(key)
		game.step(2)
		client.runtime.releaseKey(key)
	end

	it("снаряд виден на клиенте и исчезает после попадания", function()
		local game, client = training("rook")
		tapKey(game, client, "L")
		local seen = false
		for _ = 1, 40 do
			game.step(1)
			if arenaChild(client, "ProjectileOrb") then
				seen = true
				break
			end
		end
		expect(seen).toBeTruthy()
		game.step(60)
		expect(arenaChild(client, "ProjectileOrb")).toBe(nil)
		expect(game.errors()).toBeEmpty()
	end)

	it(
		"супер: вставка с портретом и названием, ролик с фоном, затем всё убирается",
		function()
			local game, client, match = training("rook")
			match.sim.fighters[1].x = -1.5
			match.sim.fighters[2].x = 1.5
			tapKey(game, client, "I")
			local backdrop, cutIn, portrait = false, false, false
			local function fx()
				return client.player:FindFirstChild("PlayerGui"):FindFirstChild("PixelFightFX")
			end
			for _ = 1, 200 do
				game.step(1)
				backdrop = backdrop or arenaChild(client, "SuperBackdrop") ~= nil
				local gui = fx()
				local band = if gui then client.runtime.findByName(gui, "Band") else nil
				if band then
					cutIn = cutIn or band:FindFirstChild("Title").Text == "VANGUARD BREAKER"
					portrait = portrait or client.runtime.findByName(band, "Rig") ~= nil
				end
			end
			expect(backdrop).toBeTruthy()
			expect(cutIn).toBeTruthy()
			expect(portrait).toBeTruthy()
			game.step(120)
			expect(arenaChild(client, "SuperBackdrop")).toBe(nil)
			expect(client.runtime.findByName(fx(), "SuperCutIn")).toBe(nil)
			expect(game.errors()).toBeEmpty()
		end
	)

	it("луч супера рисуется у Beam-персонажей", function()
		local game, client, match = training("pike")
		match.sim.fighters[2].x = 10
		tapKey(game, client, "I")
		local beam = false
		for _ = 1, 150 do
			game.step(1)
			beam = beam or arenaChild(client, "SuperBeam") ~= nil
		end
		expect(beam).toBeTruthy()
		expect(game.errors()).toBeEmpty()
	end)

	it("аура есть только у Deluxe-персонажей", function()
		local deluxeGame, deluxe = training("ashka")
		deluxeGame.step(40)
		expect(effectsCount(deluxe) > 0).toBeTruthy()
		local standardGame, standard = training("rook")
		standardGame.step(40)
		expect(effectsCount(standard)).toBe(0)
	end)

	it("телепорт: боец исчезает и появляется", function()
		local game, client = training("sable")
		tapKey(game, client, "L")
		local hidden, shownAgain = false, false
		for _ = 1, 60 do
			game.step(1)
			local anchor = arenaChild(client, "Fighter1")
			local sprite = anchor and anchor:FindFirstChild("Sprite")
			if sprite and not sprite.Enabled then
				hidden = true
			elseif hidden and sprite and sprite.Enabled then
				shownAgain = true
			end
		end
		expect(hidden).toBeTruthy()
		expect(shownAgain).toBeTruthy()
		expect(game.errors()).toBeEmpty()
	end)
end)
