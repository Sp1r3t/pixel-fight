--!strict
--[[
	SimState — данные симуляции боя (типы) и мелкие общие функции.
	Отдельный модуль, чтобы Simulation, Specials и Projectiles могли пользоваться одними типами
	без циклических require.
]]

local Types = require(script.Parent.Parent.Types)
local Fighter = require(script.Parent.Fighter)

type Fighter = Fighter.Fighter

export type SimEvent = {
	kind: string, -- "Jump" | "Land" | "Dash" | "Hit" | "Block" | "KO" | "SuperFlash" | ...
	slot: number, -- о каком бойце событие
	x: number?,
	y: number?,
	value: number?, -- урон, длительность и т.п.
	attacker: number?, -- кто ударил
	tag: string?, -- уточнение: "Counter", "Heavy", id сценария супера, вид снаряда, ...
}

export type Cinematic = {
	attacker: number,
	defender: number,
	frame: number,
	duration: number, -- кадры
	hits: number,
	damage: number, -- суммарный урон серии
	dealt: number,
	hitsDone: number,
}

-- Снаряд (или ловушка) на арене. Живёт только на сервере; клиенту уходит в снапшоте.
export type Projectile = {
	id: number,
	owner: number, -- слот бойца-владельца
	kind: string, -- вид для отрисовки: "Orb" | "Comet" | "Disc" | "Wave" | "Mine"
	x: number,
	y: number, -- центр
	vx: number, -- студ/с
	vy: number,
	width: number,
	height: number,
	age: number, -- кадры
	lifetime: number, -- кадры
	move: Types.MoveData, -- урон, оглушение, тип блока
	hitsLeft: number, -- сколько ещё раз может попасть
	rehitCooldown: number, -- кадров до следующего возможного попадания (бумеранг)
	gravity: number, -- студ/с² (навесной снаряд)
	range: number, -- бумеранг: дистанция до разворота
	travelled: number,
	returning: boolean,
	armFrames: number, -- ловушка: кадров до взвода
	facing: number,
}

export type Sim = {
	frame: number,
	fighters: { Fighter },
	inputEnabled: boolean, -- false во время заставок раунда
	events: { SimEvent }, -- события последнего шага (для эффектов на клиенте)
	freeze: number, -- кадры вспышки супера (всё замирает)
	freezeOwner: number,
	cinematic: Cinematic?,
	projectiles: { Projectile },
	nextProjectileId: number,
}

local SimState = {}

function SimState.emitAt(
	sim: Sim,
	kind: string,
	fighter: Fighter,
	x: number,
	y: number,
	value: number?,
	attacker: number?,
	tag: string?
)
	table.insert(sim.events, {
		kind = kind,
		slot = fighter.slot,
		x = x,
		y = y,
		value = value,
		attacker = attacker,
		tag = tag,
	})
end

function SimState.emit(sim: Sim, kind: string, fighter: Fighter, value: number?, attacker: number?, tag: string?)
	SimState.emitAt(sim, kind, fighter, fighter.x, fighter.y, value, attacker, tag)
end

function SimState.opponentOf(sim: Sim, fighter: Fighter): Fighter
	return sim.fighters[3 - fighter.slot]
end

return SimState
