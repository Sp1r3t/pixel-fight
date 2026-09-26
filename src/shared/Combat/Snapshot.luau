--!strict
--[[
	Снапшот — то, что сервер отправляет клиентам каждый сетевой тик: всё, что нужно для отрисовки
	(позиции, состояния, HP, супер, текущий приём), в компактном двоичном виде (buffer).
	Клиент никогда не присылает снапшоты — только ввод.
]]

local Fighter = require(script.Parent.Fighter)

export type FighterSnapshot = {
	x: number,
	y: number,
	vx: number,
	vy: number,
	facing: number,
	state: Fighter.StateName,
	stateFrame: number,
	health: number,
	maxHealth: number,
	meter: number,
	move: number, -- индекс приёма (0 — нет), см. Combat/Moves
	moveFrame: number,
	flags: number, -- биты Snapshot.Flags
	combo: number, -- сколько ударов подряд получил боец в текущем комбо
}

export type ProjectileSnapshot = {
	id: number,
	owner: number,
	kind: number,
	x: number,
	y: number,
	direction: number,
	age: number,
}

export type Snapshot = {
	frame: number,
	phase: number, -- фаза раунда (этап 4)
	timer: number, -- оставшееся время раунда в кадрах
	fighters: { FighterSnapshot },
	projectiles: { ProjectileSnapshot },
}

local Snapshot = {}

Snapshot.VERSION = 1

Snapshot.Flags = table.freeze({
	Invulnerable = 1,
	Armor = 2,
	Hitstop = 4,
	LowBlock = 8,
	SuperReady = 16,
})

local FIGHTER_BYTES = 4 + 4 + 2 + 2 + 1 + 1 + 2 + 2 + 2 + 2 + 1 + 2 + 1 + 1
local PROJECTILE_BYTES = 2 + 1 + 1 + 4 + 4 + 1 + 2
local HEADER_BYTES = 1 + 4 + 1 + 2 + 1 + 1

local function clampInt(value: number, min: number, max: number): number
	return math.clamp(math.floor(value + 0.5), min, max)
end

function Snapshot.fromFighter(fighter: Fighter.Fighter): FighterSnapshot
	local flags = 0
	if fighter.invulnerable > 0 then
		flags = bit32.bor(flags, Snapshot.Flags.Invulnerable)
	end
	return {
		x = fighter.x,
		y = fighter.y,
		vx = fighter.vx,
		vy = fighter.vy,
		facing = fighter.facing,
		state = fighter.state,
		stateFrame = fighter.stateFrame,
		health = fighter.health,
		maxHealth = fighter.maxHealth,
		meter = fighter.meter,
		move = 0,
		moveFrame = 0,
		flags = flags,
		combo = 0,
	}
end

function Snapshot.encode(snapshot: Snapshot): buffer
	local fighterCount = math.min(#snapshot.fighters, 255)
	local projectileCount = math.min(#snapshot.projectiles, 255)
	local size = HEADER_BYTES + fighterCount * FIGHTER_BYTES + projectileCount * PROJECTILE_BYTES
	local b = buffer.create(size)
	local offset = 0

	buffer.writeu8(b, offset, Snapshot.VERSION)
	offset += 1
	buffer.writeu32(b, offset, clampInt(snapshot.frame, 0, 4294967295))
	offset += 4
	buffer.writeu8(b, offset, clampInt(snapshot.phase, 0, 255))
	offset += 1
	buffer.writeu16(b, offset, clampInt(snapshot.timer, 0, 65535))
	offset += 2
	buffer.writeu8(b, offset, fighterCount)
	offset += 1
	buffer.writeu8(b, offset, projectileCount)
	offset += 1

	for index = 1, fighterCount do
		local f = snapshot.fighters[index]
		buffer.writef32(b, offset, f.x)
		buffer.writef32(b, offset + 4, f.y)
		buffer.writei16(b, offset + 8, clampInt(f.vx * 10, -32768, 32767))
		buffer.writei16(b, offset + 10, clampInt(f.vy * 10, -32768, 32767))
		buffer.writei8(b, offset + 12, if f.facing < 0 then -1 else 1)
		buffer.writeu8(b, offset + 13, Fighter.stateToIndex(f.state))
		buffer.writeu16(b, offset + 14, clampInt(f.stateFrame, 0, 65535))
		buffer.writeu16(b, offset + 16, clampInt(f.health, 0, 65535))
		buffer.writeu16(b, offset + 18, clampInt(f.maxHealth, 0, 65535))
		buffer.writeu16(b, offset + 20, clampInt(f.meter, 0, 65535))
		buffer.writeu8(b, offset + 22, clampInt(f.move, 0, 255))
		buffer.writeu16(b, offset + 23, clampInt(f.moveFrame, 0, 65535))
		buffer.writeu8(b, offset + 25, clampInt(f.flags, 0, 255))
		buffer.writeu8(b, offset + 26, clampInt(f.combo, 0, 255))
		offset += FIGHTER_BYTES
	end

	for index = 1, projectileCount do
		local p = snapshot.projectiles[index]
		buffer.writeu16(b, offset, clampInt(p.id, 0, 65535))
		buffer.writeu8(b, offset + 2, clampInt(p.owner, 0, 255))
		buffer.writeu8(b, offset + 3, clampInt(p.kind, 0, 255))
		buffer.writef32(b, offset + 4, p.x)
		buffer.writef32(b, offset + 8, p.y)
		buffer.writei8(b, offset + 12, if p.direction < 0 then -1 else 1)
		buffer.writeu16(b, offset + 13, clampInt(p.age, 0, 65535))
		offset += PROJECTILE_BYTES
	end

	return b
end

-- Разбор снапшота. Возвращает nil для повреждённых/чужих данных.
function Snapshot.decode(b: buffer): Snapshot?
	if typeof(b) ~= "buffer" or buffer.len(b) < HEADER_BYTES then
		return nil
	end
	if buffer.readu8(b, 0) ~= Snapshot.VERSION then
		return nil
	end
	local frame = buffer.readu32(b, 1)
	local phase = buffer.readu8(b, 5)
	local timer = buffer.readu16(b, 6)
	local fighterCount = buffer.readu8(b, 8)
	local projectileCount = buffer.readu8(b, 9)
	if buffer.len(b) ~= HEADER_BYTES + fighterCount * FIGHTER_BYTES + projectileCount * PROJECTILE_BYTES then
		return nil
	end

	local offset = HEADER_BYTES
	local fighters: { FighterSnapshot } = {}
	for _ = 1, fighterCount do
		local state = Fighter.indexToState(buffer.readu8(b, offset + 13))
		if state == nil then
			return nil
		end
		local fighter: FighterSnapshot = {
			x = buffer.readf32(b, offset),
			y = buffer.readf32(b, offset + 4),
			vx = buffer.readi16(b, offset + 8) / 10,
			vy = buffer.readi16(b, offset + 10) / 10,
			facing = buffer.readi8(b, offset + 12),
			state = state :: Fighter.StateName,
			stateFrame = buffer.readu16(b, offset + 14),
			health = buffer.readu16(b, offset + 16),
			maxHealth = buffer.readu16(b, offset + 18),
			meter = buffer.readu16(b, offset + 20),
			move = buffer.readu8(b, offset + 22),
			moveFrame = buffer.readu16(b, offset + 23),
			flags = buffer.readu8(b, offset + 25),
			combo = buffer.readu8(b, offset + 26),
		}
		table.insert(fighters, fighter)
		offset += FIGHTER_BYTES
	end

	local projectiles: { ProjectileSnapshot } = {}
	for _ = 1, projectileCount do
		table.insert(projectiles, {
			id = buffer.readu16(b, offset),
			owner = buffer.readu8(b, offset + 2),
			kind = buffer.readu8(b, offset + 3),
			x = buffer.readf32(b, offset + 4),
			y = buffer.readf32(b, offset + 8),
			direction = buffer.readi8(b, offset + 12),
			age = buffer.readu16(b, offset + 13),
		})
		offset += PROJECTILE_BYTES
	end

	return {
		frame = frame,
		phase = phase,
		timer = timer,
		fighters = fighters,
		projectiles = projectiles,
	}
end

return Snapshot
