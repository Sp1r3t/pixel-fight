-- Режим боссов целиком: клиент → запрос → сервер → бой с ИИ → итоги → прогресс и экран «Башня боссов».

local BossRegistry = requireShared("Characters", "BossRegistry")
local GameConfig = requireShared("Config", "GameConfig")

local function setup(options)
	local game = Harness.new(options)
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
		"смерть в первом раунде: переигровка сохраняет прошлый счёт и восстанавливает обоих бойцов",
		function()
			local game, client = setup()
			local s = services(game)
			local match = startBossViaUi(game, client)
			stepUntilPhase(game, match, "Fight")
			match.flow.wins = { 1, 1 }
			match.sim.fighters[1].health = 0
			match.sim.fighters[1].ko = true
			game.step(2)
			expect(match.flow.phase).toBe("RoundEnd")
			expect(match.paused).toBe(true)
			expect(peek(client, appState(client).bossOffer).duration).toBe(5)
			expect(s.boss.grantOffer(client.player, "BossRetry")).toBe(true)
			expect(match.flow.wins[1]).toBe(1)
			expect(match.flow.wins[2]).toBe(1)
			expect(match.flow.round).toBe(1)
			for _, fighter in match.sim.fighters do
				expect(fighter.health).toBe(fighter.maxHealth)
				expect(fighter.ko).toBe(false)
			end
			expect(match.flow.phase).toBe("RoundStart")
			expect(match.paused).toBe(false)
			expect(game.errors()).toBeEmpty()
		end
	)

	for _, dismiss in { false, true } do
		it(
			if dismiss
				then "крестик переигровки возвращает в лобби сразу"
				else "через 5 секунд переигровка возвращает в лобби",
			function()
				local game, client = setup()
				local s = services(game)
				local match = startBossViaUi(game, client)
				stepUntilPhase(game, match, "Fight")
				match.sim.fighters[1].health = 0
				match.sim.fighters[1].ko = true
				game.step(2)
				if dismiss then
					client.press("Close")
					game.step(3)
				else
					game.step(290)
					expect(match.ended).toBe(false)
					game.step(15)
				end
				expect(match.ended).toBe(true)
				expect(client.find("MainMenu") ~= nil).toBeTruthy()
				expect(s.data.getBossProgress(client.player)).toBe(0)
				expect(client.find("BossOffer")).toBe(nil)
				expect(game.errors()).toBeEmpty()
			end
		)
	end

	it(
		"усиление: пауза при покупке, чек выдаёт бонус один раз и продолжает бой",
		function()
			local monetization = table.clone(requireShared("Config", "Monetization"))
			monetization.products = {
				{ key = "BossBoost", kind = "BossBoost", id = 9001, priceHint = 5, name = "Усиление" },
				{ key = "BossRetry", kind = "BossRetry", id = 9002, priceHint = 5, name = "Переигровка" },
			}
			local game, client = setup({ overrides = { ["src/shared/Config/Monetization.luau"] = monetization } })
			local match = startBossViaUi(game, client)
			stepUntilPhase(game, match, "Fight")
			local fighter = match.sim.fighters[1]
			fighter.health = math.floor(fighter.maxHealth * 0.29)
			game.step(2)
			expect(match.paused).toBe(false)
			client.press("Buy")
			game.step(3)
			expect(match.paused).toBe(true)
			local frame = match.sim.frame
			game.step(450)
			expect(match.sim.frame).toBe(frame)
			expect(match.data.bossOffer.pending).toBe(true)
			local monetizationService = game.serverRequire("Services", "MonetizationService")
			local receipt = { PlayerId = client.player.UserId, ProductId = 9001, PurchaseId = "boost-one" }
			expect(monetizationService.processReceipt(receipt)).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(monetizationService.processReceipt(receipt)).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(fighter.modifiers.damageDealt).toBe(1.5)
			expect(fighter.modifiers.meterGain).toBe(1.5)
			expect(fighter.modifiers.damageTaken).toBe(0.7)
			expect(match.paused).toBe(false)
			game.step(3)
			expect(client.find("BossOffer")).toBe(nil)
			expect(game.errors()).toBeEmpty()
		end
	)

	it("усиление исчезает через 7 секунд, не останавливая бой", function()
		local game, client = setup()
		local match = startBossViaUi(game, client)
		stepUntilPhase(game, match, "Fight")
		match.controllers[2] = { kind = "Dummy" }
		match.sim.fighters[1].health = math.floor(match.sim.fighters[1].maxHealth * 0.29)
		game.step(2)
		expect(client.find("BossOffer") ~= nil).toBeTruthy()
		local frame = match.sim.frame
		game.step(425)
		expect(client.find("BossOffer")).toBe(nil)
		expect(match.sim.frame > frame).toBeTruthy()
		expect(match.paused).toBe(false)
		expect(match.sim.fighters[1].modifiers.damageDealt).toBe(1)
		expect(game.errors()).toBeEmpty()
	end)

	it("отмена покупки усиления снимает паузу без бонуса", function()
		local monetization = table.clone(requireShared("Config", "Monetization"))
		monetization.products = {
			{ key = "BossBoost", kind = "BossBoost", id = 9001, priceHint = 5, name = "Усиление" },
		}
		local game, client = setup({ overrides = { ["src/shared/Config/Monetization.luau"] = monetization } })
		local match = startBossViaUi(game, client)
		stepUntilPhase(game, match, "Fight")
		match.sim.fighters[1].health = math.floor(match.sim.fighters[1].maxHealth * 0.29)
		game.step(2)
		client.press("Buy")
		game.step(3)
		expect(match.paused).toBe(true)
		client.runtime.services.MarketplaceService.PromptProductPurchaseFinished:Fire(client.player.UserId, 9001, false)
		game.step(3)
		expect(match.paused).toBe(false)
		expect(match.sim.fighters[1].modifiers.damageDealt).toBe(1)
		expect(client.find("BossOffer")).toBe(nil)
		expect(game.errors()).toBeEmpty()
	end)

	it(
		"крестик усиления закрывает окно, а смерть заменяет его переигровкой",
		function()
			local game, client = setup()
			local match = startBossViaUi(game, client)
			stepUntilPhase(game, match, "Fight")
			match.sim.fighters[1].health = math.floor(match.sim.fighters[1].maxHealth * 0.29)
			game.step(2)
			client.press("Close")
			game.step(3)
			expect(client.find("BossOffer")).toBe(nil)
			expect(match.paused).toBe(false)
			match.sim.fighters[1].health = 0
			match.sim.fighters[1].ko = true
			game.step(2)
			expect(peek(client, appState(client).bossOffer).kind).toBe("BossRetry")
			expect(match.paused).toBe(true)
			expect(game.errors()).toBeEmpty()
		end
	)
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

	it(
		"предлагает усиление при HP <30% против босса с HP >60% и применяет все три бонуса",
		function()
			local game, client = setup()
			local s = services(game)
			local match = startBossViaUi(game, client)
			stepUntilPhase(game, match, "Fight")
			local player = match.sim.fighters[1]
			local boss = match.sim.fighters[2]
			player.health = math.floor(player.maxHealth * 0.29)
			boss.health = math.floor(boss.maxHealth * 0.61)
			game.step(2)
			expect(client.find("BossOffer") ~= nil).toBeTruthy()
			expect(client.find("OfferBox") ~= nil).toBeTruthy()
			expect(match.paused).toBe(false)
			expect(s.boss.grantOffer(client.player, "BossBoost")).toBe(true)
			expect(player.modifiers.damageDealt).toBeCloseTo(1.5)
			expect(player.modifiers.meterGain).toBeCloseTo(1.5)
			expect(player.modifiers.damageTaken).toBeCloseTo(0.7)
			expect(match.paused).toBe(false)
		end
	)

	it(
		"после поражения предлагает 5-секундную переигровку и откатывает только последнее очко босса",
		function()
			local game, client = setup()
			local s = services(game)
			local match = startBossViaUi(game, client)
			match.flow.round = 4
			match.flow.wins = { 1, 3 }
			match.flow.matchWinner = 2
			match.flow.phase = "MatchEnd"
			match.flow.phaseFrame = 179
			game.step(2)
			expect(match.ended).toBe(false)
			expect(match.paused).toBe(true)
			expect(client.find("BossOffer") ~= nil).toBeTruthy()
			expect(client.findText("ПЕРЕИГРАТЬ ПОСЛЕДНИЙ РАУНД", "TextLabel") ~= nil).toBeTruthy()
			expect(s.boss.grantOffer(client.player, "BossRetry")).toBe(true)
			expect(match.flow.wins[1]).toBe(1)
			expect(match.flow.wins[2]).toBe(2)
			expect(match.flow.round).toBe(4)
			expect(match.flow.phase).toBe("RoundStart")
			expect(match.paused).toBe(false)
		end
	)
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
			expect(tower.ClassName).toBe("ScrollingFrame")
			expect(tower.ScrollingDirection).toBe(Enum.ScrollingDirection.X)
			expect(tower.Size.X.Offset >= 900).toBeTruthy()
			expect(client.find("Route") ~= nil).toBeTruthy()
			local firstArt = client.find("ChapterArt_1")
			expect(firstArt ~= nil).toBeTruthy()
			client.press("MapNext")
			game.step(30)
			expect(tower.CanvasPosition.X).toBe(tower.Size.X.Offset)
			expect(client.find("ChapterArt_1")).toBe(firstArt)
			expect(client.find("ChapterArt_3") ~= nil).toBeTruthy()
			local secondArt = client.find("ChapterArt_2")
			tower.CanvasPosition = Vector2.new(tower.CanvasPosition.X + 100, 0)
			game.step(1)
			expect(client.find("ChapterArt_2")).toBe(secondArt)
			game.step(40)
			expect(tower.CanvasPosition.X).toBe(tower.Size.X.Offset)
			for _ = 1, 8 do
				client.press("MapNext")
			end
			game.step(30)
			expect(tower.CanvasPosition.X).toBe(tower.CanvasSize.X.Offset - tower.Size.X.Offset)
			expect(client.find("ChapterArt_5") ~= nil).toBeTruthy()
			expect(client.find("ChapterArt_1")).toBe(nil)
			for _ = 1, 8 do
				client.press("MapPrevious")
			end
			game.step(30)
			expect(tower.CanvasPosition.X).toBe(0)
			expect(client.find("BossTitle").Text).toBe(string.upper(BossRegistry.get("pip").name))

			client.runtime.fire(client.find("Boss_ned"), "Activated")
			game.step(2)
			expect(client.find("BossTitle").Text).toBe(string.upper(BossRegistry.get("ned").name))
			expect(tower.CanvasPosition.X).toBe(0)
			expect(client.find("Status").Text).toContainMatch("Закрыт")
			local lockedButton = client.find("FightBoss")
			client.runtime.fire(lockedButton:FindFirstChild("Face"), "MouseEnter")
			game.step(30)
			expect(lockedButton:FindFirstChild("Body").Position.Y.Offset).toBe(0)
			client.click("В БОЙ")
			game.step(4)
			expect(services(game).match.getMatchOf(client.player)).toBe(nil)
			expect(client.find("BossMap") ~= nil).toBeTruthy()
			expect(game.errors()).toBeEmpty()
			expect(game.warnings()).toBeEmpty()
			-- Selecting a boss and returning from fighter selection retain the entire chapter.
			local later = BossRegistry.list()[11]
			client.runtime.fire(client.find(`Boss_{later.id}`), "Activated")
			game.step(2)
			expect(tower.CanvasPosition.X).toBe(tower.Size.X.Offset * 2)
			client.click("Сменить")
			game.step(2)
			client.click("← Назад")
			game.step(2)
			expect(client.find("Tower").CanvasPosition.X).toBe(tower.Size.X.Offset * 2)
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
