-- Сохранения (профиль, сессионная блокировка, миграции) и покупки (ProcessReceipt, Game Pass, монеты, магазин).

local ProfileSchema = requireShared("Data", "ProfileSchema")
local ControlsLayout = requireShared("Config", "ControlsLayout")
local Monetization = requireShared("Config", "Monetization")
local BossRegistry = requireShared("Characters", "BossRegistry")

local MONETIZATION_PATH = "src/shared/Config/Monetization.luau"

-- Конфиг монетизации с «настроенными» ID (в репозитории ID = 0 — не настроены).
local function configuredMonetization()
	local products = {}
	for index, product in Monetization.products do
		local copy = table.clone(product)
		copy.id = 100 + index -- SkipBoss = 101, Coins1000 = 102, Coins3000 = 103
		table.insert(products, copy)
	end
	return {
		gamePasses = { ashka = 201, glacia = 202, tempest = 203, byte = 204, morrow = 205, astra = 206 },
		gamePassPriceHint = Monetization.gamePassPriceHint,
		characterCoinPrice = Monetization.characterCoinPrice,
		arenaPasses = { dragon = 301, neon = 302, cosmos = 303 },
		arenaPassPriceHint = Monetization.arenaPassPriceHint,
		arenaCoinPrice = Monetization.arenaCoinPrice,
		products = products,
	}
end

local function services(game)
	return {
		data = game.serverRequire("Services", "DataService"),
		money = game.serverRequire("Services", "MonetizationService"),
		router = game.serverRequire("Net", "RequestRouter"),
	}
end

local function clientPeek(client, value)
	local Fusion = client.loader.require(client.loader.get("ReplicatedStorage", "Packages", "Fusion"))
	return Fusion.peek(value)
end

local function appState(client)
	return client.require("Controllers", "UIController").getState()
end

local function press(client, name)
	local button = client.find(name)
	assert(button, `нет кнопки {name}`)
	client.runtime.fire(button:FindFirstChild("Face"), "Activated")
end

-- Сообщение, с которым игрока отключили (nil — не отключали).
local function kicked(client)
	local ok, message = pcall(function()
		return client.player.Kicked
	end)
	return if ok then message else nil
end

describe("Профиль: схема и миграции", function()
	it(
		"старые и повреждённые данные приводятся к текущей схеме",
		function()
			local data = ProfileSchema.migrate({
				version = 1,
				coins = "много",
				bossProgress = 99,
				bossClears = { pip = 2, ned = -1, [5] = 1 },
				ownedCharacters = { ashka = true, rook = true, nobody = true, glacia = "yes" },
				controls = "bad",
				junk = 1,
			})
			expect(data.version).toBe(ProfileSchema.VERSION)
			expect(data.coins).toBe(0)
			expect(data.bossProgress).toBe(BossRegistry.count())
			expect(data.bossClears.pip).toBe(2)
			expect(data.bossClears.ned).toBe(nil)
			expect(data.ownedCharacters.ashka).toBe(true)
			expect(data.ownedCharacters.rook).toBe(nil) -- бесплатные не хранятся
			expect(data.ownedCharacters.nobody).toBe(nil)
			expect(data.ownedCharacters.glacia).toBe(nil)
			expect(data.controls.mode).toBe(ControlsLayout.default().mode)
			expect(type(data.purchases)).toBe("table")
			expect((data :: any).junk).toBe(nil)
		end
	)

	it(
		"v3 → v4: найденные комбо — только существующие, без мусора",
		function()
			local data = ProfileSchema.migrate({
				version = 3,
				coins = 10,
				combos = { one_two = true, classic = "yes", nothing = true, [7] = true },
			})
			expect(data.version).toBe(ProfileSchema.VERSION)
			expect(data.combos.one_two).toBe(true)
			expect(data.combos.classic).toBe(nil)
			expect(data.combos.nothing).toBe(nil)
			local fresh = ProfileSchema.migrate({ version = 3, coins = 5 })
			expect(type(fresh.combos)).toBe("table")
			expect(next(fresh.combos)).toBe(nil)
			-- Клиент видит найденные комбо.
			expect(ProfileSchema.toPublic(data).combos.one_two).toBe(true)
		end
	)

	it("журнал покупок хранит только последние записи", function()
		local data = ProfileSchema.default()
		for index = 1, ProfileSchema.MAX_PURCHASES + 20 do
			data.purchases[`p{index}`] = index
		end
		ProfileSchema.trimPurchases(data)
		local count = 0
		for _ in data.purchases do
			count += 1
		end
		expect(count).toBe(ProfileSchema.MAX_PURCHASES)
		expect(data.purchases.p1).toBe(nil)
		expect(data.purchases[`p{ProfileSchema.MAX_PURCHASES + 20}`] ~= nil).toBeTruthy()
	end)
end)

describe("Сохранения", function()
	it(
		"данные сохраняются при выходе и загружаются при следующем входе",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice", nil, 1)
			game.step(3)
			local s = services(game)
			s.data.addCoins(alice.player, 120)
			s.data.recordBossWin(alice.player, "pip", 1, 50)
			local layout = ControlsLayout.default()
			layout.opacity = 0.8
			s.router.handle(alice.player, "SaveControls", layout, 5)
			game.removeClient(alice)
			game.step(2)
			expect(game.backend.saved[1].coins).toBe(170)
			expect(game.backend.sessions[1]).toBe(nil)

			local again = game.addClient("Alice", nil, 1)
			game.step(5)
			expect(s.data.getCoins(again.player)).toBe(170)
			expect(s.data.getBossProgress(again.player)).toBe(1)
			local state = appState(again)
			expect(clientPeek(again, state.coins)).toBe(170)
			expect(clientPeek(again, state.controlsLayout).opacity).toBeCloseTo(0.8)
			expect(game.errors()).toBeEmpty()
		end
	)

	it(
		"сессионная блокировка: профиль, открытый на другом сервере, не загружается повторно",
		function()
			local serverA = Harness.new()
			local serverB = Harness.new({ backend = serverA.backend })
			local alice = serverA.addClient("Alice", nil, 1)
			serverA.step(3)
			local copy = serverB.addClient("Alice", nil, 1)
			serverB.step(3)
			expect(kicked(copy) ~= nil).toBeTruthy()
			expect(kicked(copy)).toContainMatch("сохранения")
			expect(kicked(alice)).toBe(nil)
			-- Изменения на сервере A не потеряны.
			services(serverA).data.addCoins(alice.player, 10)
			serverA.removeClient(alice)
			expect(serverA.backend.saved[1].coins).toBe(10)
		end
	)

	it("профиль забрал другой сервер — игрок отключается", function()
		local game = Harness.new()
		local alice = game.addClient("Alice", nil, 1)
		game.step(3)
		game.backend.sessions[1].endSession()
		game.step(1)
		expect(kicked(alice)).toContainMatch("другом сервере")
		expect(services(game).data.isLoaded(alice.player)).toBe(false)
	end)

	it("не удалось загрузить профиль — понятное отключение", function()
		local game = Harness.new()
		game.backend.failStart = true
		local alice = game.addClient("Alice", nil, 1)
		game.step(3)
		expect(kicked(alice)).toContainMatch("Не удалось загрузить")
	end)
end)

describe("Покупки: Developer Products", function()
	local function shop()
		local game = Harness.new({ overrides = { [MONETIZATION_PATH] = configuredMonetization() } })
		local alice = game.addClient("Alice", nil, 1)
		game.step(3)
		return game, alice, services(game)
	end

	local function receipt(productId, purchaseId, playerId)
		return { PlayerId = playerId or 1, ProductId = productId, PurchaseId = purchaseId, CurrencySpent = 49 }
	end

	it(
		"«Пропустить босса»: выдаётся один раз на чек, повтор чека ничего не выдаёт",
		function()
			local game, alice, s = shop()
			expect(s.money.processReceipt(receipt(101, "p1"))).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(s.data.getBossProgress(alice.player)).toBe(1)
			expect(game.backend.saved[1].purchases.p1 ~= nil).toBeTruthy()
			-- Roblox повторил тот же чек (например, не дошёл ответ).
			expect(s.money.processReceipt(receipt(101, "p1"))).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(s.data.getBossProgress(alice.player)).toBe(1)
			expect(s.money.processReceipt(receipt(101, "p2"))).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(s.data.getBossProgress(alice.player)).toBe(2)
			expect(s.data.getCoins(alice.player)).toBe(0) -- пропуск без награды
			game.step(5)
			expect(alice.find("Notice").Text).toContainMatch("засчитан")
		end
	)

	it(
		"сохранение не прошло — чек не засчитан; повтор после восстановления не выдаёт дважды",
		function()
			local game, alice, s = shop()
			game.backend.saveFails = true
			expect(s.money.processReceipt(receipt(102, "c1"))).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
			expect(s.data.getCoins(alice.player)).toBe(1000)
			game.backend.saveFails = false
			expect(s.money.processReceipt(receipt(102, "c1"))).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(s.data.getCoins(alice.player)).toBe(1000)
			expect(game.backend.saved[1].coins).toBe(1000)
		end
	)

	it(
		"игрока нет на сервере или продукт неизвестен — чек ждёт",
		function()
			local _, _, s = shop()
			expect(s.money.processReceipt(receipt(101, "x", 999))).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
			expect(s.money.processReceipt(receipt(999, "y"))).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
		end
	)
end)

describe("Покупки: бойцы", function()
	it(
		"Game Pass, купленный заранее, открывает бойца при входе; покупка в игре — сразу",
		function()
			local game = Harness.new({ overrides = { [MONETIZATION_PATH] = configuredMonetization() } })
			game.world.ownedPasses["1:201"] = true
			local alice = game.addClient("Alice", nil, 1)
			game.step(3)
			local s = services(game)
			expect(s.data.ownsCharacter(alice.player, "ashka")).toBe(true)
			expect(s.data.ownsCharacter(alice.player, "glacia")).toBe(false)
			local marketplace = game.server.services.MarketplaceService
			marketplace.PromptGamePassPurchaseFinished:Fire(alice.player, 202, true)
			game.step(3)
			expect(s.data.ownsCharacter(alice.player, "glacia")).toBe(true)
			expect(clientPeek(alice, appState(alice).ownedCharacters).glacia).toBe(true)
			-- Отменённая покупка ничего не даёт.
			marketplace.PromptGamePassPurchaseFinished:Fire(alice.player, 203, false)
			expect(s.data.ownsCharacter(alice.player, "tempest")).toBe(false)
		end
	)

	it(
		"за монеты: не хватает — нельзя; хватает — открыт; повторно — нельзя",
		function()
			local game = Harness.new()
			local alice = game.addClient("Alice", nil, 1)
			game.step(3)
			local s = services(game)
			local ok, code = s.router.handle(alice.player, "BuyCharacter", { characterId = "byte" }, 1)
			expect(ok).toBe(false)
			expect(code).toBe("NotEnoughCoins")
			s.data.addCoins(alice.player, Monetization.characterCoinPrice)
			expect((s.router.handle(alice.player, "BuyCharacter", { characterId = "byte" }, 3))).toBe(true)
			expect(s.data.ownsCharacter(alice.player, "byte")).toBe(true)
			expect(s.data.getCoins(alice.player)).toBe(0)
			local _, again = s.router.handle(alice.player, "BuyCharacter", { characterId = "byte" }, 5)
			expect(again).toBe("AlreadyOwned")
			local _, free = s.router.handle(alice.player, "BuyCharacter", { characterId = "rook" }, 7)
			expect(free).toBe("BadRequest")
			-- Купленным бойцом можно играть.
			expect((s.router.handle(alice.player, "StartTraining", { characterId = "byte" }, 9))).toBe(true)
		end
	)
end)

describe("Покупки: премиальные карты", function()
	it(
		"Game Pass и монеты открывают карту; бесплатные доступны всем; профиль v2 → v3",
		function()
			local game = Harness.new({ overrides = { [MONETIZATION_PATH] = configuredMonetization() } })
			game.world.ownedPasses["1:301"] = true
			local alice = game.addClient("Alice", nil, 1)
			game.step(3)
			local s = services(game)
			expect(s.data.ownsArena(alice.player, "dojo")).toBe(true)
			expect(s.data.ownsArena(alice.player, "dragon")).toBe(true) -- Game Pass куплен заранее
			expect(s.data.ownsArena(alice.player, "neon")).toBe(false)
			expect(clientPeek(alice, appState(alice).ownedArenas).dragon).toBe(true)

			local ok, code = s.router.handle(alice.player, "BuyArena", { arenaId = "neon" }, 1)
			expect(ok).toBe(false)
			expect(code).toBe("NotEnoughCoins")
			s.data.addCoins(alice.player, Monetization.arenaCoinPrice)
			expect((s.router.handle(alice.player, "BuyArena", { arenaId = "neon" }, 3))).toBe(true)
			expect(s.data.ownsArena(alice.player, "neon")).toBe(true)
			expect(s.data.getCoins(alice.player)).toBe(0)
			local _, again = s.router.handle(alice.player, "BuyArena", { arenaId = "neon" }, 5)
			expect(again).toBe("AlreadyOwned")
			local _, free = s.router.handle(alice.player, "BuyArena", { arenaId = "dojo" }, 7)
			expect(free).toBe("BadRequest")
			game.step(3)
			expect(alice.find("Notice").Text).toContainMatch("Неон")

			-- Покупка в игре через Game Pass.
			game.server.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(alice.player, 303, true)
			game.step(3)
			expect(s.data.ownsArena(alice.player, "cosmos")).toBe(true)

			-- Старый профиль (v2) получает пустой список карт; мусор отбрасывается.
			local migrated =
				ProfileSchema.migrate({ version = 2, coins = 5, ownedArenas = { dojo = true, neon = true, x = true } })
			expect(migrated.version).toBe(ProfileSchema.VERSION)
			expect(migrated.ownedArenas.neon).toBe(true)
			expect(migrated.ownedArenas.dojo).toBe(nil) -- бесплатные не хранятся
			expect(migrated.ownedArenas.x).toBe(nil)
		end
	)

	it(
		"магазин: вкладка «Карты» — картинки, покупка за монеты и окно Robux",
		function()
			local game = Harness.new({ overrides = { [MONETIZATION_PATH] = configuredMonetization() } })
			local alice = game.addClient("Alice", nil, 1)
			game.step(3)
			local s = services(game)
			alice.click("Магазин")
			game.step(2)
			expect(alice.find("Maps").Visible).toBe(false)
			press(alice, "Tab_Maps")
			game.step(2)
			expect(alice.find("Maps").Visible).toBe(true)
			expect(alice.find("Deluxe").Visible).toBe(false)
			expect(alice.find("Arena_dragon"):FindFirstChild("Picture"):FindFirstChild("ArenaPreview") ~= nil).toBeTruthy()
			press(alice, "ArenaPass_cosmos")
			expect(game.world.prompts[1].id).toBe(303)
			s.data.addCoins(alice.player, Monetization.arenaCoinPrice)
			game.step(3)
			press(alice, "ArenaCoins_dragon")
			game.step(5)
			expect(s.data.ownsArena(alice.player, "dragon")).toBe(true)
			expect(alice.find("Arena_dragon"):FindFirstChild("Owned").Visible).toBe(true)
			expect(game.errors()).toBeEmpty()
		end
	)
end)

describe("Магазин (экран)", function()
	it("карточки Deluxe, покупка за монеты, окна покупки Robux", function()
		local game = Harness.new({ overrides = { [MONETIZATION_PATH] = configuredMonetization() } })
		local alice = game.addClient("Alice", nil, 1)
		game.step(3)
		local s = services(game)
		alice.click("Магазин")
		game.step(2)
		local cards = 0
		for _, child in alice.find("Cards"):GetChildren() do
			if string.sub(child.Name, 1, 5) == "Card_" then
				cards += 1
			end
		end
		expect(cards).toBe(6)

		press(alice, "Pass_astra")
		press(alice, "Product_Coins1000")
		press(alice, "Product_SkipBoss")
		local prompts = game.world.prompts
		expect(#prompts).toBe(3)
		expect(prompts[1].kind).toBe("GamePass")
		expect(prompts[1].id).toBe(206)
		expect(prompts[2].id).toBe(102)
		expect(prompts[3].id).toBe(101)

		s.data.addCoins(alice.player, Monetization.characterCoinPrice)
		game.step(3)
		press(alice, "Coins_morrow")
		game.step(5)
		local card = alice.find("Card_morrow")
		expect(card:FindFirstChild("Owned").Visible).toBe(true)
		expect(card:FindFirstChild("Buy").Visible).toBe(false)
		expect(alice.find("Notice").Text).toContainMatch("открыт")
		expect(game.errors()).toBeEmpty()
		expect(game.warnings()).toBeEmpty()
	end)

	it("ненастроенный товар — подсказка вместо окна покупки", function()
		local game = Harness.new()
		local alice = game.addClient("Alice")
		game.step(3)
		alice.click("Магазин")
		game.step(2)
		press(alice, "Pass_ashka")
		game.step(2)
		expect(#game.world.prompts).toBe(0)
		expect(alice.find("Notice").Text).toContainMatch("не настроен")
	end)

	it(
		"на карте боссов «Пропустить» работает только для следующего босса",
		function()
			local game = Harness.new({ overrides = { [MONETIZATION_PATH] = configuredMonetization() } })
			local alice = game.addClient("Alice")
			game.step(3)
			alice.click("Одиночная игра")
			game.step(2)
			press(alice, "SkipBoss")
			expect(#game.world.prompts).toBe(1)
			alice.runtime.fire(alice.find("Boss_ned"), "Activated")
			game.step(2)
			press(alice, "SkipBoss")
			expect(#game.world.prompts).toBe(1)
		end
	)
end)
