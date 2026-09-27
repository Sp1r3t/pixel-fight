--!strict
--[[
	Косметика — только внешний вид, на бой не влияет (no pay-to-win).

	  • Облики (Skin): у каждого бойца «Тень» (тёмная, за монеты) и «Легенда» (своя яркая палитра
	    и искры вокруг в бою, за кристаллы). Облик — другая палитра: процедурный боец (Sprites/Rig)
	    перекрашивается сам.
	  • Эффекты ударов (HitEffect): искры твоих попаданий — звёзды, сердечки, молнии, конфетти…
	  • Финишеры (KoEffect): что происходит, когда ты побеждаешь нокаутом — фейерверк, звездопад…
	  • Эмоции (Emote): смайлик над бойцом по кнопке в бою. Две — бесплатно.

	Валюты: Coins — монеты, заработанные в игре; Crystals — кристаллы (покупаются за Robux, немного
	дают за ежедневную награду); Free — есть у всех; Vip — только с VIP-пропуском.
]]

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type ItemKind = "Skin" | "HitEffect" | "KoEffect" | "Emote"
export type Currency = "Coins" | "Crystals" | "Free" | "Vip"

export type Effect = {
	primary: string,
	secondary: string,
	glyph: string?, -- частицы-символы (♥, ★, ⚡) вместо квадратиков
	confetti: boolean?, -- разноцветные частицы
}

export type Item = {
	id: string,
	kind: ItemKind,
	name: string,
	icon: string, -- эмодзи для интерфейса
	currency: Currency,
	price: number,
	description: string,
	character: string?, -- облик: чей
	palette: Types.Palette?, -- облик: цвета
	legendary: boolean?, -- облик: искры вокруг бойца в бою
	effect: Effect?, -- эффект удара / финишер
	emoji: string?, -- эмоция
}

local SHADOW_PRICE = 1500 -- монет
local LEGEND_PRICE = 150 -- кристаллов

-- Облики: { id бойца, палитра «Тени», название «Легенды», палитра «Легенды» }.
type SkinSet = {
	character: string,
	shadow: Types.Palette,
	legendName: string,
	legend: Types.Palette,
}

local SKIN_SETS: { SkinSet } = {
	{
		character = "rook",
		shadow = { primary = "#1E2A3A", secondary = "#3A3F4A", accent = "#7FDBFF" },
		legendName = "Золотой авангард",
		legend = { primary = "#D4A017", secondary = "#FFF8E1", accent = "#FF6F00" },
	},
	{
		character = "mira",
		shadow = { primary = "#3A1024", secondary = "#121218", accent = "#FF4FA0" },
		legendName = "Сакура",
		legend = { primary = "#FFB7C5", secondary = "#FFFFFF", accent = "#E91E63" },
	},
	{
		character = "brakk",
		shadow = { primary = "#2E1E10", secondary = "#1C1C1C", accent = "#FF7A2E" },
		legendName = "Лава",
		legend = { primary = "#1A1A1A", secondary = "#3E2723", accent = "#FF5722" },
	},
	{
		character = "juno",
		shadow = { primary = "#0E3B38", secondary = "#2A2A2A", accent = "#FF4F1C" },
		legendName = "Космонавт",
		legend = { primary = "#ECEFF1", secondary = "#1565C0", accent = "#FFEB3B" },
	},
	{
		character = "sable",
		shadow = { primary = "#120C1E", secondary = "#050505", accent = "#FF3355" },
		legendName = "Лунная тень",
		legend = { primary = "#B0BEC5", secondary = "#37474F", accent = "#E1BEE7" },
	},
	{
		character = "dax",
		shadow = { primary = "#2B0D0A", secondary = "#3A2E22", accent = "#FF4136" },
		legendName = "Чемпион",
		legend = { primary = "#B71C1C", secondary = "#FFD54F", accent = "#FFFFFF" },
	},
	{
		character = "wren",
		shadow = { primary = "#1D3319", secondary = "#3A3522", accent = "#9BFF6A" },
		legendName = "Феникс",
		legend = { primary = "#FF7043", secondary = "#FFCA28", accent = "#D50000" },
	},
	{
		character = "sorren",
		shadow = { primary = "#3A2508", secondary = "#1E0F05", accent = "#FFB347" },
		legendName = "Нефрит",
		legend = { primary = "#2E7D32", secondary = "#E8F5E9", accent = "#A5D6A7" },
	},
	{
		character = "pike",
		shadow = { primary = "#1C2229", secondary = "#3A0E0B", accent = "#9FB4C7" },
		legendName = "Рыцарь",
		legend = { primary = "#90A4AE", secondary = "#1A237E", accent = "#FFD700" },
	},
	{
		character = "zip",
		shadow = { primary = "#3A3210", secondary = "#0D2A3D", accent = "#00E5FF" },
		legendName = "Неон",
		legend = { primary = "#00E676", secondary = "#D500F9", accent = "#FFFF00" },
	},
	{
		character = "ashka",
		shadow = { primary = "#3A1506", secondary = "#1A0602", accent = "#FF8C1A" },
		legendName = "Солнце",
		legend = { primary = "#FFD600", secondary = "#FF3D00", accent = "#FFFFFF" },
	},
	{
		character = "glacia",
		shadow = { primary = "#0D3345", secondary = "#1C2A33", accent = "#7FDBFF" },
		legendName = "Аврора",
		legend = { primary = "#1DE9B6", secondary = "#7C4DFF", accent = "#E0F7FA" },
	},
	{
		character = "tempest",
		shadow = { primary = "#12133D", secondary = "#07070F", accent = "#FFE14A" },
		legendName = "Гроза",
		legend = { primary = "#263238", secondary = "#FFEB3B", accent = "#40C4FF" },
	},
	{
		character = "byte",
		shadow = { primary = "#003D28", secondary = "#05070D", accent = "#FF3CAC" },
		legendName = "Вирус",
		legend = { primary = "#76FF03", secondary = "#000000", accent = "#FF1744" },
	},
	{
		character = "morrow",
		shadow = { primary = "#0D0D0D", secondary = "#1E2429", accent = "#FF4D6D" },
		legendName = "Призрак",
		legend = { primary = "#ECEFF1", secondary = "#B2EBF2", accent = "#00E5FF" },
	},
	{
		character = "astra",
		shadow = { primary = "#07051A", secondary = "#2A2438", accent = "#FFD166" },
		legendName = "Галактика",
		legend = { primary = "#311B92", secondary = "#F48FB1", accent = "#00E5FF" },
	},
}

local ITEMS: { Item } = {}

for _, set in SKIN_SETS do
	table.insert(ITEMS, {
		id = `{set.character}_shadow`,
		kind = "Skin",
		name = "Тень",
		icon = "🌑",
		currency = "Coins",
		price = SHADOW_PRICE,
		description = "Тёмный облик со светящимися деталями.",
		character = set.character,
		palette = set.shadow,
	})
	table.insert(ITEMS, {
		id = `{set.character}_legend`,
		kind = "Skin",
		name = set.legendName,
		icon = "🌟",
		currency = "Crystals",
		price = LEGEND_PRICE,
		description = "Легендарный облик: свои цвета и искры вокруг бойца в бою.",
		character = set.character,
		palette = set.legend,
		legendary = true,
	})
end

local EFFECTS: { Item } = {
	{
		id = "hit_stars",
		kind = "HitEffect",
		name = "Звёзды",
		icon = "⭐",
		currency = "Coins",
		price = 1000,
		description = "Твои удары рассыпаются золотыми звёздами.",
		effect = { primary = "#FFE14A", secondary = "#FFFFFF", glyph = "★" },
	},
	{
		id = "hit_confetti",
		kind = "HitEffect",
		name = "Конфетти",
		icon = "🎊",
		currency = "Coins",
		price = 1000,
		description = "Каждое попадание — праздник: разноцветное конфетти.",
		effect = { primary = "#FF4F8B", secondary = "#3AA8F0", confetti = true },
	},
	{
		id = "hit_pixels",
		kind = "HitEffect",
		name = "Пиксели",
		icon = "👾",
		currency = "Coins",
		price = 1000,
		description = "Ретро-искры: крупные зелёные и голубые пиксели.",
		effect = { primary = "#39FF14", secondary = "#00BFFF" },
	},
	{
		id = "hit_hearts",
		kind = "HitEffect",
		name = "Сердечки",
		icon = "💖",
		currency = "Crystals",
		price = 80,
		description = "Удары разлетаются сердечками.",
		effect = { primary = "#FF4F8B", secondary = "#FFB3CF", glyph = "♥" },
	},
	{
		id = "hit_lightning",
		kind = "HitEffect",
		name = "Молнии",
		icon = "⚡",
		currency = "Crystals",
		price = 80,
		description = "Искры-молнии с синим электрическим отблеском.",
		effect = { primary = "#FFF176", secondary = "#40C4FF", glyph = "ϟ" },
	},
	{
		id = "hit_rainbow",
		kind = "HitEffect",
		name = "Радуга",
		icon = "🌈",
		currency = "Vip",
		price = 0,
		description = "Радужные искры — только для VIP.",
		effect = { primary = "#FF1744", secondary = "#2979FF", confetti = true },
	},
	{
		id = "ko_starfall",
		kind = "KoEffect",
		name = "Звездопад",
		icon = "🌠",
		currency = "Coins",
		price = 2000,
		description = "После твоего нокаута с неба сыплются звёзды.",
		effect = { primary = "#FFE14A", secondary = "#FFFFFF", glyph = "★" },
	},
	{
		id = "ko_confetti",
		kind = "KoEffect",
		name = "Конфетти-взрыв",
		icon = "🎉",
		currency = "Coins",
		price = 2000,
		description = "Победный взрыв конфетти.",
		effect = { primary = "#FF4F8B", secondary = "#3AA8F0", confetti = true },
	},
	{
		id = "ko_fireworks",
		kind = "KoEffect",
		name = "Фейерверк",
		icon = "🎆",
		currency = "Crystals",
		price = 120,
		description = "Три залпа фейерверка над ареной.",
		effect = { primary = "#FFD166", secondary = "#FF4F8B" },
	},
	{
		id = "ko_thunder",
		kind = "KoEffect",
		name = "Удар молнии",
		icon = "🌩️",
		currency = "Crystals",
		price = 120,
		description = "Молния бьёт в арену, экран вспыхивает.",
		effect = { primary = "#FFF176", secondary = "#40C4FF", glyph = "ϟ" },
	},
}
for _, item in EFFECTS do
	table.insert(ITEMS, item)
end

local EMOTES: { { id: string, emoji: string, name: string, currency: Currency, price: number } } = {
	{ id = "emote_thumbs", emoji = "👍", name = "Класс", currency = "Free", price = 0 },
	{ id = "emote_smile", emoji = "😄", name = "Улыбка", currency = "Free", price = 0 },
	{ id = "emote_cool", emoji = "😎", name = "Круто", currency = "Coins", price = 500 },
	{ id = "emote_fire", emoji = "🔥", name = "Огонь", currency = "Coins", price = 500 },
	{ id = "emote_muscle", emoji = "💪", name = "Сила", currency = "Coins", price = 500 },
	{ id = "emote_wave", emoji = "👋", name = "Привет", currency = "Coins", price = 500 },
	{ id = "emote_crown", emoji = "👑", name = "Король", currency = "Crystals", price = 40 },
	{ id = "emote_party", emoji = "🎉", name = "Праздник", currency = "Crystals", price = 40 },
	{ id = "emote_lol", emoji = "😂", name = "Смешно", currency = "Crystals", price = 40 },
	{ id = "emote_robot", emoji = "🤖", name = "Робот", currency = "Crystals", price = 40 },
}
for _, emote in EMOTES do
	table.insert(ITEMS, {
		id = emote.id,
		kind = "Emote",
		name = emote.name,
		icon = emote.emoji,
		currency = emote.currency,
		price = emote.price,
		description = "Смайлик над твоим бойцом по кнопке в бою.",
		emoji = emote.emoji,
	})
end

local byId: { [string]: Item } = {}
for _, item in ITEMS do
	assert(byId[item.id] == nil, `Повтор косметики {item.id}`)
	byId[item.id] = item
end

-- Облики бойца (без стандартного).
local function skinsOf(characterId: string): { Item }
	local result: { Item } = {}
	for _, item in ITEMS do
		if item.kind == "Skin" and item.character == characterId then
			table.insert(result, item)
		end
	end
	return result
end

local function ofKind(kind: ItemKind): { Item }
	local result: { Item } = {}
	for _, item in ITEMS do
		if item.kind == kind then
			table.insert(result, item)
		end
	end
	return result
end

return deepFreeze({
	items = ITEMS,
	byId = byId,
	skinsOf = skinsOf,
	ofKind = ofKind,
	-- Сколько эмоций можно отправить подряд: не чаще одной в EMOTE_COOLDOWN секунд.
	EMOTE_COOLDOWN = 2.5,
})
