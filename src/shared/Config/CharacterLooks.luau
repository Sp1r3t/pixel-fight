--!strict
--[[
	Облик бойцов — только данные для процедурной отрисовки (client/Sprites/Rig).

	Цвет задаётся либо слотом палитры персонажа ("primary" | "secondary" | "accent"), либо
	своим "#RRGGBB" (кожа, волосы, металл). Благодаря слотам боссы с другой палитрой
	(Config/Bosses) автоматически получают перекрашенный костюм.

	Части облика:
	  • build — телосложение: Slim / Normal / Heavy / Small;
	  • hair  — причёска: Short, Spiky, Ponytail, Bald, Bob, Long, Topknot, Mohawk, None;
	  • face  — глаза: Normal, Narrow, Glow (светятся цветом glow), Visor (светящийся визор), Skull (маска-череп);
	  • head  — повязка, очки, капюшон, шлем с плюмажем, корона, наушники;
	  • top / sleeves / gloves / pants / boots — одежда (Jacket, Gi, Tank, Top, Robe, Armor, Hoodie, Cloak, Bare);
	  • extras — шарф, плащ, пояс-кушак, чётки, наплечники, рюкзак, дрон, хвосты повязки;
	  • weapon — оружие в передней руке: Spear, Katana, Scythe, Fans, Staff, Disc;
	  • element — цвет магии (свечение рук, аура, шлейфы ударов).
]]

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Build = "Slim" | "Normal" | "Heavy" | "Small"

export type Look = {
	build: Build,
	skin: string,
	hair: { style: string, color: string },
	face: { eyes: string, glow: string?, beard: string?, mask: string? },
	head: {
		band: string?,
		bandTails: boolean?,
		goggles: string?,
		hood: string?,
		helmet: string?,
		plume: string?,
		crown: string?,
		headphones: string?,
	},
	top: { style: string, color: string, trim: string? },
	sleeves: string, -- "Full" | "Short" | "None"
	gloves: string?,
	bigGloves: boolean?,
	pants: { style: string, color: string, trim: string? }, -- "Pants" | "Shorts" | "Robe" | "Wide"
	boots: string,
	belt: string?,
	extras: {
		scarf: string?,
		cape: string?,
		sash: string?,
		beads: string?,
		shoulderPads: string?,
		backpack: string?,
		drone: string?,
		stars: string?, -- искры-звёзды на одежде
		jets: string?, -- реактивные кеды
	},
	weapon: { kind: string, color: string, accent: string }?,
	element: string,
}

local SKIN = {
	light = "#F1C27D",
	fair = "#E8C8A8",
	pale = "#EAD9CC",
	tan = "#E0AC69",
	medium = "#C68642",
	brown = "#8D5524",
	olive = "#D9A066",
}

local Looks: { [string]: Look } = {
	rook = {
		build = "Normal",
		skin = SKIN.tan,
		hair = { style = "Short", color = "#3B2A1A" },
		face = { eyes = "Normal" },
		head = { band = "accent", bandTails = true },
		top = { style = "Jacket", color = "primary", trim = "secondary" },
		sleeves = "Full",
		gloves = "secondary",
		pants = { style = "Pants", color = "secondary" },
		boots = "#2B2B2B",
		belt = "accent",
		extras = {},
		element = "accent",
	},
	mira = {
		build = "Slim",
		skin = SKIN.light,
		hair = { style = "Ponytail", color = "#4A1C2E" },
		face = { eyes = "Narrow" },
		head = { band = "accent" },
		top = { style = "Top", color = "primary", trim = "accent" },
		sleeves = "None",
		gloves = "accent",
		pants = { style = "Shorts", color = "secondary", trim = "primary" },
		boots = "accent",
		extras = {},
		element = "accent",
	},
	brakk = {
		build = "Heavy",
		skin = SKIN.medium,
		hair = { style = "Bald", color = "#5A3A1A" },
		face = { eyes = "Narrow", beard = "#5A3A1A" },
		head = {},
		top = { style = "Armor", color = "#495A76", trim = "accent" },
		sleeves = "Full",
		gloves = "secondary",
		pants = { style = "Pants", color = "secondary" },
		boots = "#3A2A1A",
		belt = "accent",
		extras = { shoulderPads = "primary" },
		element = "accent",
	},
	juno = {
		build = "Normal",
		skin = SKIN.brown,
		hair = { style = "Bob", color = "#1B1B1B" },
		face = { eyes = "Normal" },
		head = { goggles = "accent" },
		top = { style = "Jacket", color = "primary", trim = "secondary" },
		sleeves = "Full",
		gloves = "secondary",
		pants = { style = "Pants", color = "primary", trim = "secondary" },
		boots = "secondary",
		extras = {},
		weapon = { kind = "Disc", color = "accent", accent = "secondary" },
		element = "accent",
	},
	sable = {
		build = "Slim",
		skin = SKIN.fair,
		hair = { style = "None", color = "#111111" },
		face = { eyes = "Glow", glow = "accent", mask = "secondary" },
		head = { hood = "primary" },
		top = { style = "Gi", color = "primary", trim = "secondary" },
		sleeves = "Full",
		gloves = "secondary",
		pants = { style = "Pants", color = "secondary" },
		boots = "secondary",
		belt = "accent",
		extras = { scarf = "accent" },
		weapon = { kind = "DualKnives", color = "secondary", accent = "accent" },
		element = "accent",
	},
	dax = {
		build = "Heavy",
		skin = SKIN.tan,
		hair = { style = "Short", color = "#1B1B1B" },
		face = { eyes = "Narrow" },
		head = {},
		top = { style = "Tank", color = "secondary" },
		sleeves = "None",
		gloves = "primary",
		bigGloves = true,
		pants = { style = "Shorts", color = "primary", trim = "accent" },
		boots = "secondary",
		belt = "accent",
		extras = {},
		element = "accent",
	},
	wren = {
		build = "Slim",
		skin = SKIN.light,
		hair = { style = "Mohawk", color = "accent" },
		face = { eyes = "Narrow" },
		head = { band = "secondary" },
		top = { style = "Top", color = "primary", trim = "secondary" },
		sleeves = "None",
		gloves = "accent",
		pants = { style = "Pants", color = "secondary" },
		boots = "accent",
		extras = { cape = "primary" },
		element = "secondary",
	},
	sorren = {
		build = "Normal",
		skin = SKIN.medium,
		hair = { style = "Bald", color = "#3A2A1A" },
		face = { eyes = "Narrow" },
		head = {},
		top = { style = "Robe", color = "primary", trim = "secondary" },
		sleeves = "Full",
		pants = { style = "Robe", color = "primary" },
		boots = "accent",
		extras = { beads = "secondary", sash = "secondary" },
		element = "accent",
	},
	pike = {
		build = "Normal",
		skin = SKIN.tan,
		hair = { style = "None", color = "#3B2A1A" },
		face = { eyes = "Normal" },
		head = { helmet = "primary", plume = "secondary" },
		top = { style = "Armor", color = "primary", trim = "accent" },
		sleeves = "Full",
		gloves = "primary",
		pants = { style = "Pants", color = "secondary" },
		boots = "primary",
		extras = { cape = "secondary" },
		weapon = { kind = "Spear", color = "#8B5A2B", accent = "accent" },
		element = "accent",
	},
	zip = {
		build = "Small",
		skin = SKIN.light,
		hair = { style = "Spiky", color = "accent" },
		face = { eyes = "Normal" },
		head = { goggles = "secondary" },
		top = { style = "Hoodie", color = "primary", trim = "secondary" },
		sleeves = "Full",
		gloves = "secondary",
		pants = { style = "Shorts", color = "secondary" },
		boots = "accent",
		extras = { backpack = "secondary", jets = "accent" },
		element = "accent",
	},
	ashka = {
		build = "Slim",
		skin = SKIN.olive,
		hair = { style = "Long", color = "secondary" },
		face = { eyes = "Narrow" },
		head = { band = "accent" },
		top = { style = "Top", color = "primary", trim = "accent" },
		sleeves = "None",
		pants = { style = "Wide", color = "secondary", trim = "accent" },
		boots = "accent",
		extras = { sash = "accent" },
		weapon = { kind = "Fans", color = "accent", accent = "primary" },
		element = "primary",
	},
	glacia = {
		build = "Slim",
		skin = SKIN.pale,
		hair = { style = "Long", color = "secondary" },
		face = { eyes = "Normal" },
		head = { crown = "primary" },
		top = { style = "Robe", color = "primary", trim = "secondary" },
		sleeves = "Full",
		gloves = "secondary",
		pants = { style = "Robe", color = "accent" },
		boots = "accent",
		extras = { cape = "secondary" },
		weapon = { kind = "Staff", color = "accent", accent = "primary" },
		element = "primary",
	},
	tempest = {
		build = "Normal",
		skin = SKIN.tan,
		hair = { style = "Topknot", color = "secondary" },
		face = { eyes = "Narrow" },
		head = {},
		top = { style = "Gi", color = "primary", trim = "accent" },
		sleeves = "Full",
		pants = { style = "Wide", color = "secondary" },
		boots = "secondary",
		belt = "accent",
		extras = { sash = "accent" },
		weapon = { kind = "Katana", color = "#D5DBDB", accent = "accent" },
		element = "accent",
	},
	byte = {
		build = "Slim",
		skin = SKIN.light,
		hair = { style = "None", color = "#1B1B1B" },
		face = { eyes = "Visor", glow = "primary" },
		head = { hood = "secondary", headphones = "accent" },
		top = { style = "Hoodie", color = "secondary", trim = "primary" },
		sleeves = "Full",
		gloves = "primary",
		pants = { style = "Pants", color = "secondary", trim = "primary" },
		boots = "accent",
		extras = { drone = "primary" },
		element = "primary",
	},
	morrow = {
		build = "Normal",
		skin = SKIN.pale,
		hair = { style = "None", color = "#111111" },
		face = { eyes = "Skull", glow = "accent" },
		head = { hood = "primary" },
		top = { style = "Cloak", color = "primary", trim = "secondary" },
		sleeves = "Full",
		gloves = "secondary",
		pants = { style = "Robe", color = "primary" },
		boots = "#1A1A1A",
		extras = { cape = "primary" },
		weapon = { kind = "Scythe", color = "secondary", accent = "accent" },
		element = "accent",
	},
	astra = {
		build = "Slim",
		skin = SKIN.fair,
		hair = { style = "Long", color = "secondary" },
		face = { eyes = "Glow", glow = "accent" },
		head = { crown = "accent" },
		top = { style = "Robe", color = "primary", trim = "accent" },
		sleeves = "Full",
		pants = { style = "Robe", color = "primary" },
		boots = "secondary",
		extras = { cape = "primary", stars = "accent" },
		element = "accent",
	},
}

-- Облик по умолчанию (для персонажей без записи).
local DEFAULT: Look = Looks.rook

local CharacterLooks = {}

CharacterLooks.LOOKS = deepFreeze(Looks)
CharacterLooks.SKIN = table.freeze(SKIN)

local function copyLook(source: Look): Look
	local result = table.clone(source) :: any
	result.hair = table.clone(source.hair)
	result.face = table.clone(source.face)
	result.head = table.clone(source.head)
	result.top = table.clone(source.top)
	result.pants = table.clone(source.pants)
	result.extras = table.clone(source.extras)
	result.weapon = if source.weapon then table.clone(source.weapon) else nil
	return result :: Look
end

-- Boss silhouettes are assembled from the same articulated renderer, but replace
-- anatomy, face, costume and weapon as a set. Their moves stay balanced while the
-- opponent reads as a creature/boss rather than a recoloured roster fighter.
local function bossLook(base: Look, style: string): Look
	local look = copyLook(base)
	if string.find(style, "_shadow") then
		look.face = table.clone(look.face)
		look.face.eyes = "Glow"
		look.face.glow = "accent"
		look.face.mask = "secondary"
		look.head = { hood = "primary" }
		look.extras = table.clone(look.extras)
		look.extras.scarf = "accent"
		if look.weapon then
			look.weapon = { kind = look.weapon.kind, color = "secondary", accent = "accent" }
		end
	elseif string.find(style, "_legend") then
		look.face = table.clone(look.face)
		look.face.eyes = "Glow"
		look.face.glow = "accent"
		look.head = table.clone(look.head)
		look.head.crown = "accent"
		look.extras = table.clone(look.extras)
		look.extras.stars = "accent"
		look.extras.cape = look.extras.cape or "primary"
		if look.weapon then
			look.weapon = { kind = look.weapon.kind, color = "accent", accent = "secondary" }
		end
	elseif string.find(style, "brute") or string.find(style, "titan") then
		look.build = "Heavy"
		look.hair = { style = "Bald", color = "#25170F" }
		look.face = { eyes = "Narrow", beard = "#25170F" }
		look.top = { style = "Armor", color = "primary", trim = "accent" }
		look.sleeves = "None"
		look.bigGloves = true
		look.extras = { shoulderPads = "accent" }
	elseif string.find(style, "alien") then
		look.build = "Slim"
		look.skin = "#8BC7A3"
		look.hair = { style = "None", color = "#10151B" }
		look.face = { eyes = "Glow", glow = "accent" }
		look.head = { helmet = "secondary" }
		look.top = { style = "Armor", color = "primary", trim = "accent" }
		look.sleeves = "Full"
		look.extras = { drone = "accent" }
	elseif string.find(style, "kraken") then
		look.build = "Heavy"
		look.skin = "#70507F"
		look.hair = { style = "None", color = "#18101F" }
		look.face = { eyes = "Glow", glow = "accent", mask = "secondary" }
		look.head = { crown = "accent" }
		look.top = { style = "Cloak", color = "primary", trim = "accent" }
		look.pants = { style = "Robe", color = "secondary", trim = "accent" }
		look.extras = { cape = "primary", beads = "accent" }
		look.weapon = { kind = "Scythe", color = "secondary", accent = "accent" }
	elseif string.find(style, "tree") then
		look.build = "Heavy"
		look.skin = "#75502D"
		look.hair = { style = "Spiky", color = "#386641" }
		look.face = { eyes = "Glow", glow = "accent" }
		look.head = { crown = "accent" }
		look.top = { style = "Armor", color = "#5B3A22", trim = "accent" }
		look.sleeves = "Full"
		look.pants = { style = "Wide", color = "#3C5A35" }
		look.extras = { shoulderPads = "#386641", beads = "accent" }
		look.weapon = { kind = "Staff", color = "#4B2E18", accent = "accent" }
	elseif string.find(style, "sahur") then
		look.build = "Heavy"
		look.skin = "#8B5A2B"
		look.hair = { style = "None", color = "#24160C" }
		look.face = { eyes = "Glow", glow = "#FF2D2D" }
		look.head = { crown = "accent" }
		look.top = { style = "Bare", color = "#8B5A2B", trim = "accent" }
		look.sleeves = "None"
		look.pants = { style = "Wide", color = "secondary", trim = "accent" }
		look.bigGloves = true
		look.extras = { sash = "accent" }
		look.weapon = { kind = "Staff", color = "#5A3318", accent = "accent" }
	elseif string.find(style, "robot") or string.find(style, "cyber") then
		look.build = "Heavy"
		look.skin = "#98A6B3"
		look.hair = { style = "None", color = "#111827" }
		look.face = { eyes = "Visor", glow = "accent", mask = "secondary" }
		look.head = { helmet = "primary", headphones = "accent" }
		look.top = { style = "Armor", color = "secondary", trim = "accent" }
		look.sleeves = "Full"
		look.extras = { shoulderPads = "primary", drone = "accent", jets = "accent" }
	elseif string.find(style, "golem") or string.find(style, "mutant") or string.find(style, "beast") then
		look.build = "Heavy"
		look.skin = if string.find(style, "golem") then "#A8C2CC" else "#6F8F62"
		look.hair = { style = "Mohawk", color = "accent" }
		look.face = { eyes = "Glow", glow = "accent", mask = "secondary" }
		look.head = { helmet = "primary" }
		look.top = { style = "Bare", color = look.skin, trim = "accent" }
		look.sleeves = "None"
		look.bigGloves = true
		look.extras = { shoulderPads = "accent" }
	elseif string.find(style, "warlock") or string.find(style, "oracle") then
		look.build = "Slim"
		look.hair = { style = "Long", color = "secondary" }
		look.face = { eyes = "Glow", glow = "accent" }
		look.head = { crown = "accent" }
		look.top = { style = "Robe", color = "primary", trim = "accent" }
		look.pants = { style = "Robe", color = "secondary", trim = "accent" }
		look.extras = { cape = "primary", stars = "accent" }
		look.weapon = { kind = "Staff", color = "secondary", accent = "accent" }
	elseif string.find(style, "champion") then
		look.build = "Heavy"
		look.hair = { style = "Mohawk", color = "accent" }
		look.face = { eyes = "Narrow", beard = "secondary" }
		look.head = { crown = "accent" }
		look.top = { style = "Armor", color = "primary", trim = "accent" }
		look.sleeves = "None"
		look.bigGloves = true
		look.extras = { shoulderPads = "secondary", cape = "primary" }
	elseif string.find(style, "monk") then
		look.build = "Heavy"
		look.hair = { style = "Bald", color = "secondary" }
		look.face = { eyes = "Glow", glow = "accent", beard = "secondary" }
		look.head = {}
		look.top = { style = "Robe", color = "primary", trim = "accent" }
		look.pants = { style = "Wide", color = "secondary" }
		look.extras = { beads = "accent", sash = "accent" }
	elseif string.find(style, "demon") or string.find(style, "wraith") or string.find(style, "null") then
		look.build = if string.find(style, "null") then "Heavy" else "Slim"
		look.skin = "#2A2135"
		look.hair = { style = "None", color = "#08070B" }
		look.face = { eyes = "Glow", glow = "accent", mask = "secondary" }
		look.head = { hood = "primary", crown = if string.find(style, "null") then "accent" else nil }
		look.top = { style = "Cloak", color = "primary", trim = "accent" }
		look.pants = { style = "Robe", color = "secondary" }
		look.extras = { cape = "primary", stars = "accent" }
	end
	return look
end

function CharacterLooks.get(characterId: string, visualStyle: string?): Look
	local base = CharacterLooks.LOOKS[characterId] or DEFAULT
	return if visualStyle then bossLook(base, visualStyle) else base
end

return CharacterLooks
