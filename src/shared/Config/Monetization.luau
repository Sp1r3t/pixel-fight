--!strict
--[[
	Монетизация — только данные. ID товаров создаются на сайте Roblox (Creator Hub → Monetization)
	и вписываются сюда. 0 — товар не настроен: кнопка покупки за Robux в игре неактивна.

	Честность (no pay-to-win): платные бойцы по силе равны бесплатным (бюджет характеристик),
	отличаются только внешним видом (Deluxe-косметика). Любого платного бойца можно также
	открыть за монеты, заработанные в игре. Кристаллы (за Robux) тратятся только на косметику
	(Config/Cosmetics): облики, эффекты ударов, финишеры, эмоции.
]]

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type ProductKind = "SkipBoss" | "Coins" | "Crystals" | "StarterPack"

export type Product = {
	key: string,
	id: number, -- Developer Product ID (0 — не настроен)
	kind: ProductKind,
	name: string,
	amount: number?, -- для Coins и Crystals
	priceHint: number, -- цена для подсказки в интерфейсе (настоящую задаёт сайт)
}

local Monetization = {
	-- Game Pass для каждого платного бойца.
	gamePasses = {
		ashka = 0,
		glacia = 0,
		tempest = 0,
		byte = 0,
		morrow = 0,
		astra = 0,
	} :: { [string]: number },
	gamePassPriceHint = 149,

	-- Альтернатива без доната: открыть платного бойца за монеты.
	characterCoinPrice = 6000,

	-- Премиальные карты (Config/Arenas, premium = true): Game Pass за Robux или монеты.
	-- Купленную карту можно выбирать в голосовании перед боем — если она победит, на ней играют все.
	arenaPasses = {
		dragon = 0,
		neon = 0,
		cosmos = 0,
	} :: { [string]: number },
	arenaPassPriceHint = 99,
	arenaCoinPrice = 4000,

	products = {
		{ key = "SkipBoss", id = 0, kind = "SkipBoss", name = "Пропустить босса", priceHint = 49 },
		{ key = "Coins1000", id = 0, kind = "Coins", name = "1000 монет", amount = 1000, priceHint = 99 },
		{ key = "Coins3000", id = 0, kind = "Coins", name = "3000 монет", amount = 3000, priceHint = 249 },
		{
			key = "Crystals100",
			id = 0,
			kind = "Crystals",
			name = "100 кристаллов",
			amount = 100,
			priceHint = 49,
		},
		{
			key = "Crystals300",
			id = 0,
			kind = "Crystals",
			name = "300 кристаллов",
			amount = 300,
			priceHint = 129,
		},
		{
			key = "Crystals800",
			id = 0,
			kind = "Crystals",
			name = "800 кристаллов",
			amount = 800,
			priceHint = 299,
		},
		-- Набор новичка: один раз на профиль (повторная покупка — только кристаллы).
		{ key = "StarterPack", id = 0, kind = "StarterPack", name = "Набор новичка", priceHint = 99 },
	} :: { Product },

	starterPack = {
		coins = 3000,
		crystals = 150,
		emote = "emote_party",
	},

	-- VIP-пропуск: +50% монет за бои и боссов, больше ежедневная награда, «Радуга» и значок 👑.
	-- Сила бойцов не меняется.
	vipPass = 0,
	vipPriceHint = 249,
	vipCoinMultiplier = 1.5,
	vipDailyCrystals = 5,

	-- Ежедневная награда: 7 дней подряд, пропуск дня — серия сначала.
	dailyCoins = { 100, 150, 200, 250, 300, 400, 500 },
	dailyCrystalsDay7 = 20,
}

return deepFreeze(Monetization)
