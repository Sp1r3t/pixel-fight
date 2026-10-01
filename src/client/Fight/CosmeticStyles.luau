--!strict
--[[
	Визуальные стили косметики (Characters[..].cosmetics): ауры, шлейфы, фоны роликов суперов.
	Есть только у Deluxe-персонажей — это единственное их отличие от бесплатных (боевой код
	косметику не читает). Стандартные персонажи получают фон ролика из цвета вспышки супера.
]]

export type AuraStyle = {
	colors: { Color3 },
	rate: number, -- частиц в секунду
	rise: number, -- вертикальная скорость частиц (студ/с), отрицательная — падают
	spread: number, -- разброс по горизонтали вокруг бойца (студы)
	size: number,
	life: number, -- секунды
}

export type TrailStyle = {
	colors: { Color3 },
	size: number,
}

export type BackdropStyle = {
	top: Color3,
	bottom: Color3,
	sparkle: Color3?, -- «звёзды»/частицы на фоне
}

local AURAS: { [string]: AuraStyle } = {
	EmberAura = {
		colors = { Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 110, 40) },
		rate = 14,
		rise = 5,
		spread = 1.4,
		size = 0.28,
		life = 0.7,
	},
	FrostMist = {
		colors = { Color3.fromRGB(230, 250, 255), Color3.fromRGB(140, 215, 255) },
		rate = 10,
		rise = 1.2,
		spread = 1.8,
		size = 0.4,
		life = 1,
	},
	StaticCrackle = {
		colors = { Color3.fromRGB(250, 255, 140), Color3.fromRGB(120, 130, 255) },
		rate = 12,
		rise = 0,
		spread = 1.6,
		size = 0.22,
		life = 0.25,
	},
	Hologlitch = {
		colors = { Color3.fromRGB(0, 245, 160), Color3.fromRGB(255, 60, 172) },
		rate = 12,
		rise = 0.5,
		spread = 1.5,
		size = 0.35,
		life = 0.3,
	},
	SoulWisps = {
		colors = { Color3.fromRGB(124, 255, 203), Color3.fromRGB(210, 255, 240) },
		rate = 8,
		rise = 2.5,
		spread = 1.6,
		size = 0.3,
		life = 1.1,
	},
	Starfield = {
		colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(199, 125, 255) },
		rate = 9,
		rise = 0.8,
		spread = 1.8,
		size = 0.22,
		life = 0.9,
	},
}

local TRAILS: { [string]: TrailStyle } = {
	FlameTrail = { colors = { Color3.fromRGB(255, 180, 60), Color3.fromRGB(255, 90, 30) }, size = 0.5 },
	SnowTrail = { colors = { Color3.fromRGB(240, 252, 255), Color3.fromRGB(150, 220, 255) }, size = 0.45 },
	LightningTrail = { colors = { Color3.fromRGB(250, 255, 140), Color3.fromRGB(110, 120, 255) }, size = 0.4 },
	PixelTrail = { colors = { Color3.fromRGB(0, 245, 160), Color3.fromRGB(255, 60, 172) }, size = 0.5 },
	SpectralTrail = { colors = { Color3.fromRGB(124, 255, 203), Color3.fromRGB(60, 90, 80) }, size = 0.5 },
	StardustTrail = { colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(199, 125, 255) }, size = 0.35 },
}

local BACKDROPS: { [string]: BackdropStyle } = {
	PhoenixSky = {
		top = Color3.fromRGB(120, 20, 10),
		bottom = Color3.fromRGB(255, 170, 60),
		sparkle = Color3.fromRGB(255, 230, 120),
	},
	GlacierCavern = {
		top = Color3.fromRGB(10, 40, 80),
		bottom = Color3.fromRGB(150, 220, 255),
		sparkle = Color3.fromRGB(255, 255, 255),
	},
	StormClouds = {
		top = Color3.fromRGB(20, 20, 50),
		bottom = Color3.fromRGB(90, 95, 200),
		sparkle = Color3.fromRGB(240, 250, 120),
	},
	Cyberspace = {
		top = Color3.fromRGB(10, 10, 30),
		bottom = Color3.fromRGB(0, 120, 90),
		sparkle = Color3.fromRGB(255, 60, 172),
	},
	SpiritRealm = {
		top = Color3.fromRGB(10, 25, 25),
		bottom = Color3.fromRGB(40, 140, 110),
		sparkle = Color3.fromRGB(180, 255, 230),
	},
	DeepSpace = {
		top = Color3.fromRGB(5, 5, 20),
		bottom = Color3.fromRGB(60, 30, 110),
		sparkle = Color3.fromRGB(255, 255, 255),
	},
}

-- Every super has its own stage treatment. Deluxe backdrops still take
-- precedence, while the standard roster no longer shares one flat colour wash.
local CINEMATIC_BACKDROPS: { [string]: BackdropStyle } = {
	RushCombo = {
		top = Color3.fromRGB(12, 24, 54),
		bottom = Color3.fromRGB(202, 134, 34),
		sparkle = Color3.fromRGB(255, 230, 150),
	},
	KickFlurry = {
		top = Color3.fromRGB(65, 8, 45),
		bottom = Color3.fromRGB(238, 73, 126),
		sparkle = Color3.fromRGB(255, 220, 90),
	},
	SkyPiledriver = {
		top = Color3.fromRGB(35, 23, 18),
		bottom = Color3.fromRGB(125, 74, 35),
		sparkle = Color3.fromRGB(255, 178, 72),
	},
	DiscRain = {
		top = Color3.fromRGB(4, 45, 58),
		bottom = Color3.fromRGB(30, 177, 175),
		sparkle = Color3.fromRGB(255, 166, 54),
	},
	ShadowCuts = {
		top = Color3.fromRGB(7, 4, 19),
		bottom = Color3.fromRGB(62, 26, 92),
		sparkle = Color3.fromRGB(181, 121, 255),
	},
	BoxingRush = {
		top = Color3.fromRGB(45, 5, 5),
		bottom = Color3.fromRGB(158, 34, 27),
		sparkle = Color3.fromRGB(255, 218, 72),
	},
	AerialRave = {
		top = Color3.fromRGB(15, 47, 36),
		bottom = Color3.fromRGB(52, 150, 93),
		sparkle = Color3.fromRGB(210, 255, 150),
	},
	LotusPalms = {
		top = Color3.fromRGB(58, 26, 5),
		bottom = Color3.fromRGB(183, 105, 34),
		sparkle = Color3.fromRGB(255, 221, 146),
	},
	LancePierce = {
		top = Color3.fromRGB(15, 25, 38),
		bottom = Color3.fromRGB(81, 106, 132),
		sparkle = Color3.fromRGB(235, 220, 135),
	},
	RocketLoop = {
		top = Color3.fromRGB(3, 30, 48),
		bottom = Color3.fromRGB(0, 168, 210),
		sparkle = Color3.fromRGB(255, 235, 84),
	},
	PhoenixAscension = BACKDROPS.PhoenixSky,
	GlacierPrison = BACKDROPS.GlacierCavern,
	LightningIai = BACKDROPS.StormClouds,
	DroneSwarm = BACKDROPS.Cyberspace,
	ReaperJudgement = BACKDROPS.SpiritRealm,
	StarCollapse = BACKDROPS.DeepSpace,
}

local CosmeticStyles = {}

function CosmeticStyles.aura(id: string?): AuraStyle?
	return if id then AURAS[id] else nil
end

function CosmeticStyles.trail(id: string?): TrailStyle?
	return if id then TRAILS[id] else nil
end

-- Фон ролика супера: особый у Deluxe, иначе — затемнённый цвет вспышки супера.
function CosmeticStyles.backdrop(id: string?, flashHex: string, cinematicStyle: string?): BackdropStyle
	local special = if id then BACKDROPS[id] else nil
	if special then
		return special
	end
	local cinematic = if cinematicStyle then CINEMATIC_BACKDROPS[cinematicStyle] else nil
	if cinematic then
		return cinematic
	end
	local flash = Color3.fromHex(flashHex)
	return {
		top = flash:Lerp(Color3.new(0, 0, 0), 0.85),
		bottom = flash:Lerp(Color3.new(0, 0, 0), 0.45),
		sparkle = nil,
	}
end

return CosmeticStyles
