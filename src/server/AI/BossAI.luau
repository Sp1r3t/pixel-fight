--!strict
--[[
	BossAI — «мозг» компьютерного бойца поверх StateMachine.

	Главное правило: ИИ не трогает симуляцию напрямую. Он смотрит на бой и выдаёт ВВОД
	(held/pressed — как геймпад), который идёт через ту же боевую систему, что и ввод игроков.

	Восприятие: противника ИИ видит с задержкой reactionFrames (как человек — «в прошлом»),
	себя — как есть. Движение противника экстраполируется по видимой скорости.

	Состояния автомата:
	  Neutral  — дистанция: подход/отход, тычки, прыжки, рывки, особые приёмы; замечает угрозы;
	  Defend   — блок стоя/сидя, выход из блока с наказанием;
	  Punish   — выбор наказания промаха (переходит в Attack с планом комбо);
	  Attack   — выполнение плана комбо: отмены по попаданию, проверка попадания (hit-confirm);
	  AntiAir  — ожидание момента и удар по прыгнувшему противнику;
	  JumpIn   — прыжок с атакой сверху и продолжение после приземления;
	  Recover  — оглушение/нокдаун: защита при вставании, контр-супер;
	  Travel   — 2 на 2: переход на этаж цели (к дыре, прыжок с двойным прыжком или спрыгнуть вниз).
	Цель — противник, которого выбрала симуляция (ближайший, предпочтительно на своём этаже).

	Сложность — только параметры профиля (Types.AiProfile): реакция, частота блока, чтение
	стойки, наказания, анти-эйр, качество комбо, использование супера, чтение привычек, ошибки.
	Случайность детерминирована (Rng с зерном) — бои воспроизводимы в тестах.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local InputBits = require(ReplicatedStorage.Shared.Combat.InputBits)
local Fighter = require(ReplicatedStorage.Shared.Combat.Fighter)
local MoveBook = require(ReplicatedStorage.Shared.Combat.MoveBook)
local Hitbox = require(ReplicatedStorage.Shared.Combat.Hitbox)
local Simulation = require(ReplicatedStorage.Shared.Combat.Simulation)
local Specials = require(ReplicatedStorage.Shared.Combat.Specials)
local Stage = require(ReplicatedStorage.Shared.Combat.Stage)
local Rng = require(ReplicatedStorage.Shared.Util.Rng)

local StateMachine = require(script.Parent.StateMachine)

type AiProfile = Types.AiProfile
type Sim = Simulation.Sim
type FrameInput = InputBits.FrameInput
type Fighter = Fighter.Fighter

local Physics = GameConfig.Physics
local Combat = GameConfig.Combat
local TICK = GameConfig.TickRate
local METER_MAX = GameConfig.SuperMeter.Max
local WALL = Physics.ArenaHalfWidth - Physics.PushWidth / 2
local HISTORY = 64

-- Что ИИ «видит» о противнике в конкретный кадр.
export type Observation = {
	frame: number,
	x: number,
	y: number,
	floorY: number,
	standY: number, -- этаж, где противник стоял последний раз
	vx: number,
	vy: number,
	state: Fighter.StateName,
	stateFrame: number,
	move: string?,
	moveFrame: number,
	characterId: string,
	crouching: boolean,
	airborne: boolean,
	hurt: Hitbox.HurtKind,
	meter: number,
}

-- Шаг плана комбо: какую кнопку нажать и держать ли «вниз».
export type PlanStep = {
	button: "Light" | "Heavy" | "Special" | "Super",
	down: boolean?,
}

-- Привычки противника (для чтения). Считаются по тому, что ИИ видел.
export type Habits = {
	attacks: number,
	nearAttacks: number, -- атак вблизи (натиск)
	nearFrames: number,
	lows: number,
	overheads: number,
	jumps: number,
	neutralFrames: number,
}

export type Brain = {
	profile: AiProfile,
	rng: Rng.Rng,
	slot: number,
	machine: StateMachine.Machine<Brain>,

	-- Восприятие.
	history: { Observation },
	recorded: number,
	habits: Habits,
	lastSeenState: string,
	lastAttackKey: number, -- «подпись» последней замеченной атаки противника
	lastJumpHandled: boolean,

	-- Текущий кадр (заполняется в think).
	sim: Sim,
	me: Fighter,
	seen: Observation,
	dir: number, -- направление к противнику в мире: -1 / 1
	dist: number,
	held: number,
	pressed: number,

	-- Решения.
	decisionTimer: number,
	intent: "Idle" | "Forward" | "Back" | "Guard" | "Crouch",
	guardLow: boolean,
	calmFrames: number, -- сколько кадров подряд нет угрозы (выход из Defend)
	patience: number, -- сколько спокойных кадров держать блок
	guardHold: number, -- «прочитанный» натиск: держать блок дольше
	cautious: boolean, -- не входит в дальность ударов противника без нужды
	approachHandled: boolean, -- по этому сближению противника уже решили
	lastProjectile: number, -- по какому снаряду уже решили
	targetSlot: number, -- за кем сейчас следим (смена цели сбрасывает восприятие)
	upHeldLastFrame: boolean, -- для двойного прыжка: кнопку «вверх» надо отпустить и нажать снова
	crossing: number, -- 2 на 2: перелёт через дыру на другую платформу (направление; 0 — нет)
	crossFrames: number,
	crossLanding: number, -- куда приземлиться (X) после перелёта
	punishWindow: number, -- на сколько кадров противник откроется после нашего блокстана
	wasBlocked: boolean, -- последний удар плана заблокирован
	anticipateJump: boolean, -- «прочитал» прыжок: реагирует без задержки
	plan: { PlanStep },
	planIndex: number,
	planPressedAt: number, -- кадр автомата, когда нажат текущий шаг
	linkDelay: number,
	connectedSince: number, -- кадр, когда текущий удар попал (-1 — ещё нет)
	antiAirMove: string,
	jumpPressed: boolean,
	reversalTried: boolean,
	recoverGuard: boolean, -- держит «назад» во время оглушения
	seenKey: number,

	-- Кэш дальностей приёмов.
	characterId: string,
	moveCache: { [string]: Types.MoveData },
}

local BossAI = {}

----------------------------------------------------------------------------------------------
-- Восприятие
----------------------------------------------------------------------------------------------

local function newObservation(): Observation
	return {
		frame = 0,
		x = 0,
		y = 0,
		floorY = 0,
		standY = 0,
		vx = 0,
		vy = 0,
		state = "Idle",
		stateFrame = 0,
		move = nil,
		moveFrame = 0,
		characterId = "",
		crouching = false,
		airborne = false,
		hurt = "Stand",
		meter = 0,
	}
end

local function record(brain: Brain, fighter: Fighter, frame: number)
	brain.recorded += 1
	local index = (brain.recorded - 1) % HISTORY + 1
	local obs = brain.history[index]
	obs.frame = frame
	obs.x = fighter.x
	obs.y = fighter.y
	obs.floorY = fighter.floorY
	obs.standY = fighter.standY
	obs.vx = fighter.vx + fighter.push
	obs.vy = fighter.vy
	obs.state = fighter.state
	obs.stateFrame = fighter.stateFrame
	obs.move = fighter.move
	obs.moveFrame = fighter.moveFrame
	obs.characterId = fighter.characterId
	obs.crouching = Fighter.isCrouching(fighter)
	obs.airborne = Fighter.isAirborne(fighter)
	obs.hurt = Fighter.hurtKind(fighter)
	obs.meter = fighter.meter
end

-- Наблюдение delay кадров назад (или самое старое из имеющихся).
local function recall(brain: Brain, delay: number): Observation
	local available = math.min(brain.recorded, HISTORY)
	local back = math.clamp(delay, 0, available - 1)
	local index = (brain.recorded - 1 - back) % HISTORY + 1
	return brain.history[index]
end

local function updateHabits(brain: Brain)
	local seen = brain.seen
	local habits = brain.habits
	local state = seen.state
	if state == "Idle" or state == "Walk" or state == "Crouch" then
		habits.neutralFrames += 1
	end
	if brain.dist < 5 then
		habits.nearFrames += 1
	end
	if state == "PreJump" and brain.lastSeenState ~= "PreJump" then
		habits.jumps += 1
	end
	if state == "Attack" and seen.move then
		local key = seen.frame - seen.moveFrame
		if key ~= brain.seenKey then
			brain.seenKey = key
			habits.attacks += 1
			if brain.dist < 6 then
				habits.nearAttacks += 1
			end
			local move = MoveBook.get(seen.characterId, seen.move)
			if move and move.guard == "Low" then
				habits.lows += 1
			elseif move and move.guard == "Overhead" then
				habits.overheads += 1
			end
		end
	end
	brain.lastSeenState = state
end

-- Прыжков в секунду нейтрали.
local function jumpRate(habits: Habits): number
	return habits.jumps / (habits.neutralFrames / TICK + 3)
end

-- Атак в секунду, пока противник рядом.
local function pressureRate(habits: Habits): number
	return habits.nearAttacks / (habits.nearFrames / TICK + 2)
end

-- Доля низких ударов среди атак.
local function lowRatio(habits: Habits): number
	return habits.lows / (habits.attacks + 3)
end

----------------------------------------------------------------------------------------------
-- Вспомогательное
----------------------------------------------------------------------------------------------

local function chance(brain: Brain, probability: number): boolean
	return Rng.chance(brain.rng, probability)
end

local function moveData(brain: Brain, moveId: string): Types.MoveData?
	if brain.characterId ~= brain.me.characterId then
		brain.characterId = brain.me.characterId
		table.clear(brain.moveCache)
	end
	local cached = brain.moveCache[moveId]
	if cached then
		return cached
	end
	local move = MoveBook.get(brain.me.characterId, moveId)
	if move then
		brain.moveCache[moveId] = move
	end
	return move
end

local function forwardBit(brain: Brain): number
	return if brain.dir > 0 then InputBits.Right else InputBits.Left
end

local function backBit(brain: Brain): number
	return if brain.dir > 0 then InputBits.Left else InputBits.Right
end

local function hold(brain: Brain, bits: number)
	brain.held = bit32.bor(brain.held, bits)
end

local function press(brain: Brain, button: string)
	local bit = if button == "Light"
		then InputBits.Light
		elseif button == "Heavy" then InputBits.Heavy
		elseif button == "Special" then InputBits.Special
		elseif button == "Super" then InputBits.Super
		else InputBits.Dash
	brain.pressed = bit32.bor(brain.pressed, bit)
end

local function guard(brain: Brain, low: boolean)
	hold(brain, backBit(brain))
	if low then
		hold(brain, InputBits.Down)
	end
end

local ACTIONABLE: { [string]: boolean } = {
	Idle = true,
	Walk = true,
	Crouch = true,
	Block = true,
}

local DISABLED: { [string]: boolean } = {
	Hitstun = true,
	Juggle = true,
	Knockdown = true,
	WakeUp = true,
	Cinematic = true,
	KO = true,
	Win = true,
	Lose = true,
	Intro = true,
}

local function canAct(me: Fighter): boolean
	return ACTIONABLE[me.state] == true
end

local function superReady(me: Fighter): boolean
	return me.meter >= METER_MAX
end

-- Где будет противник через frames кадров (с учётом задержки восприятия).
local function predict(brain: Brain, frames: number): (number, number, Hitbox.HurtKind)
	local seen = brain.seen
	local t = (brain.profile.reactionFrames + frames) / TICK
	-- Горизонтальное движение экстраполируется осторожно (противник может остановиться)
	-- и не «сквозь» нас: ближе ширины тела он не подойдёт.
	local me = brain.me
	local x = math.clamp(seen.x + seen.vx * t * 0.6, -WALL, WALL)
	if not seen.airborne and (x - me.x) * (seen.x - me.x) >= 0 and math.abs(x - me.x) < Physics.PushWidth then
		x = me.x + (if seen.x >= me.x then 1 else -1) * Physics.PushWidth
	end
	local kind: Hitbox.HurtKind = seen.hurt
	local y = seen.y
	if seen.airborne and (seen.state == "Air" or seen.state == "Attack" or seen.state == "Juggle") then
		y = seen.y + seen.vy * t - 0.5 * Physics.Gravity * t * t
		if y <= seen.floorY then
			y = seen.floorY
			kind = (if seen.state == "Juggle" then "None" else "Stand") :: Hitbox.HurtKind
		end
	end
	return x, y, kind
end

-- Приёмы, дальность которых определяется не хитбоксом на месте: снаряды, рывки, прыжки, телепорт.
local RANGED_KINDS: { [string]: boolean } = {
	Projectile = true,
	ArcProjectile = true,
	Boomerang = true,
	GroundWave = true,
	Trap = true,
	Teleport = true,
	RushStrike = true,
	ArmorCharge = true,
	SpinDash = true,
	OverheadLeap = true,
	DiveKick = true,
	LongThrust = true,
	Rush = true,
	Counter = true,
}

-- Снаряды летят сами: угрозой считается сам снаряд, а не бросок (см. reactToProjectile).
local PROJECTILE_KINDS: { [string]: boolean } = {
	Projectile = true,
	ArcProjectile = true,
	Boomerang = true,
	GroundWave = true,
	Trap = true,
}

-- Попадёт ли приём, если нажать его сейчас (по видимой и предсказанной позиции противника).
local function wouldHit(brain: Brain, moveId: string): boolean
	local move = moveData(brain, moveId)
	if move == nil then
		return false
	end
	local me = brain.me
	if moveId == "Special" or moveId == "Super" then
		local behaviour = Specials.behaviour(me, moveId)
		if behaviour and RANGED_KINDS[behaviour.kind] then
			if behaviour.kind == "Counter" then
				return false -- стойка контратаки — только в ответ на атаку (reactToThreat)
			end
			local minRange, maxRange, grounded = Specials.reach(me, moveId)
			local x, y, kind: Hitbox.HurtKind = predict(brain, move.startup)
			if kind == "None" or (grounded and y > 0.5) then
				return false
			end
			local distance = math.abs(x - me.x)
			return distance >= minRange and distance <= maxRange
		end
	end
	local reach = if MoveBook.isNormal(moveId) then me.stats.rangeMultiplier else 1
	local facing = brain.dir
	for _, offset in { 0, math.floor(move.active / 2) } do
		local x, y, kind: Hitbox.HurtKind = predict(brain, move.startup + offset)
		local hurt = Hitbox.hurt(x, y, kind)
		if hurt then
			local rect = Hitbox.attack(me.x, me.y, facing, move.hitbox, reach)
			if Hitbox.overlaps(rect, hurt) then
				return true
			end
		end
	end
	return false
end

-- Дальность приёма противника (насколько близко опасно стоять).
local function opponentReach(brain: Brain, moveId: string): number
	local seen = brain.seen
	local move = MoveBook.get(seen.characterId, moveId)
	if move == nil then
		return 0
	end
	if moveId == "Special" or moveId == "Super" then
		local opponent = Simulation.opponentOf(brain.sim, brain.me)
		local behaviour = Specials.behaviour(opponent, moveId)
		if behaviour and PROJECTILE_KINDS[behaviour.kind] then
			return 0
		elseif behaviour and RANGED_KINDS[behaviour.kind] then
			local _, maxRange = Specials.reach(opponent, moveId)
			return maxRange + 0.6
		end
	end
	return move.hitbox.x + move.hitbox.w / 2 + Combat.HurtboxWidth / 2 + 0.6
end

-- Сколько кадров атаке противника осталось до конца (оценка «сейчас» по увиденному).
local function opponentAttackPhase(brain: Brain): (string, number, Types.MoveData?)
	local seen = brain.seen
	if seen.state ~= "Attack" or seen.move == nil then
		return "None", 0, nil
	end
	local move = MoveBook.get(seen.characterId, seen.move :: string)
	if move == nil then
		return "None", 0, nil
	end
	local now = seen.moveFrame + brain.profile.reactionFrames
	local total = MoveBook.totalFrames(move)
	if now < move.startup + move.active then
		return "Threat", total - now, move
	elseif now < total then
		return "Recovery", total - now, move
	end
	return "None", 0, move
end

----------------------------------------------------------------------------------------------
-- Планы комбо
----------------------------------------------------------------------------------------------

-- Стойка-контратака ничего не делает в комбо: противник уже в оглушении и не бьёт.
local function isStance(brain: Brain, moveId: string): boolean
	local behaviour = Specials.behaviour(brain.me, moveId)
	return behaviour ~= nil and behaviour.kind == "Counter"
end

-- Цепочка после стартового удара в зависимости от мастерства.
local function extendPlan(brain: Brain, starter: PlanStep): { PlanStep }
	local skill = brain.profile.comboSkill
	local plan: { PlanStep } = { starter }
	local specialStep: PlanStep = if isStance(brain, "Special") then { button = "Heavy" } else { button = "Special" }
	local function add(step: PlanStep)
		table.insert(plan, step)
	end
	local roll = Rng.next(brain.rng)
	local ender = skill >= 0.45 and roll < 0.35 + skill * 0.6
	local superEnder = skill >= 0.7
		and superReady(brain.me)
		and not isStance(brain, "Super")
		and chance(brain, brain.profile.superUsage)
	if starter.button == "Light" and starter.down then
		if skill >= 0.25 then
			add({ button = "Light", down = true })
		end
		if skill >= 0.5 then
			add(if chance(brain, 0.5) then { button = "Heavy", down = true } else specialStep)
		end
	elseif starter.button == "Light" then
		if skill >= 0.2 then
			add({ button = "Light" })
		end
		if skill >= 0.4 then
			add(if skill >= 0.6 and chance(brain, 0.5) then { button = "Heavy" } else { button = "Light" })
		end
		if ender then
			add(specialStep)
		end
	elseif starter.button == "Heavy" and not starter.down then
		if ender then
			add(specialStep)
		end
	elseif starter.button == "Heavy" and starter.down then
		if skill >= 0.6 and ender then
			add(specialStep)
		end
	end
	if superEnder and plan[#plan].button ~= "Super" then
		add({ button = "Super" })
	end
	return plan
end

type StarterOption = { id: string, step: PlanStep }

local STARTERS: { StarterOption } = {
	{ id = "Light1", step = { button = "Light" } },
	{ id = "Heavy", step = { button = "Heavy" } },
	{ id = "CrouchLight", step = { button = "Light", down = true } },
	{ id = "CrouchHeavy", step = { button = "Heavy", down = true } },
	{ id = "Special", step = { button = "Special" } },
}

-- Может ли противник ударить первым (стоит в своей дальности и не занят).
local function opponentCanHit(brain: Brain): boolean
	local seen = brain.seen
	local state = seen.state
	if DISABLED[state] or state == "Blockstun" or seen.airborne then
		return false
	end
	return brain.dist < opponentReach(brain, "Light2")
end

--[[
	Лучший стартовый удар, который сейчас достанет. maxStartup — для наказаний (успеть до конца
	восстановления противника). Если противник может ударить первым — умелый боец выбирает быстрые
	удары, иначе — самые сильные. Новичок берёт случайный из доступных.
]]
local function chooseStarter(brain: Brain, maxStartup: number?, preferLow: boolean?): PlanStep?
	local limit = maxStartup or math.huge
	local risky = maxStartup == nil and opponentCanHit(brain)
	local candidates: { StarterOption } = {}
	local best: StarterOption? = nil
	local bestScore = -math.huge
	for _, option in STARTERS do
		local move = moveData(brain, option.id)
		local usable = option.id ~= "Special" or brain.me.specialCooldown == 0
		if usable and move and move.startup <= limit and wouldHit(brain, option.id) then
			table.insert(candidates, option)
			local score = if risky then move.damage * 0.1 - move.startup * 10 else move.damage - move.startup * 3
			if preferLow and move.guard == "Low" then
				score += 40
			end
			if score > bestScore then
				bestScore = score
				best = option
			end
		end
	end
	if best == nil then
		return nil
	end
	if chance(brain, brain.profile.comboSkill) then
		return best.step
	end
	return candidates[Rng.integer(brain.rng, 1, #candidates)].step
end

local function startPlan(brain: Brain, plan: { PlanStep })
	brain.plan = plan
	brain.planIndex = 0
end

----------------------------------------------------------------------------------------------
-- Решения, общие для состояний
----------------------------------------------------------------------------------------------

-- Заметил атаку противника → блок? Возвращает имя следующего состояния.
local function reactToThreat(brain: Brain): string?
	local phase, remaining, move = opponentAttackPhase(brain)
	if phase ~= "Threat" or move == nil then
		return nil
	end
	local seen = brain.seen
	local key = seen.frame - seen.moveFrame
	if key == brain.lastAttackKey then
		return nil -- по этой атаке уже решили
	end
	if brain.dist > opponentReach(brain, seen.move :: string) + math.abs(seen.vx) * remaining / TICK then
		return nil -- не достанет
	end
	brain.lastAttackKey = key
	local profile = brain.profile
	-- Стойка контратаки успевает, если до удара противника ещё есть время (и это не захват).
	local mine = Specials.behaviour(brain.me, "Special")
	local untilHit = move.startup - (seen.moveFrame + profile.reactionFrames)
	if
		mine
		and mine.kind == "Counter"
		and canAct(brain.me)
		and brain.me.specialCooldown == 0
		and move.guard ~= "Unblockable"
		and untilHit > mine.move.startup + 1
		and chance(brain, profile.punishChance * 0.9)
	then
		startPlan(brain, { { button = "Special" } })
		return "Attack"
	end
	-- Контр-супер: неуязвим на старте, поэтому перебивает атаку.
	if superReady(brain.me) and canAct(brain.me) and chance(brain, profile.superUsage * 0.35) then
		startPlan(brain, { { button = "Super" } })
		return "Attack"
	end
	if not chance(brain, profile.blockChance * (1 - profile.mistakeChance)) then
		return nil
	end
	local correct = chance(brain, profile.guardRead)
	local low: boolean
	if move.guard == "Low" then
		low = correct
	elseif move.guard == "Overhead" then
		low = not correct
	else
		low = brain.guardLow
	end
	brain.guardLow = low
	return "Defend"
end

-- Есть ли у бойца готовая стойка-контратака.
local function hasCounter(brain: Brain): boolean
	local behaviour = Specials.behaviour(brain.me, "Special")
	return behaviour ~= nil and behaviour.kind == "Counter" and brain.me.specialCooldown == 0 and canAct(brain.me)
end

-- Противник в восстановлении после промаха — наказать?
local function reactToWhiff(brain: Brain): string?
	local phase = opponentAttackPhase(brain)
	if phase ~= "Recovery" or not canAct(brain.me) then
		return nil
	end
	local seen = brain.seen
	local key = -(seen.frame - seen.moveFrame)
	if key == brain.lastAttackKey then
		return nil
	end
	brain.lastAttackKey = key
	if not chance(brain, brain.profile.punishChance) then
		return nil
	end
	return "Punish"
end

-- Противник идёт навстречу и вот-вот войдёт в дальность нашего удара — встретить ударом.
local function reactToApproach(brain: Brain): string?
	local seen = brain.seen
	if not canAct(brain.me) or seen.state ~= "Walk" or seen.vx * brain.dir >= -1 then
		brain.approachHandled = false
		return nil
	end
	if brain.approachHandled then
		return nil
	end
	local starter = chooseStarter(brain, nil, false)
	if starter == nil then
		return nil
	end
	brain.approachHandled = true
	if not chance(brain, brain.profile.punishChance * 0.8) then
		return nil
	end
	startPlan(brain, extendPlan(brain, starter))
	return "Attack"
end

-- Летит снаряд противника → блок (или прыжок через низкую волну).
local function reactToProjectile(brain: Brain): string?
	local me = brain.me
	if not canAct(me) then
		return nil
	end
	local profile = brain.profile
	local lag = profile.reactionFrames / TICK
	for _, projectile in brain.sim.projectiles do
		if projectile.owner ~= me.slot and projectile.kind ~= "Mine" and projectile.id ~= brain.lastProjectile then
			-- Снаряд тоже виден с задержкой реакции.
			local seenX = projectile.x - projectile.vx * lag
			local approaching = (me.x - seenX) * projectile.vx > 0
			local speed = math.abs(projectile.vx)
			local frames = if speed > 0
				then (math.abs(me.x - seenX) - 1.5) / speed * TICK - profile.reactionFrames
				else 0
			if approaching and frames < 30 then
				brain.lastProjectile = projectile.id
				if projectile.kind == "Wave" and chance(brain, profile.jumpChance + profile.readChance * 0.5) then
					return "JumpIn"
				end
				if chance(brain, profile.blockChance) then
					local correct = chance(brain, profile.guardRead)
					local low = projectile.move.guard == "Low"
					brain.guardLow = if correct then low else not low
					return "Defend"
				end
				return nil
			end
		end
	end
	return nil
end

-- Противник прыгнул → сбивать?
local function reactToJump(brain: Brain): string?
	local seen = brain.seen
	if not seen.airborne or seen.state == "Juggle" then
		if not seen.airborne then
			brain.lastJumpHandled = false
		end
		return nil
	end
	if brain.lastJumpHandled or not canAct(brain.me) then
		return nil
	end
	brain.lastJumpHandled = true
	local approaching = seen.vx * brain.dir < 0 or brain.dist < 5
	if not approaching then
		return nil
	end
	if chance(brain, brain.profile.antiAirChance) then
		return "AntiAir"
	end
	-- Не сбил — хотя бы блок стоя (атаки в прыжке — «сверху»).
	if chance(brain, brain.profile.blockChance * 0.8) then
		brain.guardLow = false
		return "Defend"
	end
	return nil
end

----------------------------------------------------------------------------------------------
-- Состояния
----------------------------------------------------------------------------------------------

local states: { [string]: StateMachine.State<Brain> } = {}

-- Выбор действия в нейтрали.
local function decide(brain: Brain): string?
	local profile = brain.profile
	local me = brain.me
	local dist = brain.dist
	local seen = brain.seen
	local cornered = math.abs(me.x) > WALL - 2.5 and me.x * brain.dir < 0

	brain.intent = "Idle"
	brain.cautious = chance(brain, profile.blockChance * (1 - profile.aggression * 0.5))
	brain.anticipateJump = profile.readChance > 0
		and jumpRate(brain.habits) > 0.15
		and chance(brain, profile.readChance)

	-- Ошибка: случайное действие не к месту.
	if chance(brain, profile.mistakeChance * 0.4) then
		local roll = Rng.next(brain.rng)
		if roll < 0.5 then
			startPlan(brain, { { button = if roll < 0.25 then "Light" else "Heavy" } })
			return "Attack"
		elseif roll < 0.7 then
			return "JumpIn"
		end
		brain.intent = "Forward"
		return nil
	end

	-- Полная шкала и противник рядом в нейтрали — иногда супер «в лоб».
	if superReady(me) and wouldHit(brain, "Super") and chance(brain, profile.superUsage * 0.15) then
		startPlan(brain, { { button = "Super" } })
		return "Attack"
	end

	-- Противник часто атакует вблизи — «прочитал» натиск: держит блок и ждёт ошибки.
	local pressure = pressureRate(brain.habits)
	if dist < opponentReach(brain, "Heavy") and pressure > 0.6 then
		local readIt = math.min(1, pressure / 2) * (profile.readChance * 0.7 + profile.blockChance * 0.5)
		if chance(brain, readIt) then
			-- Боец со стойкой-контратакой отвечает на «прочитанный» натиск стойкой.
			if hasCounter(brain) and chance(brain, 0.35) then
				startPlan(brain, { { button = "Special" } })
				return "Attack"
			end
			brain.guardLow = chance(brain, lowRatio(brain.habits) * (0.5 + profile.readChance))
			brain.guardHold = profile.thinkInterval * 2
			return "Defend"
		end
	end

	-- Атака, если что-то достаёт.
	if canAct(me) and chance(brain, 0.25 + profile.aggression * 0.6) then
		local preferLow = profile.readChance > 0
			and brain.habits.attacks > 0
			and chance(brain, profile.readChance * 0.5)
		local starter = chooseStarter(brain, nil, preferLow)
		if starter then
			startPlan(brain, extendPlan(brain, starter))
			return "Attack"
		end
	end

	-- Особый приём с дистанции.
	if me.specialCooldown == 0 and chance(brain, profile.specialChance) and wouldHit(brain, "Special") then
		startPlan(brain, extendPlan(brain, { button = "Special" }))
		return "Attack"
	end

	-- Прыжок с атакой.
	local jumpRange = dist > 3 and dist < 9
	if jumpRange and not seen.airborne and chance(brain, profile.jumpChance * (if cornered then 2 else 1)) then
		return "JumpIn"
	end

	-- Дистанция.
	local preferred = profile.preferredRange
	if dist > preferred + 0.8 then
		if dist > 5.5 and chance(brain, profile.dashChance) then
			hold(brain, forwardBit(brain))
			press(brain, "Dash")
		end
		brain.intent = "Forward"
	elseif dist < preferred - 1 and not cornered then
		if chance(brain, profile.dashChance * 0.5) then
			hold(brain, backBit(brain))
			press(brain, "Dash")
		end
		brain.intent = "Back"
	else
		-- На своей дистанции: либо держит защиту, либо подшагивает.
		local threatRange = dist < opponentReach(brain, "Heavy") + 1
		local defensive = 1 - profile.aggression
		if threatRange and chance(brain, defensive * (0.3 + profile.readChance)) then
			brain.intent = "Guard"
			brain.guardLow = chance(brain, lowRatio(brain.habits) * profile.readChance)
		elseif chance(brain, profile.aggression) then
			brain.intent = "Forward"
		else
			brain.intent = if chance(brain, 0.3) then "Crouch" else "Idle"
		end
	end
	return nil
end

-- 2 на 2: этаж бойца и цели (0 — пол, 1 — второй этаж); nil — сцена без этажей.
local function levels(brain: Brain): (number?, number?)
	local layout = brain.sim.stage
	if #layout.platforms == 0 then
		return nil, nil
	end
	return Stage.levelOf(layout, brain.me.standY), Stage.levelOf(layout, brain.seen.standY)
end

-- Нужно ли идти на этаж цели: цель стоит на другом этаже.
local function needsTravel(brain: Brain): boolean
	local mine, theirs = levels(brain)
	return mine ~= nil and theirs ~= nil and mine ~= theirs and not brain.seen.airborne and canAct(brain.me)
end

states.Travel = {
	update = function(brain: Brain): string?
		local me = brain.me
		local layout = brain.sim.stage
		local hole = Stage.holeCenter(layout)
		local mine, theirs = levels(brain)
		if DISABLED[me.state] then
			return "Recover"
		end
		if hole == nil or mine == nil or theirs == nil or brain.machine.frames > 300 then
			return "Neutral"
		end
		if mine == theirs and not Fighter.isAirborne(me) then
			return "Neutral"
		end
		-- Атакуют рядом — сначала защититься.
		local threat = reactToThreat(brain)
		if threat then
			return threat
		end
		local toHole = hole - me.x
		local toTarget = if brain.seen.x >= hole then 1 else -1
		if mine == 0 and theirs == 1 then
			-- Наверх: к дыре, прыжок, у вершины — двойной прыжок, затем в сторону цели на платформу.
			if not Fighter.isAirborne(me) then
				if math.abs(toHole) > 1 then
					hold(brain, if toHole > 0 then InputBits.Right else InputBits.Left)
				elseif canAct(me) then
					hold(brain, InputBits.Up)
				end
			else
				local platformTop = 0
				for _, platform in layout.platforms do
					platformTop = math.max(platformTop, platform.top)
				end
				local above = me.y > platformTop + 0.3
				if not above and me.vy < 10 and me.airJumps > 0 then
					-- «Вверх» нужно нажать заново: если держали — отпускаем на кадр.
					if not brain.upHeldLastFrame then
						hold(brain, InputBits.Up)
					end
				end
				if above then
					hold(brain, if toTarget > 0 then InputBits.Right else InputBits.Left)
				elseif math.abs(toHole) > 0.5 then
					hold(brain, if toHole > 0 then InputBits.Right else InputBits.Left)
				end
			end
		elseif mine == 1 and theirs == 0 then
			-- Вниз: идём к дыре и спрыгиваем.
			hold(brain, if toHole > 0 then InputBits.Right else InputBits.Left)
		end
		return nil
	end,
}

-- Внутренний край платформы под бойцом (у дыры) и направление к дыре; nil — боец не на платформе.
local function innerEdge(layout: Stage.Layout, x: number): (number?, number)
	for _, platform in layout.platforms do
		if x >= platform.left and x <= platform.right then
			if math.abs(platform.right) < math.abs(platform.left) then
				return platform.right, 1
			end
			return platform.left, -1
		end
	end
	return nil, 0
end

local EDGE_MARGIN = 0.9 -- с какого расстояния до края начинать прыжок через дыру
local HORIZONTAL = bit32.bor(InputBits.Left, InputBits.Right)

--[[
	2 на 2: поведение у края второго этажа (поверх решения автомата).
	  • цель на этом же этаже, но на другой платформе — перепрыгиваем дыру (прыжок, у вершины двойной);
	  • цель внизу — спрыгнуть можно (этим пользуется Travel);
	  • иначе к краю не подходим и не делаем туда рывок, чтобы не свалиться случайно.
]]
local function guardLedge(brain: Brain)
	local me = brain.me
	local layout = brain.sim.stage
	if #layout.platforms == 0 then
		return
	end
	if brain.crossing ~= 0 then
		brain.crossFrames += 1
		local airborne = Fighter.isAirborne(me) or me.state == "PreJump"
		if (not airborne and brain.crossFrames > 6) or brain.crossFrames > 150 or DISABLED[me.state] then
			brain.crossing = 0
		else
			local direction = brain.crossing
			local held = bit32.band(brain.held, bit32.bnot(bit32.bor(HORIZONTAL, InputBits.Up, InputBits.Down)))
			held = bit32.bor(held, if direction > 0 then InputBits.Right else InputBits.Left)
			-- Прыжок, а у вершины — двойной прыжок, пока не долетели до платформы.
			local doubleJump = me.state == "Air"
				and me.vy <= 2
				and me.airJumps > 0
				and not brain.upHeldLastFrame
				and (brain.crossLanding - me.x) * direction > 0
			if brain.crossFrames <= 4 or doubleJump then
				held = bit32.bor(held, InputBits.Up)
			end
			brain.held = held
			return
		end
	end
	local _, theirs = levels(brain)
	local hole = Stage.holeCenter(layout)
	if me.state == "Air" and theirs == 1 and hole ~= nil then
		-- Падаем в дыру, а цель наверху (прыжок-атака не долетел, отбросило ударом) — «спасение»:
		-- двойной прыжок и тянемся к платформе цели.
		local halfHole = 0
		for _, platform in layout.platforms do
			if platform.left >= hole then
				halfHole = platform.left - hole
			end
		end
		if math.abs(me.x - hole) <= halfHole + 0.5 and me.y >= 4 and me.vy <= 0 then
			local side = if brain.seen.x >= hole then 1 else -1
			local held = bit32.band(brain.held, bit32.bnot(bit32.bor(HORIZONTAL, InputBits.Down, InputBits.Up)))
			held = bit32.bor(held, if side > 0 then InputBits.Right else InputBits.Left)
			if me.airJumps > 0 and not brain.upHeldLastFrame and me.y < 11 then
				held = bit32.bor(held, InputBits.Up)
			end
			brain.held = held
			return
		end
	end
	if Fighter.isAirborne(me) or not canAct(me) or Stage.levelOf(layout, me.floorY) == 0 then
		return
	end
	local edge, toward = innerEdge(layout, me.x)
	if edge == nil then
		return
	end
	local dashing = InputBits.has(brain.pressed, InputBits.Dash) and me.facing == toward
	if InputBits.horizontal(brain.held) ~= toward and not dashing then
		return
	end
	local distance = math.abs(edge - me.x)
	if distance > (if dashing then Physics.DashDistance + EDGE_MARGIN else EDGE_MARGIN) then
		return
	end
	if theirs == 0 then
		return -- цель внизу: спрыгиваем в дыру
	end
	brain.pressed = bit32.band(brain.pressed, bit32.bnot(InputBits.Dash))
	if theirs == 1 and hole ~= nil and (brain.seen.x - edge) * toward > 0 and distance <= EDGE_MARGIN then
		brain.crossing = toward
		brain.crossFrames = 0
		brain.crossLanding = 2 * hole - edge + toward
		brain.held = bit32.bor(
			bit32.band(brain.held, bit32.bnot(HORIZONTAL)),
			InputBits.Up,
			if toward > 0 then InputBits.Right else InputBits.Left
		)
	else
		brain.held = bit32.band(brain.held, bit32.bnot(HORIZONTAL))
	end
end

states.Neutral = {
	enter = function(brain: Brain)
		brain.decisionTimer = 0
		brain.intent = "Idle"
	end,
	update = function(brain: Brain): string?
		local profile = brain.profile
		if needsTravel(brain) then
			return "Travel"
		end
		local reaction = reactToThreat(brain)
			or reactToProjectile(brain)
			or reactToWhiff(brain)
			or reactToJump(brain)
			or reactToApproach(brain)
		if reaction then
			return reaction
		end
		-- «Прочитал» прыжок: реагирует на реальное начало прыжка без задержки.
		if brain.anticipateJump and not brain.lastJumpHandled then
			local actual = Simulation.opponentOf(brain.sim, brain.me)
			if actual.state == "PreJump" and canAct(brain.me) then
				brain.lastJumpHandled = true
				return "AntiAir"
			end
		end

		brain.decisionTimer -= 1
		if brain.decisionTimer <= 0 and canAct(brain.me) then
			local interval = profile.thinkInterval
			brain.decisionTimer = interval + Rng.integer(brain.rng, -math.floor(interval / 3), math.floor(interval / 3))
			local nextState = decide(brain)
			if nextState then
				return nextState
			end
		end

		local intent = brain.intent
		if intent == "Forward" then
			-- Осторожный боец не входит в дальность ударов противника «просто так»,
			-- а останавливается на её границе и ждёт промаха (футсис).
			local edge = opponentReach(brain, "Heavy") + 0.3
			if brain.dist < 2.3 or (brain.cautious and brain.dist < edge) then
				brain.intent = "Idle"
			else
				hold(brain, forwardBit(brain))
			end
		elseif intent == "Back" then
			hold(brain, backBit(brain))
		elseif intent == "Guard" then
			guard(brain, brain.guardLow)
		elseif intent == "Crouch" then
			hold(brain, InputBits.Down)
		end
		return nil
	end,
}

states.Defend = {
	enter = function(brain: Brain)
		brain.calmFrames = 0
		-- «Читает» продолжение натиска — держит блок дольше.
		brain.patience = math.max(brain.guardHold, 4 + (if chance(brain, brain.profile.readChance) then 10 else 0))
		brain.guardHold = 0
		brain.punishWindow = 0
	end,
	update = function(brain: Brain): string?
		local me = brain.me
		local profile = brain.profile
		if me.state == "Hitstun" or DISABLED[me.state] then
			return "Recover"
		end
		-- Новая атака в той же серии: пересмотреть стойку.
		local phase, _, move = opponentAttackPhase(brain)
		local seen = brain.seen
		if phase == "Threat" and move then
			local key = seen.frame - seen.moveFrame
			if key ~= brain.lastAttackKey then
				brain.lastAttackKey = key
				local correct = chance(brain, profile.guardRead)
				if move.guard == "Low" then
					brain.guardLow = correct
				elseif move.guard == "Overhead" then
					brain.guardLow = not correct
				end
			end
		end
		if seen.airborne then
			brain.guardLow = false
		end
		guard(brain, brain.guardLow)

		if me.state == "Blockstun" then
			brain.calmFrames = 0
			-- Блок «чувствуется» сразу: зная фреймдату, боец понимает, насколько противник открыт.
			local opponent = Simulation.opponentOf(brain.sim, me)
			local blockedMove = if opponent.state == "Attack" and opponent.move
				then MoveBook.get(opponent.characterId, opponent.move :: string)
				else nil
			brain.punishWindow = if blockedMove
				then MoveBook.totalFrames(blockedMove) - opponent.moveFrame - me.stun
				else 0
			return nil
		end
		-- Сразу после блокстана: противник небезопасен — наказать, не дожидаясь реакции;
		-- иначе иногда «перебить» продолжение натиска самым быстрым ударом.
		if brain.punishWindow ~= 0 and canAct(me) then
			local window = brain.punishWindow
			brain.punishWindow = 0
			if window >= 4 and chance(brain, profile.punishChance) then
				local starter = chooseStarter(brain, window - 1, false)
				if starter then
					startPlan(brain, extendPlan(brain, starter))
					return "Attack"
				end
			elseif
				window >= -2
				and hasCounter(brain)
				and brain.dist < opponentReach(brain, "Light2")
				and chance(brain, profile.readChance * 0.4)
			then
				-- После блока противник часто продолжает натиск — встречаем стойкой.
				startPlan(brain, { { button = "Special" } })
				return "Attack"
			elseif window >= -2 and chance(brain, profile.aggression * 0.3 + profile.comboSkill * 0.2) then
				local starter = chooseStarter(brain, 6, false)
				if starter then
					startPlan(brain, extendPlan(brain, starter))
					return "Attack"
				end
			end
		end
		-- Противник открылся после заблокированной атаки — наказать.
		if phase == "Recovery" and canAct(me) then
			local punish = reactToWhiff(brain)
			if punish then
				return punish
			end
		end
		if phase == "Threat" then
			brain.calmFrames = 0
			return nil
		end
		brain.calmFrames += 1
		if brain.calmFrames > brain.patience then
			return "Neutral"
		end
		return nil
	end,
}

states.Punish = {
	update = function(brain: Brain): string?
		local _, remaining = opponentAttackPhase(brain)
		local me = brain.me
		-- Супер — лучшее наказание, если шкала полная и достаёт.
		if superReady(me) and chance(brain, brain.profile.superUsage) and wouldHit(brain, "Super") then
			startPlan(brain, { { button = "Super" } })
			return "Attack"
		end
		local starter = chooseStarter(brain, math.max(3, remaining - 1), false)
		if starter == nil then
			-- Не достаёт: подойти ближе, если успеем.
			brain.intent = "Forward"
			return "Neutral"
		end
		startPlan(brain, extendPlan(brain, starter))
		return "Attack"
	end,
}

states.Attack = {
	enter = function(brain: Brain)
		brain.planIndex = 0
		brain.connectedSince = -1
		brain.planPressedAt = 0
		brain.wasBlocked = false
	end,
	update = function(brain: Brain): string?
		local me = brain.me
		local machine = brain.machine
		local plan = brain.plan
		local profile = brain.profile
		if me.state == "Hitstun" or DISABLED[me.state] then
			return "Recover"
		end

		-- Первый шаг: нажать, как только можем действовать.
		if brain.planIndex == 0 then
			local first = plan[1]
			if first == nil then
				return "Neutral"
			end
			if first.down then
				hold(brain, InputBits.Down)
			end
			if first.button == "Super" and not superReady(me) then
				return "Neutral"
			end
			if canAct(me) or me.state == "Landing" or me.state == "Dash" then
				press(brain, first.button)
				brain.planIndex = 1
				brain.planPressedAt = machine.frames
			elseif machine.frames > 20 then
				return "Neutral"
			end
			return nil
		end

		local step = plan[brain.planIndex]
		if step and step.down then
			hold(brain, InputBits.Down)
		end

		if me.state ~= "Attack" then
			-- Приём ещё не начался (буфер) или уже закончился.
			if machine.frames - brain.planPressedAt > 6 then
				-- Серию заблокировали — теперь мы в невыгодном положении: защищаемся.
				if brain.wasBlocked and chance(brain, profile.blockChance) then
					brain.guardLow = false
					return "Defend"
				end
				return "Neutral"
			end
			return nil
		end

		local nextStep = plan[brain.planIndex + 1]
		if nextStep == nil then
			return nil -- доигрываем последний удар
		end
		if nextStep.down then
			hold(brain, InputBits.Down)
		end

		if me.moveConnected then
			if brain.connectedSince < 0 then
				brain.connectedSince = machine.frames
				-- Задержка связки: у мастеров — пара кадров, у новичков — может не успеть.
				local sloppy = (1 - profile.comboSkill) * 14 + (if chance(brain, profile.mistakeChance) then 10 else 0)
				brain.linkDelay = Rng.integer(brain.rng, 0, math.floor(sloppy + 0.5))
				-- Проверка попадания: по блоку опытный боец не продолжает рискованную серию.
				local opponent = Simulation.opponentOf(brain.sim, me)
				local blocked = opponent.state == "Blockstun"
				brain.wasBlocked = blocked
				local continueChance = 0.3 + 0.7 * profile.comboSkill
				if blocked and chance(brain, profile.comboSkill) then
					continueChance = if nextStep.button == "Light" then 0.6 else 0.1
				end
				if not chance(brain, continueChance) then
					brain.plan = table.move(plan, 1, brain.planIndex, 1, {})
					return nil
				end
			end
			if machine.frames - brain.connectedSince >= brain.linkDelay then
				if nextStep.button == "Super" and not superReady(me) then
					brain.plan = table.move(plan, 1, brain.planIndex, 1, {})
					return nil
				end
				press(brain, nextStep.button)
				brain.planIndex += 1
				brain.connectedSince = -1
				brain.planPressedAt = machine.frames
			end
		end
		if machine.frames > 180 then
			return "Neutral"
		end
		return nil
	end,
}

states.AntiAir = {
	enter = function(brain: Brain)
		brain.antiAirMove = if wouldHit(brain, "Special") and chance(brain, 0.5) then "Special" else "Heavy"
	end,
	update = function(brain: Brain): string?
		local me = brain.me
		local seen = brain.seen
		if DISABLED[me.state] or me.state == "Blockstun" then
			return if me.state == "Blockstun" then "Defend" else "Recover"
		end
		if not seen.airborne and brain.machine.frames > 2 then
			return "Neutral"
		end
		if brain.machine.frames > 70 then
			return "Neutral"
		end
		if not canAct(me) then
			return nil
		end
		for _, id in { brain.antiAirMove, "Heavy", "Light1" } do
			if (id ~= "Special" or me.specialCooldown == 0) and wouldHit(brain, id) then
				local button = if id == "Light1" then "Light" elseif id == "Special" then "Special" else "Heavy"
				startPlan(brain, extendPlan(brain, { button = button :: any }))
				return "Attack"
			end
		end
		-- Ждём момента, держа блок стоя.
		guard(brain, false)
		return nil
	end,
}

-- 2 на 2: прыжок вперёд со второго этажа не должен кончиться падением в дыру.
local function jumpLandsSafely(brain: Brain, direction: number): boolean
	local me = brain.me
	local layout = brain.sim.stage
	if #layout.platforms == 0 or Stage.levelOf(layout, me.standY) == 0 then
		return true
	end
	local airTime = 2 * Physics.JumpVelocity / Physics.Gravity
	local landX = me.x + direction * me.stats.walkSpeed * Physics.JumpForwardSpeedFactor * airTime
	return Stage.floorBelow(layout, landX, me.standY) >= me.standY - 0.01
end

states.JumpIn = {
	enter = function(brain: Brain)
		brain.jumpPressed = false
	end,
	update = function(brain: Brain): string?
		local me = brain.me
		local machine = brain.machine
		if DISABLED[me.state] then
			return "Recover"
		end
		if machine.frames == 0 and not jumpLandsSafely(brain, brain.dir) then
			return "Neutral"
		end
		if machine.frames < 4 then
			if canAct(me) or me.state == "PreJump" then
				hold(brain, bit32.bor(InputBits.Up, forwardBit(brain)))
			end
			return nil
		end
		if me.state == "Air" and not brain.jumpPressed then
			for _, id in { "AirHeavy", "AirLight" } do
				if wouldHit(brain, id) then
					press(brain, if id == "AirHeavy" then "Heavy" else "Light")
					brain.jumpPressed = true
					break
				end
			end
			return nil
		end
		if me.state == "Air" or me.state == "PreJump" or (me.state == "Attack" and Fighter.isAirborne(me)) then
			return nil
		end
		-- Приземлились: если атака попала — продолжить комбо.
		local opponent = Simulation.opponentOf(brain.sim, me)
		if
			brain.jumpPressed
			and opponent.state == "Hitstun"
			and chance(brain, 0.3 + 0.7 * brain.profile.comboSkill)
		then
			local starter = chooseStarter(brain, nil, false)
			if starter then
				startPlan(brain, extendPlan(brain, starter))
				return "Attack"
			end
		end
		if me.state == "Landing" then
			return nil
		end
		return "Neutral"
	end,
}

states.Recover = {
	enter = function(brain: Brain)
		brain.reversalTried = false
		brain.recoverGuard = chance(brain, brain.profile.blockChance)
	end,
	update = function(brain: Brain): string?
		local me = brain.me
		local profile = brain.profile
		local state = me.state
		if state == "Blockstun" then
			return "Defend"
		end
		if canAct(me) then
			-- Держал «назад» в оглушении — продолжает защищаться, пока противник рядом.
			return if brain.recoverGuard and brain.dist < 5 then "Defend" else "Neutral"
		end
		if state == "Intro" or state == "Win" or state == "Lose" or state == "KO" then
			return nil
		end
		-- Встаём: защита при вставании или контр-супер (неуязвим на старте).
		if state == "WakeUp" and me.stun <= 3 and not brain.reversalTried then
			brain.reversalTried = true
			if superReady(me) and brain.dist < 5 and chance(brain, profile.superUsage * 0.5) then
				startPlan(brain, { { button = "Super" } })
				return "Attack"
			end
			brain.guardLow = chance(brain, lowRatio(brain.habits))
		end
		-- Держать «назад» во время оглушения: если серия противника прервётся — сразу блок.
		if brain.recoverGuard or brain.reversalTried then
			guard(brain, brain.guardLow)
		end
		return nil
	end,
}

----------------------------------------------------------------------------------------------
-- Публичный интерфейс
----------------------------------------------------------------------------------------------

function BossAI.new(profile: AiProfile, seed: number): Brain
	local history: { Observation } = {}
	for index = 1, HISTORY do
		history[index] = newObservation()
	end
	local brain: Brain = {
		profile = profile,
		rng = Rng.new(seed),
		slot = 0,
		machine = nil :: any,
		history = history,
		recorded = 0,
		habits = { attacks = 0, nearAttacks = 0, nearFrames = 0, lows = 0, overheads = 0, jumps = 0, neutralFrames = 0 },
		lastSeenState = "Idle",
		lastAttackKey = -1,
		lastJumpHandled = false,
		sim = nil :: any,
		me = nil :: any,
		seen = history[1],
		dir = 1,
		dist = 0,
		held = 0,
		pressed = 0,
		decisionTimer = 0,
		intent = "Idle",
		guardLow = false,
		calmFrames = 0,
		patience = 4,
		guardHold = 0,
		cautious = false,
		approachHandled = false,
		lastProjectile = -1,
		targetSlot = 0,
		upHeldLastFrame = false,
		crossing = 0,
		crossFrames = 0,
		crossLanding = 0,
		punishWindow = 0,
		wasBlocked = false,
		anticipateJump = false,
		plan = {},
		planIndex = 0,
		planPressedAt = 0,
		linkDelay = 0,
		connectedSince = -1,
		antiAirMove = "Heavy",
		jumpPressed = false,
		reversalTried = false,
		recoverGuard = false,
		seenKey = -1,
		characterId = "",
		moveCache = {},
	}
	brain.machine = StateMachine.new(states, "Neutral", brain)
	return brain
end

-- Текущее состояние автомата (для отладки и тестов).
function BossAI.stateOf(brain: Brain): string
	return brain.machine.current
end

-- Ввод ИИ на этот кадр.
function BossAI.think(brain: Brain, sim: Sim, slot: number): FrameInput
	local me = sim.fighters[slot]
	local opponent = Simulation.opponentOf(sim, me)
	brain.slot = slot
	brain.sim = sim
	brain.me = me
	if opponent == me then
		return InputBits.empty() -- противников нет
	end
	if opponent.slot ~= brain.targetSlot then
		-- Новая цель (2 на 2): наблюдения за прежней не годятся.
		brain.targetSlot = opponent.slot
		brain.recorded = 0
	end

	if not sim.inputEnabled then
		-- Заставка раунда: забыть позиции прошлого раунда (привычки помним).
		brain.recorded = 0
		if brain.machine.current ~= "Neutral" then
			StateMachine.transition(brain.machine, "Neutral")
		end
		return InputBits.empty()
	end

	record(brain, opponent, sim.frame)
	local seen = recall(brain, brain.profile.reactionFrames)
	brain.seen = seen
	local dx = seen.x - me.x
	brain.dir = if dx > 0.05 then 1 elseif dx < -0.05 then -1 else me.facing
	brain.dist = math.abs(dx)
	brain.held = 0
	brain.pressed = 0
	updateHabits(brain)

	local current = brain.machine.current
	if DISABLED[me.state] and current ~= "Recover" and current ~= "Attack" then
		StateMachine.transition(brain.machine, "Recover")
	end
	StateMachine.step(brain.machine)
	guardLedge(brain)
	brain.upHeldLastFrame = InputBits.has(brain.held, InputBits.Up)
	return { held = brain.held, pressed = brain.pressed }
end

-- Функция ввода для контроллера слота в матче.
function BossAI.controller(profile: AiProfile, seed: number): (sim: Sim, slot: number) -> FrameInput
	local brain = BossAI.new(profile, seed)
	return function(sim: Sim, slot: number): FrameInput
		return BossAI.think(brain, sim, slot)
	end
end

return BossAI
