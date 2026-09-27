--!strict
--[[
	Арены (карты) — только внешний вид: небо, силуэты, погода и анимированные детали фона.
	На бой не влияют (геометрию боя задаёт Combat/Stage).

	10 карт: 7 бесплатных и 3 премиальные (premium = true) — «Логово дракона», «Неон-Сити»,
	«Космо-арена». Премиальную карту можно выбрать в голосовании, только если она куплена
	(Game Pass или монеты, см. Config/Monetization); если она победила — на ней играют все.
	Боссы тоже дерутся на своих картах (Config/Bosses) — так игроки видят премиальные карты в деле.

	Отрисовка — клиентский модуль Fight/ArenaArt (процедурно, «слегка пиксельно», детерминированно по id).
]]

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

-- Силуэты дальнего и среднего плана.
export type Silhouette =
	"Mountains"
	| "City"
	| "Pillars"
	| "Spikes"
	| "Waves"
	| "Trees"
	| "Volcano"
	| "Skyline"
	| "Rocks"

-- Частицы погоды на заднем плане.
export type Weather = "None" | "Petals" | "Rain" | "Snow" | "Embers" | "Fireflies" | "Ash" | "Dust"

-- Детали неба и фона (часть анимирована).
export type Feature =
	"Sun"
	| "Moon"
	| "Stars"
	| "Clouds"
	| "Lanterns"
	| "Birds"
	| "Lightning"
	| "Aurora"
	| "Volcano"
	| "Dragon"
	| "NeonSigns"
	| "FlyingCars"
	| "Planets"
	| "Meteors"
	| "Nebula"
	| "Ship"
	| "Lighthouse"

export type ArenaTheme = {
	id: string,
	order: number,
	name: string,
	description: string,
	premium: boolean,
	skyTop: string,
	skyBottom: string,
	far: string, -- дальние силуэты
	near: string, -- ближние силуэты
	floor: string,
	floorLine: string,
	accent: string, -- солнце, кромки платформ, акценты
	glow: string, -- второй яркий цвет (неон, лава, туманность)
	silhouette: Silhouette,
	nearSilhouette: Silhouette,
	weather: Weather,
	features: { Feature },
}

local Arenas: { ArenaTheme } = {
	{
		id = "dojo",
		order = 1,
		name = "Додзё на закате",
		description = "Старое додзё в горах: закат, фонарики и летящие лепестки сакуры.",
		premium = false,
		skyTop = "#2B1B3D",
		skyBottom = "#E07A5F",
		far = "#3D2C4E",
		near = "#1E1428",
		floor = "#6B4A33",
		floorLine = "#8C6444",
		accent = "#FFC845",
		glow = "#FF8FB1",
		silhouette = "Mountains",
		nearSilhouette = "Pillars",
		weather = "Petals",
		features = { "Sun", "Clouds", "Lanterns", "Birds" },
	},
	{
		id = "rooftop",
		order = 2,
		name = "Ночная крыша",
		description = "Крыша небоскрёба в грозу: дождь, молнии и огни ночного города.",
		premium = false,
		skyTop = "#0B0B23",
		skyBottom = "#3A1C71",
		far = "#1C1446",
		near = "#120C2C",
		floor = "#2E2E3A",
		floorLine = "#5A5A7A",
		accent = "#00F5A0",
		glow = "#FFE066",
		silhouette = "City",
		nearSilhouette = "City",
		weather = "Rain",
		features = { "Moon", "Clouds", "Lightning" },
	},
	{
		id = "peaks",
		order = 3,
		name = "Снежные пики",
		description = "Ледяные вершины под северным сиянием. Идёт снег.",
		premium = false,
		skyTop = "#081630",
		skyBottom = "#35608C",
		far = "#4F7CA8",
		near = "#2E4A6B",
		floor = "#8A8F98",
		floorLine = "#B8BEC7",
		accent = "#FFFFFF",
		glow = "#7CFFCB",
		silhouette = "Mountains",
		nearSilhouette = "Mountains",
		weather = "Snow",
		features = { "Aurora", "Stars", "Clouds" },
	},
	{
		id = "harbor",
		order = 4,
		name = "Закатная гавань",
		description = "Причал у тёплого моря: чайки, облака и огромное солнце над волнами.",
		premium = false,
		skyTop = "#FF7E5F",
		skyBottom = "#FEB47B",
		far = "#B85C5C",
		near = "#6B2F3A",
		floor = "#5C4033",
		floorLine = "#7A5A45",
		accent = "#FFF1A8",
		glow = "#2EC4B6",
		silhouette = "Waves",
		nearSilhouette = "Pillars",
		weather = "None",
		features = { "Sun", "Clouds", "Birds", "Lighthouse" },
	},
	{
		id = "caldera",
		order = 5,
		name = "Огненная кальдера",
		description = "Арена в кратере вулкана. Снизу поднимаются искры, вдали дымит вулкан.",
		premium = false,
		skyTop = "#1A0500",
		skyBottom = "#8C1C00",
		far = "#4A0E00",
		near = "#240600",
		floor = "#3B2A26",
		floorLine = "#FF6B35",
		accent = "#FFE66D",
		glow = "#FF6B35",
		silhouette = "Spikes",
		nearSilhouette = "Spikes",
		weather = "Embers",
		features = { "Volcano" },
	},
	{
		id = "void",
		order = 6,
		name = "Звёздная пустота",
		description = "Парящие скалы среди звёзд. Тишина — и мерцание далёких галактик.",
		premium = false,
		skyTop = "#05030B",
		skyBottom = "#1A1446",
		far = "#2A1F5C",
		near = "#120C2C",
		floor = "#231A42",
		floorLine = "#C77DFF",
		accent = "#F7F1E3",
		glow = "#C77DFF",
		silhouette = "Rocks",
		nearSilhouette = "Spikes",
		weather = "Dust",
		features = { "Stars", "Nebula" },
	},
	{
		id = "forest",
		order = 7,
		name = "Лес светлячков",
		description = "Ночная поляна в древнем лесу. Светлячки кружат под полной луной.",
		premium = false,
		skyTop = "#0A1A2F",
		skyBottom = "#2C5364",
		far = "#15324A",
		near = "#0B1D16",
		floor = "#2F3E23",
		floorLine = "#4F6B35",
		accent = "#FFF4C2",
		glow = "#C6FF6B",
		silhouette = "Trees",
		nearSilhouette = "Trees",
		weather = "Fireflies",
		features = { "Moon", "Stars" },
	},
	{
		id = "dragon",
		order = 8,
		name = "Логово дракона",
		description = "Пещера у жерла вулкана. Над ареной кружит огромный дракон и дышит огнём, "
			.. "вдали извергается вулкан.",
		premium = true,
		skyTop = "#1C0306",
		skyBottom = "#A32100",
		far = "#3A0A0A",
		near = "#1A0404",
		floor = "#2B1B17",
		floorLine = "#FF4E1A",
		accent = "#FFD23F",
		glow = "#FF4E1A",
		silhouette = "Volcano",
		nearSilhouette = "Spikes",
		weather = "Embers",
		features = { "Volcano", "Dragon", "Lightning" },
	},
	{
		id = "neon",
		order = 9,
		name = "Неон-Сити",
		description = "Киберпанк-мегаполис: мигающие неоновые вывески, летающие машины и дождь.",
		premium = true,
		skyTop = "#070B1F",
		skyBottom = "#5B1A6E",
		far = "#1A1240",
		near = "#0C0A22",
		floor = "#1B1B2E",
		floorLine = "#FF3CAC",
		accent = "#00E5FF",
		glow = "#FF3CAC",
		silhouette = "Skyline",
		nearSilhouette = "Skyline",
		weather = "Rain",
		features = { "Moon", "NeonSigns", "FlyingCars" },
	},
	{
		id = "cosmos",
		order = 10,
		name = "Космо-арена",
		description = "Арена на астероиде: планета с кольцами, туманности, метеоритный дождь "
			.. "и пролетающий звездолёт.",
		premium = true,
		skyTop = "#02010A",
		skyBottom = "#1B0F4A",
		far = "#2D1E6B",
		near = "#110B30",
		floor = "#2A2340",
		floorLine = "#6BE4FF",
		accent = "#FFE9A8",
		glow = "#6BE4FF",
		silhouette = "Rocks",
		nearSilhouette = "Rocks",
		weather = "Dust",
		features = { "Stars", "Nebula", "Planets", "Meteors", "Ship" },
	},
}

local byId: { [string]: ArenaTheme } = {}
local free: { string } = {}
local premium: { string } = {}
for _, arena in Arenas do
	byId[arena.id] = arena
	table.insert(if arena.premium then premium else free, arena.id)
end

return deepFreeze({
	list = Arenas,
	byId = byId,
	free = free, -- id бесплатных карт
	premium = premium, -- id премиальных карт
	default = "dojo",
})
