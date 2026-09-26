-- Боевая система через сеть: клавиши клиента → урон на сервере → эффекты на клиенте.

local function startTraining(options)
	local game = Harness.new(options)
	local client = game.addClient("Alice")
	game.step(2)
	client.click("Тренировка")
	game.step(10)
	local MatchService = game.serverRequire("Services", "MatchService")
	local match = MatchService.getMatchOf(client.player)
	return game, client, match
end

local function tap(client, game, key, frames)
	client.runtime.pressKey(key)
	game.step(1)
	client.runtime.releaseKey(key)
	game.step(frames or 1)
end

local function effectsCount(client)
	local folder = client.runtime.services.Workspace:FindFirstChild("Effects")
	return if folder then #folder:GetChildren() else 0
end

describe("Бой через сеть", function()
	it(
		"J вплотную к манекену — урон на сервере и искры на клиенте",
		function()
			local game, client, match = startTraining()
			-- Подходим к манекену.
			client.runtime.pressKey("D")
			game.step(40)
			client.runtime.releaseKey("D")
			game.step(5)
			local dummy = match.sim.fighters[2]
			local before = dummy.health
			local sparksBefore = effectsCount(client)
			tap(client, game, "J", 12)
			expect(dummy.health < before).toBeTruthy()
			expect(effectsCount(client) > sparksBefore).toBeTruthy()
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)

	it(
		"в тренировке шкала супера полная, I запускает супер с роликом",
		function()
			local game, client, match = startTraining()
			client.runtime.pressKey("D")
			game.step(40)
			client.runtime.releaseKey("D")
			game.step(5)
			expect(match.sim.fighters[1].meter).toBe(1000)
			local dummy = match.sim.fighters[2]
			local before = dummy.health
			tap(client, game, "I", 1)
			local sawCinematic = false
			for _ = 1, 240 do
				game.step(1)
				if match.sim.cinematic then
					sawCinematic = true
				end
			end
			expect(sawCinematic).toBeTruthy()
			expect(dummy.health < before or dummy.health == dummy.maxHealth).toBeTruthy()
			expect(game.errors()).toBeEmpty()
		end
	)

	it("манекен восстанавливает здоровье после комбо", function()
		local game, client, match = startTraining()
		client.runtime.pressKey("D")
		game.step(40)
		client.runtime.releaseKey("D")
		tap(client, game, "K", 20)
		local dummy = match.sim.fighters[2]
		expect(dummy.health < dummy.maxHealth).toBeTruthy()
		game.step(150)
		expect(dummy.health).toBe(dummy.maxHealth)
	end)

	it(
		"компенсация пинга берётся из пинга игрока и ограничена",
		function()
			local game, client, match = startTraining()
			client.player.NetworkPing = 0.05 -- 50 мс → 3 кадра
			game.step(40)
			expect(match.sim.fighters[1].lagFrames).toBe(3)
			client.player.NetworkPing = 2 -- огромный пинг не даёт огромного преимущества
			game.step(40)
			expect(match.sim.fighters[1].lagFrames).toBe(6)
			expect(match.sim.fighters[2].lagFrames).toBe(0) -- манекен/ИИ без компенсации
		end
	)

	it(
		"игрок, заваливающий сервер мусорными пакетами, отключается",
		function()
			local game, client = startTraining()
			local InputService = game.serverRequire("Services", "InputService")
			for index = 1, 600 do
				InputService.receive(client.player, "junk", index, {}, 0)
			end
			game.step(400) -- проверка идёт раз в 5 секунд
			expect(client.player.Kicked ~= nil).toBeTruthy()
		end
	)

	it(
		"анимации ударов отрисовываются без ошибок (все обычные удары)",
		function()
			local game, client = startTraining()
			for _, key in { "J", "K" } do
				tap(client, game, key, 30)
			end
			client.runtime.pressKey("S")
			tap(client, game, "J", 20)
			tap(client, game, "K", 40)
			client.runtime.releaseKey("S")
			client.runtime.pressKey("W")
			game.step(8)
			client.runtime.releaseKey("W")
			tap(client, game, "K", 50)
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)
end)
