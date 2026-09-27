-- Режим боссов целиком: клиент → запрос → сервер → бой с ИИ → итоги → прогресс и экран «Башня боссов».

local BossRegistry = requireShared("Characters", "BossRegistry")
local GameConfig = requireShared("Config", "GameConfig")

local function setup()
	local game = Harness.new()
	local client = game.addClient("Alice")
	game.step(3)
	return game, client
end

local function services(game)
	return {
		match = game.serverRequire("Services", "MatchService"),
		boss = game.serverRequire("Services", "BossService"),
		data = game.serverRequire("Services", "DataService"),
		router = game.serverRequire("Net", "RequestRouter"),
	}
end

local function appState(client)
	return client.require("Controllers", "UIController").getState()
end

-- Значение Fusion Value на клиенте.
local function peek(client, value)
	local Fusion = client.loader.require(client.loader.get("ReplicatedStorage", "Packages", "Fusion"))
	return Fusion.peek(value)
end

-- Прокрутить матч до фазы phase (с ограничением по кадрам).
local function stepUntilPhase(game, match, phase)
	for _ = 1, 1200 do
		if match.ended or (match.flow and match.flow.phase == phase) then
			return
		end
		game.step(1)
	end
	error(`фаза {phase} не наступила`)
end

-- Выиграть (или проиграть) все раунды принудительным нокаутом в начале боя.
local function finishByKnockouts(game, match, loserSlot)
	for _ = 1, 10 do
		if match.ended then
			return
		end
		stepUntilPhase(game, match, "Fight")
		if match.ended then
			return
		end
		local loser = match.sim.fighters[loserSlot]
		loser.health = 0
		loser.ko = true
		game.step(1)
		stepUntilPhase(game, match, "RoundStart")
	end
end

local function startBossViaUi(game, client)
	client.click("Одиночная игра")
	game.step(2)
	client.click("В БОЙ")
	game.step(6)
	return services(game).match.getMatchOf(client.player)
end

describe("Режим боссов: доступ", function()
	it("сначала открыт только первый босс, остальные закрыты", function()
		local game, client = setup()
		local s = services(game)
		local ok, code = s.router.handle(client.player, "StartBoss", { bossId = "ned", characterId = "rook" }, 100)
		expect(ok).toBe(false)
		expect(code).toBe("BossLocked")
		expect(s.match.getMatchOf(client.player)).toBe(nil)
		local okFirst = s.router.handle(client.player, "StartBoss", { bossId = "pip", characterId = "rook" }, 101)
		expect(okFirst).toBe(true)
		expect(game.errors()).toBeEmpty()
	end)

	it(
		"сервер проверяет запрос: мусор, чужой персонаж, неизвестный босс",
		function()
			local game, client = setup()
			local router = services(game).router
			local cases = {
				{ payload = "junk", code = "BadRequest" },
				{ payload = { bossId = 5, characterId = "rook" }, code = "BadRequest" },
				{ payload = { bossId = "nobody", characterId = "rook" }, code = "BadRequest" },
				{ payload = { bossId = "pip", characterId = "ashka" }, code = "CharacterNotAvailable" },
			}
			for index, case in cases do
				local ok, code = router.handle(client.player, "StartBoss", case.payload, index * 2)
				expect(ok).toBe(false)
				expect(code).toBe(case.code)
			end
		end
	)
end)

describe("Режим боссов: бой", function()
	it(
		"кнопка «В БОЙ»: бой до 3 побед против ИИ с именем и цветами босса",
		function()
			local game, client = setup()
			local match = startBossViaUi(game, client)
			local pip = BossRegistry.get("pip")
			expect(match ~= nil).toBeTruthy()
			expect(match.mode).toBe("Boss")
			expect(match.flow.roundsToWin).toBe(GameConfig.RoundsToWin.Boss)
			expect(match.controllers[2].kind).toBe("AI")
			expect(match.sim.fighters[2].tapDash).toBe(false)
			expect(client.find("Battle") ~= nil).toBeTruthy()
			local panel = client.find("FighterPanel2")
			expect(panel:FindFirstChild("Name").Text).toBe(string.upper(pip.name))
			local views = client.require("Controllers", "FightController").getViews()
			expect(views[2].def.palette.primary).toBe(pip.palette.primary)
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)

	it("ИИ босса действительно дерётся с игроком", function()
		local game, client = setup()
		local match = startBossViaUi(game, client)
		stepUntilPhase(game, match, "Fight")
		local player = match.sim.fighters[1]
		for _ = 1, 900 do
			game.step(1)
			if player.health < player.maxHealth then
				break
			end
		end
		expect(player.health < player.maxHealth).toBeTruthy()
		expect(game.errors()).toBeEmpty()
	end)

	it("бонус HP босса применяется", function()
		local game, client = setup()
		local s = services(game)
		local boss = BossRegistry.get("null")
		local match = s.boss.startBoss(client.player, boss, "rook", 1)
		local rook = match.sim.fighters[1]
		expect(match.sim.fighters[2].maxHealth).toBe(math.floor(rook.maxHealth * boss.hpMultiplier + 0.5))
	end)
end)

describe("Режим боссов: прогресс", function()
	it(
		"победа открывает следующего босса и даёт награду только один раз",
		function()
			local game, client = setup()
			local s = services(game)
			local match = startBossViaUi(game, client)
			finishByKnockouts(game, match, 2)
			game.step(5)
			expect(match.ended).toBe(true)
			expect(s.data.getBossProgress(client.player)).toBe(1)
			expect(s.data.getCoins(client.player)).toBe(BossRegistry.get("pip").reward)

			-- Клиент получил профиль и итог боя.
			local state = appState(client)
			expect(peek(client, state.bossProgress)).toBe(1)
			expect(peek(client, state.coins)).toBe(BossRegistry.get("pip").reward)
			expect(client.find("BossMap") ~= nil).toBeTruthy()
			expect(client.findText("Пройдено: 1 / 20", "TextLabel") ~= nil).toBeTruthy()
			expect(client.find("Notice").Text).toContainMatch("повержен")
			local nedName = client.find("Boss_ned"):FindFirstChild("BossName", true)
			expect(nedName.Text).toBe(string.upper(BossRegistry.get("ned").name))
			-- Выбор на карте перешёл к новому открытому боссу.
			expect(peek(client, state.selectedBossId)).toBe("ned")

			-- Повторная победа над тем же боссом: без награды, прогресс не меняется.
			local again = s.boss.startBoss(client.player, BossRegistry.get("pip"), "rook", 2)
			game.step(3)
			finishByKnockouts(game, again, 2)
			game.step(5)
			expect(s.data.getBossProgress(client.player)).toBe(1)
			expect(s.data.getCoins(client.player)).toBe(BossRegistry.get("pip").reward)
			expect(s.data.get(client.player).bossClears.pip).toBe(2)
			expect(game.errors()).toBeEmpty()
		end
	)

	it("поражение и выход из боя не засчитываются", function()
		local game, client = setup()
		local s = services(game)
		local match = startBossViaUi(game, client)
		finishByKnockouts(game, match, 1)
		game.step(5)
		expect(match.ended).toBe(true)
		expect(s.data.getBossProgress(client.player)).toBe(0)
		expect(client.find("Notice").Text).toContainMatch("сильнее")

		local second = s.boss.startBoss(client.player, BossRegistry.get("pip"), "rook", 3)
		game.step(3)
		client.leaveBattle()
		game.step(5)
		expect(second.ended).toBe(true)
		expect(s.data.getBossProgress(client.player)).toBe(0)
		expect(s.data.getCoins(client.player)).toBe(0)
	end)

	it("пропуск босса засчитывает следующего без награды", function()
		local game, client = setup()
		local s = services(game)
		local skipped = s.boss.grantSkip(client.player)
		expect(skipped.id).toBe("pip")
		expect(s.data.getBossProgress(client.player)).toBe(1)
		expect(s.data.getCoins(client.player)).toBe(0)
		local ok = s.router.handle(client.player, "StartBoss", { bossId = "ned", characterId = "rook" }, 50)
		expect(ok).toBe(true)
		-- После последнего босса пропускать нечего.
		s.data.get(client.player).bossProgress = BossRegistry.count()
		expect(s.boss.grantSkip(client.player)).toBe(nil)
	end)
end)

describe("Механики боссов на сервере", function()
	it(
		"«Железная кожа», «Напор», «Вампиризм» выставляют модификаторы",
		function()
			local game, client = setup()
			local s = services(game)
			s.data.get(client.player).bossProgress = 19
			local kessa = s.boss.startBoss(client.player, BossRegistry.get("kessa"), "rook", 1)
			expect(kessa.sim.fighters[2].modifiers.firstHitTaken).toBe(0.5)
			expect(kessa.sim.fighters[1].modifiers.firstHitTaken).toBe(1)
			local lise = s.boss.startBoss(client.player, BossRegistry.get("lise"), "rook", 1)
			expect(lise.sim.fighters[2].modifiers.meterGain > 1).toBeTruthy()
			local tide = s.boss.startBoss(client.player, BossRegistry.get("tidebreaker"), "rook", 1)
			expect(tide.sim.fighters[2].modifiers.lifesteal > 0).toBeTruthy()
		end
	)

	it("«Ярость» включается ниже 35% HP и показывается игроку", function()
		local game, client = setup()
		local s = services(game)
		local match = s.boss.startBoss(client.player, BossRegistry.get("grist"), "rook", 1)
		stepUntilPhase(game, match, "Fight")
		local boss = match.sim.fighters[2]
		expect(boss.modifiers.damageDealt).toBe(1)
		boss.health = math.floor(boss.maxHealth * 0.3)
		game.step(1)
		expect(boss.modifiers.damageDealt > 1).toBeTruthy()
		local sawBanner = false
		for _ = 1, 20 do
			game.step(1)
			local label = client.findText("RAGE!", "TextLabel")
			if label then
				sawBanner = true
				break
			end
		end
		expect(sawBanner).toBeTruthy()
	end)

	it("«Регенерация» восстанавливает HP, если босса не бьют", function()
		local game, client = setup()
		local s = services(game)
		local match = s.boss.startBoss(client.player, BossRegistry.get("oru"), "rook", 1)
		stepUntilPhase(game, match, "Fight")
		local boss = match.sim.fighters[2]
		boss.health = math.floor(boss.maxHealth * 0.5)
		local start = boss.health
		game.step(60 * 5)
		expect(boss.health > start).toBeTruthy()
		expect(boss.health <= start + boss.maxHealth * 0.05).toBeTruthy()
	end)

	it("«Готов к бою»: полная шкала супера в начале раунда", function()
		local game, client = setup()
		local s = services(game)
		local match = s.boss.startBoss(client.player, BossRegistry.get("sovereign"), "rook", 1)
		stepUntilPhase(game, match, "RoundStart")
		game.step(2)
		expect(match.sim.fighters[2].meter).toBe(GameConfig.SuperMeter.Max)
		expect(match.sim.fighters[1].meter).toBe(0)
	end)

	it("«Отражение»: босс сражается персонажем игрока", function()
		local game, client = setup()
		local s = services(game)
		local match = s.boss.startBoss(client.player, BossRegistry.get("wraith"), "mira", 1)
		expect(match.characters[2]).toBe("mira")
		expect(match.sim.fighters[2].characterId).toBe("mira")
	end)
end)

describe("Экран «Башня боссов»", function()
	it(
		"20 карточек; закрытый босс — силуэт, кнопка боя неактивна",
		function()
			local game, client = setup()
			client.click("Одиночная игра")
			game.step(2)
			local tower = client.find("Tower")
			local cards = 0
			for _, child in tower:GetChildren() do
				if string.sub(child.Name, 1, 5) == "Boss_" then
					cards += 1
				end
			end
			expect(cards).toBe(20)
			expect(client.find("BossTitle").Text).toBe(string.upper(BossRegistry.get("pip").name))

			client.runtime.fire(client.find("Boss_ned"), "Activated")
			game.step(2)
			expect(client.find("BossTitle").Text).toBe(string.upper(BossRegistry.get("ned").name))
			expect(client.find("Status").Text).toContainMatch("Закрыт")
			client.click("В БОЙ")
			game.step(4)
			expect(services(game).match.getMatchOf(client.player)).toBe(nil)
			expect(client.find("BossMap") ~= nil).toBeTruthy()
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
		end
	)

	it("«Сменить» открывает выбор бойца и возвращает к башне", function()
		local game, client = setup()
		client.click("Одиночная игра")
		game.step(2)
		client.click("Сменить")
		game.step(2)
		expect(client.find("CharacterSelect") ~= nil).toBeTruthy()
		client.click("← Назад")
		game.step(2)
		expect(client.find("BossMap") ~= nil).toBeTruthy()
	end)
end)
