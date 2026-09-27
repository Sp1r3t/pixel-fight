-- Интеграция: клиент → сеть → сервер → снапшоты → отрисовка. Тренировка против манекена.

local function startTraining(options)
	local game = Harness.new(options)
	local client = game.addClient("Alice")
	game.step(2)
	client.click("Тренировка")
	game.step(10)
	return game, client
end

local function serverMatch(game, client)
	local MatchService = game.serverRequire("Services", "MatchService")
	return MatchService.getMatchOf(client.player)
end

local function fighterAnchor(client, slot)
	local arena = client.runtime.services.Workspace:FindFirstChild("Arena")
	return arena and arena:FindFirstChild(`Fighter{slot}`)
end

describe("Тренировка", function()
	it(
		"кнопка «Тренировка» запускает бой: арена, бойцы, экран боя",
		function()
			local game, client = startTraining()
			local match = serverMatch(game, client)
			expect(match ~= nil).toBeTruthy()
			expect(match.mode).toBe("Training")
			expect(client.find("Battle") ~= nil).toBeTruthy()
			expect(client.find("MainMenu")).toBe(nil)
			expect(fighterAnchor(client, 1) ~= nil).toBeTruthy()
			expect(fighterAnchor(client, 2) ~= nil).toBeTruthy()
			local camera = client.runtime.services.Workspace.CurrentCamera
			expect(camera.CameraType).toBe(Enum.CameraType.Scriptable)
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)

	it(
		"удержание D двигает бойца на сервере и на экране клиента",
		function()
			local game, client = startTraining()
			local match = serverMatch(game, client)
			local startX = match.sim.fighters[1].x
			client.runtime.pressKey("D")
			game.step(30)
			client.runtime.releaseKey("D")
			game.step(10)
			local serverX = match.sim.fighters[1].x
			expect(serverX > startX + 1).toBeTruthy()
			local anchor = fighterAnchor(client, 1)
			expect(math.abs(anchor.CFrame.Position.X - serverX) < 0.5).toBeTruthy()
			expect(game.errors()).toBeEmpty()
		end
	)

	it("прыжок виден на клиенте", function()
		local game, client = startTraining()
		client.runtime.pressKey("W")
		game.step(3)
		client.runtime.releaseKey("W")
		local highest = 0
		for _ = 1, 40 do
			game.step(1)
			local anchor = fighterAnchor(client, 1)
			highest = math.max(highest, anchor.CFrame.Position.Y)
		end
		-- Якорь спрайта стоит выше ног на CENTER_OFFSET (~3.7), прыжок добавляет ~7 студов.
		expect(highest > 3.7 + 5).toBeTruthy()
		expect(game.errors()).toBeEmpty()
	end)

	it(
		"нажатие рывка не теряется при задержке и потере пакетов",
		function()
			local game, client = startTraining({ latencyFrames = 4, dropEveryNth = 2 })
			local match = serverMatch(game, client)
			local sawDash = false
			client.runtime.pressKey("LeftShift")
			game.step(1)
			client.runtime.releaseKey("LeftShift")
			for _ = 1, 20 do
				game.step(1)
				if match.sim.fighters[1].state == "Dash" then
					sawDash = true
				end
			end
			expect(sawDash).toBeTruthy()
			expect(game.errors()).toBeEmpty()
		end
	)

	it("манекен не управляется клиентом и стоит на месте", function()
		local game, client = startTraining()
		local match = serverMatch(game, client)
		local dummyX = match.sim.fighters[2].x
		client.runtime.pressKey("A")
		game.step(20)
		client.runtime.releaseKey("A")
		expect(match.sim.fighters[2].x).toBeCloseTo(dummyX)
	end)

	it("пауза → «Выйти» завершает бой и возвращает в меню", function()
		local game, client = startTraining()
		-- В первой тренировке сама открывается памятка «Как играть».
		expect(client.find("HowToPlay") ~= nil).toBeTruthy()
		client.press("GotIt")
		game.step(1)
		expect(client.find("HowToPlay")).toBe(nil)
		expect(client.find("PauseMenu")).toBe(nil)
		client.press("Pause")
		game.step(1)
		expect(client.find("PauseMenu") ~= nil).toBeTruthy()
		client.press("Resume")
		game.step(1)
		expect(client.find("PauseMenu")).toBe(nil)
		expect(serverMatch(game, client) ~= nil).toBeTruthy()
		client.leaveBattle()
		game.step(5)
		expect(serverMatch(game, client)).toBe(nil)
		expect(client.find("MainMenu") ~= nil).toBeTruthy()
		expect(client.runtime.services.Workspace:FindFirstChild("Arena")).toBe(nil)
		expect(game.errors()).toBeEmpty()
		expect(game.warnings()).toBeEmpty()
	end)

	it("сервер не даёт начать бой недоступным персонажем", function()
		local game = Harness.new()
		local client = game.addClient("Mallory")
		game.step(1)
		local RequestRouter = game.serverRequire("Net", "RequestRouter")
		local ok, code = RequestRouter.handle(client.player, "StartTraining", { characterId = "ashka" }, 1)
		expect(ok).toBe(false)
		expect(code).toBe("CharacterNotAvailable")
		ok, code = RequestRouter.handle(client.player, "StartTraining", { characterId = "nobody" }, 1)
		expect(code).toBe("CharacterNotAvailable")
		ok, code = RequestRouter.handle(client.player, "StartTraining", "garbage", 1)
		expect(code).toBe("CharacterNotAvailable")
	end)

	it("выход игрока с сервера завершает его матч", function()
		local game, client = startTraining()
		game.world.removePlayer(client.player)
		game.step(2)
		expect(serverMatch(game, client)).toBe(nil)
	end)
end)
