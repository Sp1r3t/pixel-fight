--!strict
--[[
	Specials — поведение особых приёмов (16 типов) и суперов (6 способов доставки).

	Фреймдата и урон — в Config/Characters (move), параметры — в params. Здесь — только
	то, чем приёмы отличаются друг от друга: движение, снаряды, неуязвимость, броня, контратака,
	притягивание. Все функции детерминированы и работают только с данными симуляции.

	Особые приёмы:
	  Projectile / ArcProjectile / Boomerang / GroundWave — снаряд на первом активном кадре;
	  Trap        — мина перед бойцом (новая заменяет старую);
	  RushStrike  — рывок-удар (останавливается при попадании);   SpinDash — вращение с продвижением;
	  ArmorCharge — рывок с бронёй на armorHits ударов;           RisingStrike — неуязвимый взлёт;
	  DiveKick    — подскок и пике под углом («сверху»), приземление завершает приём;          OverheadLeap — прыжок-дуга, удар при приземлении;
	  Teleport    — неуязвимое исчезновение и удар из-за спины;   Counter — стойка: перехватывает удар и отвечает;
	  CommandGrab — неблокируемый захват вплотную;                Hook — дальний крюк, притягивает противника;
	  LongThrust  — шаг вперёд и дальний выпад.
	Суперы: Rush — рывок; Launcher — неуязвимый взлёт; Beam — луч на весь экран; Barrage — обстрел
	площади; Grab — захват; Counter — стойка-контратака. Попадание супера запускает ролик.
]]

local Types = require(script.Parent.Parent.Types)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local CharacterRegistry = require(script.Parent.Parent.Characters.CharacterRegistry)
local Fighter = require(script.Parent.Fighter)
local SimState = require(script.Parent.SimState)
local Projectiles = require(script.Parent.Projectiles)

type Sim = SimState.Sim
type Fighter = Fighter.Fighter

local Physics = GameConfig.Physics
local Combat = GameConfig.Combat
local TICK = GameConfig.TickRate
local DT = 1 / TICK
local WALL = Physics.ArenaHalfWidth - Physics.PushWidth / 2

local ARC_GRAVITY = 150 -- навесной снаряд: крутая дуга на среднюю дистанцию
local RISE_SPEED = 32 -- скорость взлёта апперкотов/лаунчеров
local BEHIND_DISTANCE = 1.6 -- на каком расстоянии за спиной появляется телепортирующийся

export type Behaviour = {
	kind: string, -- тип особого приёма или способ доставки супера
	isSuper: boolean,
	move: Types.MoveData,
	params: Types.MoveParams,
}

local Specials = {}

local PROJECTILE_KIND: { [string]: string } = {
	Projectile = "Orb",
	ArcProjectile = "Comet",
	Boomerang = "Disc",
	GroundWave = "Wave",
	Trap = "Mine",
}

-- Поведение приёма бойца (nil — обычный удар).
function Specials.behaviour(fighter: Fighter, moveId: string?): Behaviour?
	if moveId ~= "Special" and moveId ~= "Super" then
		return nil
	end
	local def = CharacterRegistry.get(fighter.characterId)
	if def == nil then
		return nil
	end
	if moveId == "Special" then
		local kind: string = def.special.kind
		return { kind = kind, isSuper = false, move = def.special.move, params = def.special.params }
	end
	local delivery: string = def.super.delivery
	return { kind = delivery, isSuper = true, move = def.super.move, params = def.super.params }
end

-- Вид снаряда приёма (nil — приём без снаряда).
function Specials.projectileKind(behaviour: Behaviour): string?
	return if behaviour.isSuper then nil else PROJECTILE_KIND[behaviour.kind]
end

-- Можно ли начать приём: у бойца не больше одного своего снаряда на арене.
function Specials.canStart(sim: Sim, fighter: Fighter, moveId: string): boolean
	local behaviour = Specials.behaviour(fighter, moveId)
	if behaviour == nil then
		return true
	end
	local kind = Specials.projectileKind(behaviour)
	if kind == nil or kind == "Mine" then
		return true
	end
	return Projectiles.countOwned(sim, fighter.slot, kind) == 0
end

-- Бьёт ли приём своим хитбоксом (у снарядов, ловушек и контратак — нет).
function Specials.usesMeleeHitbox(fighter: Fighter, moveId: string): boolean
	local behaviour = Specials.behaviour(fighter, moveId)
	if behaviour == nil then
		return true
	end
	return Specials.projectileKind(behaviour) == nil and behaviour.kind ~= "Counter"
end

local function isActiveFrame(move: Types.MoveData, frame: number): boolean
	return frame >= move.startup and frame < move.startup + move.active
end

-- Стоит ли боец в стойке контратаки прямо сейчас.
function Specials.isCountering(fighter: Fighter): boolean
	if fighter.state ~= "Attack" or fighter.moveConnected then
		return false
	end
	local behaviour = Specials.behaviour(fighter, fighter.move)
	return behaviour ~= nil and behaviour.kind == "Counter" and isActiveFrame(behaviour.move, fighter.moveFrame)
end

-- Луч или обстрел супера активен (сносит снаряды соперника).
function Specials.sweepsProjectiles(fighter: Fighter): boolean
	local behaviour = Specials.behaviour(fighter, fighter.move)
	return behaviour ~= nil
		and behaviour.isSuper
		and (behaviour.kind == "Beam" or behaviour.kind == "Barrage")
		and isActiveFrame(behaviour.move, fighter.moveFrame)
end

-- Приземление не прерывает приём (прыжок-дуга бьёт как раз при приземлении).
function Specials.keepsMoveOnLand(fighter: Fighter): boolean
	local behaviour = Specials.behaviour(fighter, fighter.move)
	if behaviour == nil or behaviour.kind ~= "OverheadLeap" then
		return false
	end
	return fighter.moveFrame < behaviour.move.startup + behaviour.move.active
end

-- Начало приёма: неуязвимость, броня, одноразовые эффекты.
function Specials.onStart(sim: Sim, fighter: Fighter, moveId: string)
	local behaviour = Specials.behaviour(fighter, moveId)
	if behaviour == nil then
		return
	end
	local params = behaviour.params
	local move = behaviour.move
	if params.invincibleFrames then
		-- +1: счётчик уменьшается уже в кадре начала приёма.
		fighter.invulnerable = math.max(fighter.invulnerable, params.invincibleFrames + 1)
	end
	local kind = behaviour.kind
	if kind == "ArmorCharge" then
		fighter.armor = params.armorHits or 1
	elseif kind == "Teleport" then
		-- Исчезает на время подготовки: по нему нельзя попасть.
		fighter.invulnerable = math.max(fighter.invulnerable, move.startup + 1)
		SimState.emit(sim, "Vanish", fighter)
	elseif kind == "Trap" then
		Projectiles.removeOwned(sim, fighter.slot, "Mine")
	end
end

local function applyGravity(fighter: Fighter)
	if Fighter.isAirborne(fighter) or fighter.vy > 0 then
		fighter.vy -= Physics.Gravity * DT
	end
end

-- Скорость, чтобы пройти distance за frames кадров.
local function speedFor(distance: number, frames: number): number
	return distance / math.max(1, frames) * TICK
end

local function spawnProjectile(sim: Sim, fighter: Fighter, behaviour: Behaviour)
	local move = behaviour.move
	local params = behaviour.params
	local kind = Specials.projectileKind(behaviour) :: string
	local facing = fighter.facing
	local x = math.clamp(fighter.x + facing * move.hitbox.x, -WALL, WALL)
	local y = fighter.y + move.hitbox.y
	local speed = params.projectileSpeed or 25
	local lifetime = math.floor((params.projectileLifetime or 2) * TICK + 0.5)
	if kind == "Orb" or kind == "Wave" then
		Projectiles.spawn(sim, fighter, {
			kind = kind,
			x = x,
			y = y,
			vx = facing * speed,
			lifetime = lifetime,
			move = move,
		})
	elseif kind == "Comet" then
		local height = params.arcHeight or 6
		Projectiles.spawn(sim, fighter, {
			kind = kind,
			x = x,
			y = y,
			vx = facing * speed,
			vy = math.sqrt(2 * ARC_GRAVITY * height),
			gravity = ARC_GRAVITY,
			lifetime = 4 * TICK,
			move = move,
		})
	elseif kind == "Disc" then
		Projectiles.spawn(sim, fighter, {
			kind = kind,
			x = x,
			y = y,
			vx = facing * speed,
			lifetime = 4 * TICK,
			move = move,
			hits = 2, -- туда и обратно
			range = params.travelDistance or 16,
		})
	elseif kind == "Mine" then
		Projectiles.spawn(sim, fighter, {
			kind = kind,
			x = x,
			y = move.hitbox.h / 2,
			vx = 0,
			lifetime = math.floor((params.trapLifetime or 5) * TICK + 0.5),
			move = move,
			armFrames = Projectiles.MINE_ARM_FRAMES,
		})
	end
end

local function teleport(sim: Sim, fighter: Fighter, distance: number)
	local opponent = SimState.opponentOf(sim, fighter)
	local dx = opponent.x - fighter.x
	local side = if dx >= 0 then 1 else -1
	local target: number
	if math.abs(dx) <= distance then
		-- За спину противника; если там стена — перед ним.
		target = opponent.x + side * BEHIND_DISTANCE
		if math.abs(target) > WALL then
			target = opponent.x - side * BEHIND_DISTANCE
		end
	else
		target = fighter.x + side * distance
	end
	fighter.x = math.clamp(target, -WALL, WALL)
	fighter.facing = if opponent.x >= fighter.x then 1 else -1
	SimState.emit(sim, "Appear", fighter)
end

--[[
	Кадр приёма. Возвращает true, если приём сам управляет движением бойца
	(тогда симуляция не обнуляет скорость и не применяет гравитацию сама).
]]
function Specials.update(sim: Sim, fighter: Fighter, behaviour: Behaviour): boolean
	local move = behaviour.move
	local params = behaviour.params
	local frame = fighter.moveFrame
	local startup = move.startup
	local activeEnd = startup + move.active
	local facing = fighter.facing
	local kind = behaviour.kind

	if Specials.projectileKind(behaviour) then
		if frame == startup then
			spawnProjectile(sim, fighter, behaviour)
		end
		return false
	end

	if kind == "RushStrike" or kind == "ArmorCharge" or kind == "Rush" then
		local distance = params.travelDistance or 6
		if frame < activeEnd and not fighter.moveConnected then
			fighter.vx = facing * speedFor(distance, activeEnd)
		else
			fighter.vx = 0
		end
		if kind == "ArmorCharge" and frame >= activeEnd then
			fighter.armor = 0
		end
		applyGravity(fighter)
		return true
	elseif kind == "SpinDash" then
		fighter.vx = if isActiveFrame(move, frame)
			then facing * speedFor(params.travelDistance or 6, move.active)
			else 0
		applyGravity(fighter)
		return true
	elseif kind == "LongThrust" then
		fighter.vx = if frame < startup then facing * speedFor(params.travelDistance or 2, startup) else 0
		applyGravity(fighter)
		return true
	elseif kind == "RisingStrike" or kind == "Launcher" then
		if frame == startup then
			fighter.vy = RISE_SPEED
			fighter.vx = facing * 3
		elseif not Fighter.isAirborne(fighter) and fighter.vy <= 0 then
			fighter.vx = 0
		end
		applyGravity(fighter)
		return true
	elseif kind == "DiveKick" then
		-- Подскок на 60% высоты дуги, затем прямой нырок вперёд: приземление ровно к концу активных кадров.
		local height = (params.arcHeight or 6) * 0.6
		if frame < startup then
			local u = (frame + 1) / startup
			fighter.vx = facing * 2
			fighter.vy = (height * (1 - (1 - u) * (1 - u)) - fighter.y) * TICK
		elseif frame < activeEnd then
			fighter.vx = facing * speedFor(params.travelDistance or 8, move.active)
			fighter.vy = -math.max(fighter.y, 0.2) / (activeEnd - frame) * TICK
		else
			applyGravity(fighter)
		end
		return true
	elseif kind == "OverheadLeap" then
		if frame < startup then
			-- Точная дуга: за startup кадров — travelDistance вперёд и arcHeight вверх.
			local u = (frame + 1) / startup
			local height = 4 * (params.arcHeight or 5) * u * (1 - u)
			fighter.vx = facing * speedFor(params.travelDistance or 5, startup)
			fighter.vy = (height - fighter.y) * TICK
		else
			fighter.vx = 0
			fighter.vy = if fighter.y > 0 then -fighter.y * TICK else 0
		end
		return true
	elseif kind == "Teleport" then
		fighter.vx = 0
		if frame == startup - 1 then
			teleport(sim, fighter, params.travelDistance or 10)
		end
		applyGravity(fighter)
		return true
	end
	return false
end

-- После попадания или блока приёма: крюк притягивает противника.
function Specials.afterHit(attacker: Fighter, defender: Fighter, behaviour: Behaviour, blocked: boolean)
	if behaviour.kind == "Hook" and not blocked and not defender.ko then
		local side = if defender.x >= attacker.x then 1 else -1
		-- Отбрасывание затухает с PushFriction за кадр: подбираем скорость под нужное смещение.
		local distance = behaviour.params.pullDistance or 5
		defender.push = -side * distance * TICK * (1 - Combat.PushFriction)
	end
end

--[[
	Угроза приёма для ИИ: на какой дистанции (от и до) он достаёт и должен ли противник быть на земле.
	Для снарядов — вся дальность полёта.
]]
function Specials.reach(fighter: Fighter, moveId: string): (number, number, boolean)
	local behaviour = Specials.behaviour(fighter, moveId)
	if behaviour == nil then
		return 0, 0, false
	end
	local move = behaviour.move
	local params = behaviour.params
	local hurtHalf = Combat.HurtboxWidth / 2
	local melee = move.hitbox.x + move.hitbox.w / 2 + hurtHalf
	local kind = behaviour.kind
	if kind == "Projectile" or kind == "GroundWave" then
		local range = (params.projectileSpeed or 25) * (params.projectileLifetime or 2)
		return 0, range, kind == "GroundWave"
	elseif kind == "ArcProjectile" then
		-- Снаряд опасен на спуске: от высоты макушки стоящего бойца до пола.
		local speed = params.projectileSpeed or 20
		local vy = math.sqrt(2 * ARC_GRAVITY * (params.arcHeight or 6))
		local y0 = move.hitbox.y
		local half = move.hitbox.h / 2
		local function timeAt(height: number): number
			local discriminant = vy * vy + 2 * ARC_GRAVITY * (y0 - height)
			return (vy + math.sqrt(math.max(0, discriminant))) / ARC_GRAVITY
		end
		local near = move.hitbox.x + speed * timeAt(Physics.StandHeight + half) - hurtHalf
		local far = move.hitbox.x + speed * timeAt(half) + hurtHalf
		return near, far, false
	elseif kind == "Boomerang" then
		return 0, (params.travelDistance or 16) + 1, false
	elseif kind == "Trap" then
		return math.max(0, move.hitbox.x - 1.5), move.hitbox.x + 1.5, true
	elseif kind == "Teleport" then
		return 0, params.travelDistance or 10, false
	elseif kind == "RushStrike" or kind == "ArmorCharge" or kind == "Rush" or kind == "SpinDash" then
		return 0, melee + (params.travelDistance or 6), false
	elseif kind == "OverheadLeap" or kind == "DiveKick" or kind == "LongThrust" then
		local travel = params.travelDistance or 5
		return math.max(0, travel - melee), travel + melee, false
	elseif kind == "Counter" then
		return 0, 0, false -- по инициативе не бьёт
	end
	return 0, melee, false
end

return Specials
