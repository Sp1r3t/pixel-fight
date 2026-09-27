--!strict
--[[
	Снаряды и ловушки: полёт, столкновения, попадания.

	Виды (для отрисовки на клиенте, индекс передаётся в снапшоте):
	  Orb   — прямой снаряд (Rook);
	  Comet — навесной снаряд с гравитацией (Astra), исчезает, коснувшись пола;
	  Disc  — бумеранг (Juno): летит на дальность range, затем возвращается к владельцу;
	          может попасть по пути туда и по пути обратно;
	  Wave  — волна по земле (Glacia), низкий удар;
	  Mine  — ловушка (Byte): лежит на полу, взводится, срабатывает под противником на земле.

	Правила: снаряды разных владельцев при встрече уничтожают друг друга; активный луч или обстрел
	(супер Beam/Barrage) сносит снаряды соперника; у бойца одновременно не больше одного снаряда
	своего особого приёма (проверяет Specials.canStart).
]]

local Types = require(script.Parent.Parent.Types)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Hitbox = require(script.Parent.Hitbox)
local Fighter = require(script.Parent.Fighter)
local SimState = require(script.Parent.SimState)

type Sim = SimState.Sim
type Projectile = SimState.Projectile

local TICK = GameConfig.TickRate
local DT = 1 / TICK
local WALL = GameConfig.Physics.ArenaHalfWidth + 2 -- снаряд исчезает за краем арены

export type ProjectileHit = {
	projectile: Projectile,
	defender: Fighter.Fighter,
	x: number,
	y: number,
}

export type SpawnOptions = {
	kind: string,
	x: number,
	y: number,
	vx: number,
	vy: number?,
	lifetime: number, -- кадры
	move: Types.MoveData,
	hits: number?,
	gravity: number?,
	range: number?,
	armFrames: number?,
}

local Projectiles = {}

Projectiles.KINDS = table.freeze({ "Orb", "Comet", "Disc", "Wave", "Mine" })
Projectiles.MINE_ARM_FRAMES = 8
Projectiles.REHIT_FRAMES = 20

local kindIndex: { [string]: number } = {}
for index, kind in Projectiles.KINDS do
	kindIndex[kind] = index
end

function Projectiles.kindToIndex(kind: string): number
	return kindIndex[kind] or 0
end

function Projectiles.indexToKind(index: number): string?
	return Projectiles.KINDS[index]
end

function Projectiles.spawn(sim: Sim, owner: Fighter.Fighter, options: SpawnOptions): Projectile
	sim.nextProjectileId += 1
	local projectile: Projectile = {
		id = sim.nextProjectileId,
		owner = owner.slot,
		kind = options.kind,
		x = options.x,
		y = options.y,
		vx = options.vx,
		vy = options.vy or 0,
		width = options.move.hitbox.w,
		height = options.move.hitbox.h,
		age = 0,
		lifetime = options.lifetime,
		move = options.move,
		hitsLeft = options.hits or 1,
		rehitCooldown = 0,
		gravity = options.gravity or 0,
		range = options.range or math.huge,
		travelled = 0,
		returning = false,
		armFrames = options.armFrames or 0,
		facing = if options.vx < 0 then -1 elseif options.vx > 0 then 1 else owner.facing,
	}
	table.insert(sim.projectiles, projectile)
	SimState.emitAt(sim, "Projectile", owner, projectile.x, projectile.y, projectile.id, owner.slot, projectile.kind)
	return projectile
end

-- Сколько живых снарядов вида kind у владельца.
function Projectiles.countOwned(sim: Sim, owner: number, kind: string): number
	local count = 0
	for _, projectile in sim.projectiles do
		if projectile.owner == owner and projectile.kind == kind then
			count += 1
		end
	end
	return count
end

function Projectiles.removeOwned(sim: Sim, owner: number, kind: string)
	for index = #sim.projectiles, 1, -1 do
		local projectile = sim.projectiles[index]
		if projectile.owner == owner and projectile.kind == kind then
			table.remove(sim.projectiles, index)
		end
	end
end

local function rectOf(projectile: Projectile): Hitbox.Rect
	return {
		left = projectile.x - projectile.width / 2,
		right = projectile.x + projectile.width / 2,
		bottom = projectile.y - projectile.height / 2,
		top = projectile.y + projectile.height / 2,
	}
end

Projectiles.rectOf = rectOf

local function remove(sim: Sim, projectile: Projectile, reason: string)
	local index = table.find(sim.projectiles, projectile)
	if index then
		table.remove(sim.projectiles, index)
		local owner = sim.fighters[projectile.owner]
		SimState.emitAt(sim, "ProjectileEnd", owner, projectile.x, projectile.y, projectile.id, owner.slot, reason)
	end
end

Projectiles.remove = remove

-- Движение одного снаряда за кадр. Возвращает false, если снаряд исчез.
local function move(sim: Sim, projectile: Projectile): boolean
	projectile.age += 1
	if projectile.rehitCooldown > 0 then
		projectile.rehitCooldown -= 1
	end
	if projectile.age > projectile.lifetime then
		remove(sim, projectile, "Expired")
		return false
	end
	if projectile.kind == "Mine" then
		return true -- лежит на месте
	end
	if projectile.kind == "Disc" then
		if not projectile.returning and projectile.travelled >= projectile.range then
			projectile.returning = true
		end
		if projectile.returning then
			-- Возвращается к владельцу; поймал — снаряд исчезает.
			local owner = sim.fighters[projectile.owner]
			local dx = owner.x - projectile.x
			local speed = math.abs(projectile.vx)
			projectile.vx = if dx >= 0 then speed else -speed
			projectile.vy = ((owner.y + 3.5) - projectile.y) * 4
			if math.abs(dx) < 1.2 then
				remove(sim, projectile, "Caught")
				return false
			end
		end
	end
	projectile.vy -= projectile.gravity * DT
	local stepX = projectile.vx * DT
	projectile.x += stepX
	projectile.y += projectile.vy * DT
	projectile.travelled += math.abs(stepX)
	if math.abs(projectile.x) > WALL then
		if projectile.kind == "Disc" and not projectile.returning then
			projectile.returning = true
		else
			remove(sim, projectile, "Wall")
			return false
		end
	end
	if projectile.kind == "Comet" and projectile.y - projectile.height / 2 <= 0 and projectile.vy < 0 then
		remove(sim, projectile, "Ground")
		return false
	end
	return true
end

-- Снаряд задевает бойца? Ловушка срабатывает только под бойцом на земле.
local function touches(projectile: Projectile, defender: Fighter.Fighter): (number?, number?)
	if projectile.kind == "Mine" then
		if projectile.age < projectile.armFrames or Fighter.isAirborne(defender) then
			return nil, nil
		end
	end
	local hurt = Hitbox.hurt(defender.x, defender.y, Fighter.hurtKind(defender))
	if hurt == nil then
		return nil, nil
	end
	local rect = rectOf(projectile)
	if Hitbox.overlaps(rect, hurt) then
		return Hitbox.contactPoint(rect, hurt)
	end
	return nil, nil
end

-- Идёт ли у бойца луч/обстрел супера, сносящий снаряды соперника.
local function sweepsProjectiles(fighter: Fighter.Fighter, beamActive: (Fighter.Fighter) -> boolean): boolean
	return fighter.state == "Attack" and fighter.move == "Super" and beamActive(fighter)
end

--[[
	Шаг всех снарядов: движение, столкновения друг с другом, лучи суперов, попадания по бойцам.
	Возвращает попадания — их применяет симуляция (урон, блок, реакция — как у обычных ударов).
]]
function Projectiles.step(sim: Sim, beamActive: (Fighter.Fighter) -> boolean): { ProjectileHit }
	local hits: { ProjectileHit } = {}
	for _, projectile in table.clone(sim.projectiles) do
		if table.find(sim.projectiles, projectile) then
			move(sim, projectile)
		end
	end

	-- Встречные снаряды разных владельцев гасят друг друга (ловушки не участвуют).
	for _, a in table.clone(sim.projectiles) do
		for _, b in table.clone(sim.projectiles) do
			if
				a.owner < b.owner
				and a.kind ~= "Mine"
				and b.kind ~= "Mine"
				and table.find(sim.projectiles, a)
				and table.find(sim.projectiles, b)
				and Hitbox.overlaps(rectOf(a), rectOf(b))
			then
				remove(sim, a, "Clash")
				remove(sim, b, "Clash")
			end
		end
	end

	-- Луч или обстрел супера сносит снаряды соперника.
	for _, fighter in sim.fighters do
		if sweepsProjectiles(fighter, beamActive) then
			for _, projectile in table.clone(sim.projectiles) do
				if projectile.owner ~= fighter.slot then
					remove(sim, projectile, "Swept")
				end
			end
		end
	end

	for _, projectile in table.clone(sim.projectiles) do
		local defender = sim.fighters[3 - projectile.owner]
		if projectile.rehitCooldown == 0 and projectile.hitsLeft > 0 then
			local x, y = touches(projectile, defender)
			if x and y then
				table.insert(hits, { projectile = projectile, defender = defender, x = x, y = y })
			end
		end
	end
	return hits
end

-- После попадания снаряд тратит попадание (бумеранг пролетает насквозь и может ударить на обратном пути).
function Projectiles.consume(sim: Sim, projectile: Projectile)
	projectile.hitsLeft -= 1
	if projectile.hitsLeft <= 0 then
		remove(sim, projectile, "Hit")
	else
		projectile.rehitCooldown = Projectiles.REHIT_FRAMES
	end
end

return Projectiles
