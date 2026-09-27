-- Магазин: косметика, кристаллы, набор новичка, VIP, ежедневная награда, эмоции в бою.

local Monetization = requireShared("Config", "Monetization")
local Cosmetics = requireShared("Config", "Cosmetics")
local CharacterRegistry = requireShared("Characters", "CharacterRegistry")

local MONETIZATION_PATH = "src/shared/Config/Monetization.luau"
local DAY = 86400

-- Настоящий конфиг с «настроенными» ID: продукты 101…, VIP — 401.
local function configured()
	local config = {}
	for key, value in Monetization do
		config[key] = value
	end
	local products = {}
	for index, product in Monetization.products do
		local copy = table.clone(product)
		copy.id = 100 + index
		table.insert(products, copy)
	end
	config.products = products
	config.vipPass = 401
	return config
end

local function productId(key)
	for index, product in Monetization.products do
		if product.key == key then
			return 100 + index
		end
	end
	error(`нет продукта {key}`)
end

local function setup(options)
	local game = Harness.new({ overrides = { [MONETIZATION_PATH] = configured() } })
	if options and options.vip then
		game.world.ownedPasses["1:401"] = true
	end
	local alice = game.addClient("Alice", nil, 1)
	game.step(3)
	return game,
		alice,
		{
			data = game.serverRequire("Services", "DataService"),
			money = game.serverRequire("Services", "MonetizationService"),
			cosmetic = game.serverRequire("Services", "CosmeticService"),
		}
end

local function receipt(id, purchaseId)
	return { PlayerId = 1, ProductId = id, PurchaseId = purchaseId, CurrencySpent = 49 }
end

describe("Косметика: список", function()
	it("у каждого бойца два облика; всё — только внешний вид", function()
		for _, def in CharacterRegistry.list() do
			local skins = Cosmetics.skinsOf(def.id)
			expect(#skins).toBe(2)
			for _, skin in skins do
				expect(skin.palette ~= nil).toBeTruthy()
			end
		end
		for _, item in Cosmetics.items do
			expect(#item.name > 0 and #item.icon > 0).toBeTruthy()
			if item.currency == "Coins" or item.currency == "Crystals" then
				expect(item.price > 0).toBeTruthy()
			end
		end
		expect(#Cosmetics.ofKind("Emote") >= 8).toBeTruthy()
	end)
end)

describe("Покупка косметики", function()
	it(
		"за монеты: не хватает — отказ; хватает — куплено и сразу надето",
		function()
			local _, alice, s = setup()
			local ok, reason = s.money.buyItem(alice.player, "rook_shadow")
			expect(ok).toBe(false)
			expect(reason).toBe("NotEnoughCoins")
			s.data.addCoins(alice.player, 2000)
			expect((s.money.buyItem(alice.player, "rook_shadow"))).toBe(true)
			expect(s.data.getCoins(alice.player)).toBe(500)
			expect(s.data.hasItem(alice.player, "rook_shadow")).toBe(true)
			expect(s.data.getLoadout(alice.player, "rook").skin).toBe("rook_shadow")
			local again, why = s.money.buyItem(alice.player, "rook_shadow")
			expect(again).toBe(false)
			expect(why).toBe("AlreadyOwned")
		end
	)

	it(
		"за кристаллы; бесплатные эмоции есть у всех, VIP-вещь купить нельзя",
		function()
			local _, alice, s = setup()
			expect(s.data.hasItem(alice.player, "emote_thumbs")).toBe(true)
			expect(s.data.hasItem(alice.player, "hit_hearts")).toBe(false)
			local _, reason = s.money.buyItem(alice.player, "hit_hearts")
			expect(reason).toBe("NotEnoughCrystals")
			s.data.addCrystals(alice.player, 100)
			expect((s.money.buyItem(alice.player, "hit_hearts"))).toBe(true)
			expect(s.data.getCrystals(alice.player)).toBe(20)
			expect(s.data.getLoadout(alice.player, "rook").hitEffect).toBe("hit_hearts")
			local vipOk, vipReason = s.money.buyItem(alice.player, "hit_rainbow")
			expect(vipOk).toBe(false)
			expect(vipReason).toBe("BadRequest")
		end
	)

	it("надеть можно только своё и только подходящее", function()
		local _, alice, s = setup()
		expect((s.cosmetic.equip(alice.player, "Skin:rook", "rook_legend"))).toBe(false) -- не куплено
		s.data.grantItem(alice.player, "mira_legend")
		expect((s.cosmetic.equip(alice.player, "Skin:rook", "mira_legend"))).toBe(false) -- чужой облик
		expect((s.cosmetic.equip(alice.player, "Skin:mira", "mira_legend"))).toBe(true)
		expect((s.cosmetic.equip(alice.player, "HitEffect", "mira_legend"))).toBe(false)
		expect((s.cosmetic.equip(alice.player, "Skin:mira", nil))).toBe(true) -- снять
		expect(s.data.getLoadout(alice.player, "mira").skin).toBe(nil)
	end)
end)

describe("Кристаллы и наборы (Robux)", function()
	it("кристаллы выдаются один раз на чек", function()
		local game, alice, s = setup()
		local id = productId("Crystals300")
		expect(s.money.processReceipt(receipt(id, "k1"))).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(s.money.processReceipt(receipt(id, "k1"))).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(s.data.getCrystals(alice.player)).toBe(300)
		expect(game.backend.saved[1].crystals).toBe(300)
	end)

	it(
		"набор новичка: монеты, кристаллы и эмоция — один раз; повтор даёт только кристаллы",
		function()
			local _, alice, s = setup()
			local id = productId("StarterPack")
			local pack = Monetization.starterPack
			expect(s.money.processReceipt(receipt(id, "s1"))).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(s.data.getCoins(alice.player)).toBe(pack.coins)
			expect(s.data.getCrystals(alice.player)).toBe(pack.crystals)
			expect(s.data.hasItem(alice.player, pack.emote)).toBe(true)
			expect(s.money.processReceipt(receipt(id, "s2"))).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
			expect(s.data.getCoins(alice.player)).toBe(pack.coins)
			expect(s.data.getCrystals(alice.player)).toBe(pack.crystals * 2)
		end
	)

	it(
		"VIP: больше монет за награды, «Радуга» доступна, значок в бою",
		function()
			local _, alice, s = setup({ vip = true })
			expect(s.data.isVip(alice.player)).toBe(true)
			expect(s.data.hasItem(alice.player, "hit_rainbow")).toBe(true)
			expect(s.data.addEarnedCoins(alice.player, 100)).toBe(150)
			expect((s.cosmetic.equip(alice.player, "HitEffect", "hit_rainbow"))).toBe(true)
		end
	)
end)

describe("Ежедневная награда", function()
	it(
		"раз в день; серия растёт подряд, пропуск — сначала; 7-й день даёт кристаллы",
		function()
			local _, alice, s = setup()
			local start = 20000 * DAY + 3600
			local ok, info = s.money.claimDaily(alice.player, start)
			expect(ok).toBe(true)
			expect(info.day).toBe(1)
			expect(info.coins).toBe(Monetization.dailyCoins[1])
			local again, reason = s.money.claimDaily(alice.player, start + 3600)
			expect(again).toBe(false)
			expect(reason).toBe("AlreadyClaimed")
			for day = 2, 7 do
				local _, next = s.money.claimDaily(alice.player, start + (day - 1) * DAY)
				expect(next.day).toBe(day)
			end
			expect(s.data.getCrystals(alice.player)).toBe(Monetization.dailyCrystalsDay7)
			-- Пропустили день — серия сначала.
			local _, reset = s.money.claimDaily(alice.player, start + 9 * DAY)
			expect(reset.day).toBe(1)
		end
	)
end)

describe("Облик и эмоции в бою", function()
	it(
		"облик виден в бою всем; эмоция уходит всем участникам, спам ограничен",
		function()
			local game, alice, s = setup()
			s.data.addCoins(alice.player, 2000)
			s.money.buyItem(alice.player, "rook_shadow")
			alice.click("Тренировка")
			game.step(10)
			local state = alice.require("Controllers", "UIController").getState()
			local Fusion = alice.loader.require(alice.loader.get("ReplicatedStorage", "Packages", "Fusion"))
			local battle = Fusion.peek(state.battle)
			local mine = battle.fighters[1]
			expect(mine.palette.primary).toBe(Cosmetics.byId.rook_shadow.palette.primary)

			local ok = s.cosmetic.emote(alice.player, "emote_thumbs", 100)
			expect(ok).toBe(true)
			local fast, why = s.cosmetic.emote(alice.player, "emote_smile", 101)
			expect(fast).toBe(false)
			expect(why).toBe("TooFast")
			local notOwned = s.cosmetic.emote(alice.player, "emote_crown", 110)
			expect(notOwned).toBe(false)
			expect(game.errors()).toBeEmpty()
		end
	)
end)

describe("Экран магазина и меню", function()
	local function faceText(client, name)
		local node = client.find(name)
		assert(node, `нет {name}`)
		return node:FindFirstChild("Face").Text
	end

	it("вкладка «Эффекты»: купить за монеты → сразу надето", function()
		local game, alice, s = setup()
		s.data.addCoins(alice.player, 1000)
		alice.click("Магазин")
		game.step(2)
		alice.press("Tab_Effects")
		game.step(2)
		expect(faceText(alice, "Item_hit_stars")).toBe("🪙 1 000")
		alice.press("Item_hit_stars")
		game.step(4)
		expect(s.data.getCoins(alice.player)).toBe(0)
		expect(faceText(alice, "Item_hit_stars")).toBe("Надето ✓")
		expect(game.errors()).toBeEmpty()
	end)

	it(
		"вкладка «Облики»: купленный облик можно снять и надеть снова",
		function()
			local game, alice, s = setup()
			s.data.addCoins(alice.player, 1500)
			alice.click("Магазин")
			game.step(2)
			alice.press("Tab_Skins")
			game.step(2)
			alice.press("Item_rook_shadow")
			game.step(4)
			expect(faceText(alice, "Item_rook_shadow")).toBe("Надето ✓")
			alice.press("Default_rook")
			game.step(4)
			expect(faceText(alice, "Item_rook_shadow")).toBe("Надеть")
			expect(faceText(alice, "Default_rook")).toBe("Надето ✓")
			expect(s.data.getLoadout(alice.player, "rook").skin).toBe(nil)
		end
	)

	it("кнопка 🎁 в меню выдаёт подарок дня один раз", function()
		local game, alice, s = setup()
		expect(alice.find("Daily"):FindFirstChild("Badge", true).Visible).toBe(true)
		alice.press("Daily")
		game.step(4)
		expect(s.data.getCoins(alice.player)).toBe(Monetization.dailyCoins[1])
		expect(alice.find("Daily"):FindFirstChild("Badge", true).Visible).toBe(false)
		alice.press("Daily")
		game.step(4)
		expect(s.data.getCoins(alice.player)).toBe(Monetization.dailyCoins[1])
	end)

	it(
		"в бою кнопка 😀 открывает эмоции, выбор закрывает список",
		function()
			local game, alice = setup()
			alice.click("Тренировка")
			game.step(10)
			if alice.find("GotIt") then
				alice.press("GotIt")
				game.step(2)
			end
			alice.press("EmoteButton")
			game.step(1)
			expect(alice.find("EmoteRow").Visible).toBe(true)
			alice.press("Emote_emote_thumbs")
			game.step(4)
			expect(alice.find("EmoteRow").Visible).toBe(false)
			expect(game.errors()).toBeEmpty()
		end
	)
end)
