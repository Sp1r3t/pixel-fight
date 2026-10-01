--!strict
--[[
	Обычные удары — одинаковые для всех персонажей. Индивидуальность персонажей — в их
	характеристиках (урон, дальность и т.д. масштабируют эти удары), особом приёме и супере.

	Фреймдата — в кадрах 60 FPS; хитбокс — относительно ног бойца (x — вперёд по взгляду).
	cancels — во что удар можно отменить, если он попал или был заблокирован (комбо-цепочки).
	Особый приём и супер берутся из конфига персонажа (Config/Characters).
]]

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Stance = "Stand" | "Crouch" | "Air"
export type Button = "Light" | "Heavy"

export type NormalMove = {
	id: string,
	stance: Stance,
	button: Button,
	data: Types.MoveData,
	cancels: { string },
}

-- Порядок важен: индекс приёма передаётся в снапшотах.
local IDS: { string } = {
	"Light1",
	"Light2",
	"Light3",
	"Heavy",
	"CrouchLight",
	"CrouchHeavy",
	"AirLight",
	"AirHeavy",
	"Special",
	"Super",
}

local NORMALS: { [string]: NormalMove } = {
	-- «Рука»: быстрая цепочка из трёх ударов.
	Light1 = {
		id = "Light1",
		stance = "Stand",
		button = "Light",
		cancels = { "Light2", "Heavy", "Special", "Super" },
		data = {
			name = "Jab",
			startup = 4,
			active = 2,
			recovery = 8,
			damage = 30,
			chip = 0,
			hitstun = 15,
			blockstun = 10,
			hitbox = { x = 1.6, y = 4.3, w = 1.9, h = 1.0 },
			guard = "Mid",
			knockback = 3,
		},
	},
	Light2 = {
		id = "Light2",
		stance = "Stand",
		button = "Light",
		cancels = { "Light3", "Heavy", "Special", "Super" },
		data = {
			name = "Cross",
			startup = 5,
			active = 2,
			recovery = 9,
			damage = 32,
			chip = 0,
			hitstun = 16,
			blockstun = 11,
			hitbox = { x = 1.7, y = 3.9, w = 2.0, h = 1.2 },
			guard = "Mid",
			knockback = 4,
		},
	},
	Light3 = {
		id = "Light3",
		stance = "Stand",
		button = "Light",
		cancels = { "Special", "Super" },
		data = {
			name = "Hook",
			startup = 7,
			active = 3,
			recovery = 13,
			damage = 45,
			chip = 4,
			hitstun = 20,
			blockstun = 13,
			hitbox = { x = 1.9, y = 3.6, w = 2.2, h = 1.6 },
			guard = "Mid",
			knockback = 10,
		},
	},
	-- «Нога»: медленнее, сильнее и дальше.
	Heavy = {
		id = "Heavy",
		stance = "Stand",
		button = "Heavy",
		cancels = { "Special", "Super" },
		data = {
			name = "Roundhouse",
			startup = 9,
			active = 3,
			recovery = 15,
			damage = 80,
			chip = 8,
			hitstun = 22,
			blockstun = 15,
			hitbox = { x = 2.3, y = 3.3, w = 2.6, h = 1.6 },
			guard = "Mid",
			knockback = 12,
		},
	},
	-- Удары сидя — низкие (блокируются только сидя).
	CrouchLight = {
		id = "CrouchLight",
		stance = "Crouch",
		button = "Light",
		cancels = { "CrouchLight", "CrouchHeavy", "Special", "Super" },
		data = {
			name = "Low Jab",
			startup = 4,
			active = 2,
			recovery = 8,
			damage = 24,
			chip = 0,
			hitstun = 14,
			blockstun = 9,
			hitbox = { x = 1.6, y = 1.2, w = 1.9, h = 1.0 },
			guard = "Low",
			knockback = 3,
		},
	},
	CrouchHeavy = {
		id = "CrouchHeavy",
		stance = "Crouch",
		button = "Heavy",
		cancels = { "Special", "Super" },
		data = {
			name = "Sweep",
			startup = 9,
			active = 3,
			recovery = 18,
			damage = 65,
			chip = 6,
			hitstun = 20,
			blockstun = 13,
			hitbox = { x = 2.3, y = 0.6, w = 2.8, h = 1.0 },
			guard = "Low",
			knockback = 6,
			knockdown = true,
		},
	},
	-- Удары в прыжке — «сверху» (блокируются только стоя).
	AirLight = {
		id = "AirLight",
		stance = "Air",
		button = "Light",
		cancels = {},
		data = {
			name = "Air Jab",
			startup = 4,
			active = 7,
			recovery = 7,
			damage = 35,
			chip = 0,
			hitstun = 15,
			blockstun = 10,
			hitbox = { x = 1.4, y = 2.6, w = 1.9, h = 1.8 },
			guard = "Overhead",
			knockback = 4,
		},
	},
	AirHeavy = {
		id = "AirHeavy",
		stance = "Air",
		button = "Heavy",
		cancels = {},
		data = {
			name = "Air Kick",
			startup = 7,
			active = 5,
			recovery = 10,
			damage = 60,
			chip = 6,
			hitstun = 18,
			blockstun = 12,
			hitbox = { x = 1.7, y = 1.8, w = 2.2, h = 2.0 },
			guard = "Overhead",
			knockback = 8,
		},
	},
}

-- Особый приём можно отменить в супер при попадании.
local SPECIAL_CANCELS: { string } = { "Super" }

return deepFreeze({
	ids = IDS,
	normals = NORMALS,
	specialCancels = SPECIAL_CANCELS,
})
