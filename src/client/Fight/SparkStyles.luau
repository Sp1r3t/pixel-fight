--!strict
--[[
	Цвета искр при попадании — по косметике персонажа (Characters[..].cosmetics.hitSpark).
	Только внешний вид: на бой не влияет.
]]

export type SparkStyle = {
	primary: Color3,
	secondary: Color3,
	count: number, -- множитель количества частиц
}

local STYLES: { [string]: SparkStyle } = {
	Impact = { primary = Color3.fromRGB(255, 255, 255), secondary = Color3.fromRGB(255, 214, 90), count = 1 },
	Slash = { primary = Color3.fromRGB(235, 250, 255), secondary = Color3.fromRGB(140, 220, 255), count = 1 },
	Energy = { primary = Color3.fromRGB(255, 255, 255), secondary = Color3.fromRGB(120, 255, 220), count = 1 },
	-- Deluxe-косметика платных персонажей: больше частиц и насыщеннее цвета.
	Flame = { primary = Color3.fromRGB(255, 230, 110), secondary = Color3.fromRGB(255, 100, 40), count = 1.5 },
	Ice = { primary = Color3.fromRGB(240, 252, 255), secondary = Color3.fromRGB(120, 210, 255), count = 1.5 },
	Lightning = { primary = Color3.fromRGB(250, 255, 140), secondary = Color3.fromRGB(110, 120, 255), count = 1.5 },
	Glitch = { primary = Color3.fromRGB(0, 245, 160), secondary = Color3.fromRGB(255, 60, 172), count = 1.5 },
	Soul = { primary = Color3.fromRGB(200, 255, 235), secondary = Color3.fromRGB(124, 255, 203), count = 1.5 },
	Star = { primary = Color3.fromRGB(255, 255, 255), secondary = Color3.fromRGB(199, 125, 255), count = 1.5 },
}

local BLOCK_STYLE: SparkStyle = {
	primary = Color3.fromRGB(150, 200, 255),
	secondary = Color3.fromRGB(255, 255, 255),
	count = 0.8,
}

local SparkStyles = {}

function SparkStyles.get(name: string): SparkStyle
	return STYLES[name] or STYLES.Impact
end

function SparkStyles.block(): SparkStyle
	return BLOCK_STYLE
end

return SparkStyles
