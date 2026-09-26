--!strict
--[[
	Детерминированная симуляция поединка 1 на 1 с фиксированным шагом (GameConfig.TickRate).
	Чистый Luau без Roblox API: одна и та же симуляция работает на сервере (авторитетно)
	и в тестах. Сервер вызывает Simulation.step() 60 раз в секунду, подавая ввод игроков/ИИ.

	Порядок кадра:
	  1. ввод (буфер нажатий, двойное нажатие для рывка);
	  2. вспышка супера или кинематографичная серия — если идут, всё остальное стоит;
	  3. логика состояний: движение, атаки и отмены, оглушение, нокдаун (кроме бойцов в хитстопе);
	  4. интеграция позиций, отбрасывание, приземление;
	  5. раздвигание бойцов, границы арены (у стены отбрасывает атакующего), максимальная дистанция;
	  6. поворот к противнику;
	  7. попадания: хитбоксы против хартбоксов (с компенсацией пинга), блок, урон, реакция.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local CharacterRegistry = require(script.Parent.Parent.Characters.CharacterRegistry)
local Types = require(script.Parent.Parent.Types)
local InputBits = require(script.Parent.InputBits)
local Fighter = require(script.Parent.Fighter)
local MoveBook = require(script.Parent.MoveBook)
local Hitbox = require(script.Parent.Hitbox)
local SimState = require(script.Parent.SimState)
local Projectiles = require(script.Parent.Projectiles)
local Specials = require(script.Parent.Specials)

type Fighter = Fighter.Fighter
type FrameInput = InputBits.FrameInput
type MoveData = Types.MoveData

local Physics = GameConfig.Physics
local Combat = GameConfig.Combat
local TICK = GameConfig.TickRate
local DT = 1 / TICK
local METER_MAX = GameConfig.SuperMeter.Max
local PUSH_SCALE = 2 -- knockback из фреймдаты → скорость отбрасывания (студ/с)
local HISTORY_SIZE = Combat.MaxLagCompensationFrames

export type SimEvent = SimState.SimEvent
export type Cinematic = SimState.Cinematic
export type Sim = SimState.Sim

export type SimOptions = {
	characters: { string }, -- два id персонажей
	hpMultipliers: { number }?,
}

local Simulation = {}

local emitAt = SimState.emitAt
local emit = SimState.emit

function Simulation.new(options: SimOptions): Sim
	assert(#options.characters == 2, "Симуляция рассчитана на двух бойцов")
	local multipliers = options.hpMultipliers or { 1, 1 }
	local sim: Sim = {
		frame = 0,
		fighters = {
			Fighter.new(1, options.characters[1], multipliers[1]),
			Fighter.new(2, options.characters[2], multipliers[2]),
		},
		inputEnabled = true,
		events = {},
		freeze = 0,
		freezeOwner = 0,
		cinematic = nil,
		projectiles = {},
		nextProjectileId = 0,
	}
	Simulation.resetPositions(sim)
	return sim
end

-- Сбросить боевое состояние бойца (начало раунда, выход нового бойца).
local function resetCombatState(fighter: Fighter)
	fighter.move = nil
	fighter.moveFrame = 0
	fighter.moveConnected = false
	fighter.moveHits = 0
	fighter.airAttackUsed = false
	fighter.specialCooldown = 0
	fighter.armor = 0
	fighter.stun = 0
	fighter.hitstop = 0
	fighter.push = 0
	fighter.comboHits = 0
	fighter.comboDamage = 0
	fighter.juggleHits = 0
	fighter.knockdownOnLand = false
	fighter.ko = false
	table.clear(fighter.history)
end

-- Расставить бойцов на стартовые позиции (начало раунда). HP и шкалу не трогает.
function Simulation.resetPositions(sim: Sim)
	local half = Physics.StartDistance / 2
	sim.freeze = 0
	sim.cinematic = nil
	table.clear(sim.projectiles)
	for _, fighter in sim.fighters do
		fighter.x = if fighter.slot == 1 then -half else half
		fighter.y = 0
		fighter.vx = 0
		fighter.vy = 0
		fighter.facing = if fighter.slot == 1 then 1 else -1
		fighter.buffer = {}
		fighter.dashRequest = 0
		fighter.dashRequestFrames = 0
		fighter.invulnerable = 0
		resetCombatState(fighter)
		Fighter.setState(fighter, "Idle")
	end
end

-- Полностью восстановить HP (новый раунд).
function Simulation.restoreHealth(sim: Sim)
	for _, fighter in sim.fighters do
		fighter.health = fighter.maxHealth
	end
end

-- Заменить бойца в слоте (эстафета 2 на 2): новый боец выходит на позицию старого.
function Simulation.replaceFighter(sim: Sim, slot: number, characterId: string, hpMultiplier: number?): Fighter
	local old = sim.fighters[slot]
	local fighter = Fighter.new(slot, characterId, hpMultiplier)
	fighter.x = old.x
	fighter.facing = old.facing
	fighter.lagFrames = old.lagFrames
	fighter.tapDash = old.tapDash
	sim.fighters[slot] = fighter
	return fighter
end

function Simulation.opponentOf(sim: Sim, fighter: Fighter): Fighter
	return SimState.opponentOf(sim, fighter)
end

-- Компенсация пинга для атак бойца в слоте (сервер вызывает по пингу игрока; у ИИ — 0).
function Simulation.setLagFrames(sim: Sim, slot: number, frames: number)
	sim.fighters[slot].lagFrames = math.clamp(math.floor(frames), 0, Combat.MaxLagCompensationFrames)
end

-- Идёт ли «пауза» боя (вспышка супера или ролик) — таймер раунда в это время стоит.
function Simulation.isPaused(sim: Sim): boolean
	return sim.freeze > 0 or sim.cinematic ~= nil
end

local function gainMeter(fighter: Fighter, amount: number)
	if amount <= 0 or fighter.ko then
		return
	end
	local gain = amount * fighter.stats.superGainMultiplier * fighter.modifiers.meterGain
	fighter.meter = math.min(METER_MAX, fighter.meter + gain)
end

-- Множитель урона от модификаторов бойцов (механики боссов). firstHit — учитывать «железную кожу».
local function modifierScale(attacker: Fighter, defender: Fighter, firstHit: boolean): number
	local scale = attacker.modifiers.damageDealt * defender.modifiers.damageTaken
	if firstHit and defender.comboHits == 0 then
		scale *= defender.modifiers.firstHitTaken
	end
	return scale
end

-- Вампиризм: атакующий лечится частью нанесённого урона.
local function drainLife(attacker: Fighter, damage: number)
	local rate = attacker.modifiers.lifesteal
	if rate > 0 and damage > 0 and not attacker.ko then
		attacker.health = math.min(attacker.maxHealth, attacker.health + math.floor(damage * rate + 0.5))
	end
end

----------------------------------------------------------------------------------------------
-- Ввод
----------------------------------------------------------------------------------------------

local function processInput(sim: Sim, fighter: Fighter, input: FrameInput)
	local held = if sim.inputEnabled then InputBits.sanitize(input.held) else 0
	local pressed = if sim.inputEnabled then InputBits.sanitize(input.pressed) else 0

	fighter.prevHeld = fighter.held
	fighter.held = held

	-- Буфер: нажатие «помнится» несколько кадров, чтобы приём сработал, даже если нажали чуть раньше.
	-- Во время хитстопа/вспышки буфер не «тикает» — так удобно нажимать отмены.
	if fighter.hitstop == 0 and sim.freeze == 0 and sim.cinematic == nil then
		for bit, frames in fighter.buffer do
			if frames > 1 then
				fighter.buffer[bit] = frames - 1
			else
				fighter.buffer[bit] = nil
			end
		end
		if fighter.dashRequestFrames > 0 then
			fighter.dashRequestFrames -= 1
			if fighter.dashRequestFrames == 0 then
				fighter.dashRequest = 0
			end
		end
	end
	for _, bit in InputBits.ACTIONS do
		if InputBits.has(pressed, bit) and bit ~= InputBits.Dash then
			fighter.buffer[bit] = GameConfig.Input.BufferFrames
		end
	end

	-- Кнопка рывка: в сторону удерживаемого направления, иначе вперёд.
	if InputBits.has(pressed, InputBits.Dash) then
		local direction = InputBits.horizontal(held)
		fighter.dashRequest = if direction ~= 0 then direction else fighter.facing
		fighter.dashRequestFrames = GameConfig.Input.BufferFrames
	end

	-- Двойное нажатие направления.
	local newlyHeld = bit32.band(held, bit32.bnot(fighter.prevHeld))
	local tap = 0
	if InputBits.has(newlyHeld, InputBits.Left) and not InputBits.has(held, InputBits.Right) then
		tap = -1
	elseif InputBits.has(newlyHeld, InputBits.Right) and not InputBits.has(held, InputBits.Left) then
		tap = 1
	end
	if tap ~= 0 and fighter.tapDash and not InputBits.has(held, InputBits.Down) then
		if fighter.tapDir == tap and sim.frame - fighter.tapFrame <= Physics.DoubleTapWindow then
			fighter.dashRequest = tap
			fighter.dashRequestFrames = GameConfig.Input.BufferFrames
			fighter.tapDir = 0
		else
			fighter.tapDir = tap
			fighter.tapFrame = sim.frame
		end
	end
end

local function buffered(fighter: Fighter, bit: number): boolean
	return fighter.buffer[bit] ~= nil
end

----------------------------------------------------------------------------------------------
-- Атаки
----------------------------------------------------------------------------------------------

local groundControl: (sim: Sim, fighter: Fighter) -> ()

local function moveOf(fighter: Fighter): MoveData?
	local id = fighter.move
	if id == nil then
		return nil
	end
	return MoveBook.get(fighter.characterId, id)
end

local function startMove(sim: Sim, fighter: Fighter, id: string, button: number): boolean
	local move = MoveBook.get(fighter.characterId, id)
	if move == nil then
		return false
	end
	fighter.buffer[button] = nil
	local airborne = Fighter.isAirborne(fighter)
	Fighter.setState(fighter, "Attack")
	fighter.move = id
	fighter.moveFrame = 0
	fighter.moveConnected = false
	fighter.moveHits = 0
	if airborne then
		fighter.airAttackUsed = true
	else
		fighter.vx = 0
	end

	if id == "Super" then
		fighter.meter = 0
		sim.freeze = Combat.SuperFreezeFrames
		sim.freezeOwner = fighter.slot
		-- Неуязвим на старте супера: на вспышку можно отреагировать, но не перебить.
		fighter.invulnerable = move.startup + 1
		local def = CharacterRegistry.get(fighter.characterId)
		emit(sim, "SuperFlash", fighter, Combat.SuperFreezeFrames, nil, if def then def.super.cinematic.style else nil)
	elseif id == "Special" then
		emit(sim, "Special", fighter)
	end
	if id == "Special" or id == "Super" then
		Specials.onStart(sim, fighter, id)
		-- Кадр 0 приёма: движение (рывки, прыжки) начинается сразу.
		local behaviour = Specials.behaviour(fighter, id)
		if behaviour then
			Specials.update(sim, fighter, behaviour)
		end
	end
	return true
end

-- Следующий удар «Руки» в цепочке.
local function lightMoveFor(fighter: Fighter, crouching: boolean, airborne: boolean): string
	if airborne then
		return "AirLight"
	elseif crouching then
		return "CrouchLight"
	elseif fighter.state == "Attack" and fighter.move == "Light1" then
		return "Light2"
	elseif fighter.state == "Attack" and fighter.move == "Light2" then
		return "Light3"
	end
	return "Light1"
end

--[[
	Попробовать начать удар по буферу нажатий. allowed — ограничение (для отмен);
	nil — любой удар, доступный в текущем положении.
]]
local function tryStartAttack(sim: Sim, fighter: Fighter, allowed: { string }?): boolean
	local airborne = Fighter.isAirborne(fighter)
	local crouching = InputBits.has(fighter.held, InputBits.Down)
	local function permitted(id: string): boolean
		return allowed == nil or table.find(allowed, id) ~= nil
	end

	if
		buffered(fighter, InputBits.Super)
		and not airborne
		and fighter.meter >= METER_MAX
		and permitted("Super")
		and Specials.canStart(sim, fighter, "Super")
	then
		return startMove(sim, fighter, "Super", InputBits.Super)
	end
	if
		buffered(fighter, InputBits.Special)
		and not airborne
		and fighter.specialCooldown == 0
		and permitted("Special")
		and Specials.canStart(sim, fighter, "Special")
	then
		return startMove(sim, fighter, "Special", InputBits.Special)
	end
	if buffered(fighter, InputBits.Heavy) and not (airborne and fighter.airAttackUsed) then
		local id = if airborne then "AirHeavy" elseif crouching then "CrouchHeavy" else "Heavy"
		if permitted(id) then
			return startMove(sim, fighter, id, InputBits.Heavy)
		end
	end
	if buffered(fighter, InputBits.Light) and not (airborne and fighter.airAttackUsed) then
		local id = lightMoveFor(fighter, crouching, airborne)
		if permitted(id) then
			return startMove(sim, fighter, id, InputBits.Light)
		end
	end
	return false
end

local function finishMove(sim: Sim, fighter: Fighter)
	if fighter.move == "Special" then
		fighter.specialCooldown = Combat.SpecialCooldownFrames
	end
	fighter.move = nil
	fighter.moveConnected = false
	fighter.moveHits = 0
	fighter.armor = 0
	if Fighter.isAirborne(fighter) then
		Fighter.setState(fighter, "Air")
	else
		Fighter.setState(fighter, "Idle")
		groundControl(sim, fighter)
	end
end

local function updateAttack(sim: Sim, fighter: Fighter)
	local move = moveOf(fighter)
	if move == nil then
		finishMove(sim, fighter)
		return
	end
	fighter.moveFrame = fighter.stateFrame

	if fighter.moveFrame >= MoveBook.totalFrames(move) then
		finishMove(sim, fighter)
		return
	end

	-- Отмена в следующий удар: только после попадания/блока и в окне отмены.
	local cancelEnd = move.startup + move.active + Combat.CancelWindow
	if fighter.moveConnected and fighter.moveFrame >= move.startup and fighter.moveFrame < cancelEnd then
		local current = fighter.move :: string
		if tryStartAttack(sim, fighter, MoveBook.cancels(current)) then
			return
		end
	end

	-- Особые приёмы и суперы двигают бойца по-своему (рывки, прыжки, телепорт, снаряды).
	local behaviour = Specials.behaviour(fighter, fighter.move)
	if behaviour and Specials.update(sim, fighter, behaviour) then
		return
	end
	if Fighter.isAirborne(fighter) then
		fighter.vy -= Physics.Gravity * DT
	else
		fighter.vx = 0
	end
end

-- Угрожает ли противник ударом (для стойки блока при удержании «назад»).
local function isThreatened(sim: Sim, fighter: Fighter): boolean
	local opponent = Simulation.opponentOf(sim, fighter)
	if opponent.state ~= "Attack" then
		return false
	end
	local move = moveOf(opponent)
	if move == nil or opponent.moveFrame >= move.startup + move.active then
		return false
	end
	return math.abs(opponent.x - fighter.x) <= Combat.ProximityGuardRange
end

----------------------------------------------------------------------------------------------
-- Движение
----------------------------------------------------------------------------------------------

local function isGroundActionable(fighter: Fighter): boolean
	local state = fighter.state
	return state == "Idle" or state == "Walk" or state == "Crouch" or state == "Block"
end

-- Скорость рывка: быстрый старт и плавное торможение, суммарно ровно distance студов.
local function dashSpeed(distance: number, totalFrames: number, frame: number): number
	local duration = totalFrames / TICK
	local startSpeed = 2 * distance / duration
	return startSpeed * math.max(0, 1 - (frame + 0.5) / totalFrames)
end

local function startDash(sim: Sim, fighter: Fighter, direction: number)
	fighter.dashDir = direction
	fighter.dashRequest = 0
	fighter.dashRequestFrames = 0
	if direction == fighter.facing then
		Fighter.setState(fighter, "Dash")
		fighter.vx = direction * dashSpeed(Physics.DashDistance, Physics.DashFrames, 0)
		emit(sim, "Dash", fighter)
	else
		Fighter.setState(fighter, "Backdash")
		fighter.vx = direction * dashSpeed(Physics.BackdashDistance, Physics.BackdashFrames, 0)
		fighter.invulnerable = Physics.BackdashInvulnerableFrames
		emit(sim, "Backdash", fighter)
	end
end

function groundControl(sim: Sim, fighter: Fighter)
	if tryStartAttack(sim, fighter, nil) then
		return
	end

	local held = fighter.held
	local direction = InputBits.horizontal(held)

	if fighter.dashRequest ~= 0 then
		startDash(sim, fighter, fighter.dashRequest)
		return
	end

	if InputBits.has(held, InputBits.Up) then
		Fighter.setState(fighter, "PreJump")
		fighter.jumpDir = direction
		fighter.vx = 0
		return
	end

	-- Удержание «назад» при угрозе удара — стойка блока (стоя или сидя).
	local opponent = Simulation.opponentOf(sim, fighter)
	local away = if opponent.x > fighter.x then -1 elseif opponent.x < fighter.x then 1 else -fighter.facing
	if direction == away and isThreatened(sim, fighter) then
		if fighter.state ~= "Block" then
			Fighter.setState(fighter, "Block")
		end
		fighter.vx = 0
		return
	end

	if InputBits.has(held, InputBits.Down) then
		if fighter.state ~= "Crouch" then
			Fighter.setState(fighter, "Crouch")
		end
		fighter.vx = 0
		return
	end

	if direction ~= 0 then
		local backwards = direction ~= fighter.facing
		local speed = fighter.stats.walkSpeed * (if backwards then Physics.BackWalkFactor else 1)
		if fighter.state ~= "Walk" then
			Fighter.setState(fighter, "Walk")
		end
		fighter.vx = direction * speed
		return
	end

	if fighter.state ~= "Idle" then
		Fighter.setState(fighter, "Idle")
	end
	fighter.vx = 0
end

-- Конец комбо: боец вернулся в нейтральное положение.
local function endCombo(sim: Sim, fighter: Fighter)
	if fighter.comboHits >= 2 then
		emit(sim, "ComboEnd", fighter, fighter.comboHits, 3 - fighter.slot)
	end
	fighter.comboHits = 0
	fighter.comboDamage = 0
	fighter.juggleHits = 0
end

local function updateState(sim: Sim, fighter: Fighter)
	local state = fighter.state
	if fighter.specialCooldown > 0 then
		fighter.specialCooldown -= 1
	end

	if state == "Attack" then
		updateAttack(sim, fighter)
	elseif isGroundActionable(fighter) then
		groundControl(sim, fighter)
	elseif state == "Hitstun" or state == "Blockstun" then
		fighter.vx = 0
		fighter.stun -= 1
		if fighter.stun <= 0 then
			fighter.stun = 0
			if state == "Hitstun" then
				endCombo(sim, fighter)
			end
			Fighter.setState(fighter, "Idle")
			groundControl(sim, fighter)
		end
	elseif state == "Juggle" then
		fighter.vy -= Physics.Gravity * DT
	elseif state == "Knockdown" then
		fighter.vx = 0
		fighter.stun -= 1
		if fighter.stun <= 0 then
			Fighter.setState(fighter, "WakeUp")
			fighter.stun = Combat.WakeUpFrames
		end
	elseif state == "WakeUp" then
		fighter.vx = 0
		fighter.stun -= 1
		if fighter.stun <= 0 then
			fighter.stun = 0
			Fighter.setState(fighter, "Idle")
			groundControl(sim, fighter)
		end
	elseif state == "PreJump" then
		local direction = InputBits.horizontal(fighter.held)
		if direction ~= 0 then
			fighter.jumpDir = direction
		end
		if fighter.stateFrame >= Physics.JumpSquatFrames then
			Fighter.setState(fighter, "Air")
			fighter.airAttackUsed = false
			fighter.vy = Physics.JumpVelocity
			fighter.vx = fighter.jumpDir * fighter.stats.walkSpeed * Physics.JumpForwardSpeedFactor
			emit(sim, "Jump", fighter)
		end
	elseif state == "Air" then
		-- Удар в прыжке сохраняет инерцию; гравитация действует всегда.
		tryStartAttack(sim, fighter, nil)
		fighter.vy -= Physics.Gravity * DT
	elseif state == "Landing" then
		fighter.vx = 0
		if fighter.stateFrame >= Physics.LandingFrames then
			Fighter.setState(fighter, "Idle")
			groundControl(sim, fighter)
		end
	elseif state == "Dash" or state == "Backdash" then
		local total = if state == "Dash" then Physics.DashFrames else Physics.BackdashFrames
		local distance = if state == "Dash" then Physics.DashDistance else Physics.BackdashDistance
		if fighter.stateFrame >= total then
			fighter.vx = 0
			Fighter.setState(fighter, "Idle")
			groundControl(sim, fighter)
		else
			fighter.vx = fighter.dashDir * dashSpeed(distance, total, fighter.stateFrame)
		end
	else
		-- KO, Win, Lose, Intro, Cinematic: стоим.
		fighter.vx = 0
	end
end

local function onLand(sim: Sim, fighter: Fighter)
	fighter.y = 0
	fighter.vy = 0
	fighter.airAttackUsed = false
	local state = fighter.state
	if state == "Juggle" then
		fighter.vx = 0
		fighter.juggleHits = 0
		if fighter.ko then
			Fighter.setState(fighter, "KO")
		else
			Fighter.setState(fighter, "Knockdown")
			fighter.stun = Combat.KnockdownFrames
			endCombo(sim, fighter)
		end
		fighter.knockdownOnLand = false
		emit(sim, "Knockdown", fighter)
	elseif state == "Attack" and Specials.keepsMoveOnLand(fighter) then
		return -- удар при приземлении (прыжок-дуга): приём продолжается
	elseif state == "Air" or state == "Attack" then
		fighter.vx = 0
		fighter.move = nil
		fighter.moveConnected = false
		Fighter.setState(fighter, "Landing")
		emit(sim, "Land", fighter)
	end
end

local function integrate(sim: Sim, fighter: Fighter)
	fighter.x += (fighter.vx + fighter.push) * DT
	fighter.push *= Combat.PushFriction
	if math.abs(fighter.push) < 0.05 then
		fighter.push = 0
	end
	local state = fighter.state
	if state == "Air" or state == "Juggle" or fighter.y > 0 or fighter.vy > 0 then
		fighter.y += fighter.vy * DT
		if fighter.y <= 0 and fighter.vy <= 0 then
			onLand(sim, fighter)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Пространство: раздвигание, границы, дистанция, поворот
----------------------------------------------------------------------------------------------

local WALL = Physics.ArenaHalfWidth - Physics.PushWidth / 2

local function clampToArena(sim: Sim, fighter: Fighter)
	local clamped = math.clamp(fighter.x, -WALL, WALL)
	if clamped ~= fighter.x then
		-- Отбрасывание «в стену» переходит на атакующего: он отлетает назад.
		if fighter.push ~= 0 and math.sign(fighter.push) == math.sign(fighter.x) then
			local opponent = Simulation.opponentOf(sim, fighter)
			if opponent.state == "Attack" then
				opponent.push = -fighter.push * 0.8
			end
			fighter.push = 0
		end
		fighter.x = clamped
	end
end

local function separate(sim: Sim)
	local a, b = sim.fighters[1], sim.fighters[2]
	local aBottom, aTop = Fighter.pushExtent(a)
	local bBottom, bTop = Fighter.pushExtent(b)
	if aTop <= bBottom or bTop <= aBottom then
		return -- один над другим: можно перепрыгнуть
	end

	local dx = b.x - a.x
	local overlap = Physics.PushWidth - math.abs(dx)
	if overlap <= 0 then
		return
	end

	-- Кто левее: при совпадении — по направлению взгляда первого бойца.
	local side = if dx > 0 then 1 elseif dx < 0 then -1 else a.facing
	local aTarget = a.x - side * overlap / 2
	local bTarget = b.x + side * overlap / 2

	-- Если кто-то упёрся в стену, второй отодвигается на всё расстояние.
	if math.abs(aTarget) > WALL then
		local excess = math.abs(aTarget) - WALL
		aTarget -= math.sign(aTarget) * excess
		bTarget += side * excess
	elseif math.abs(bTarget) > WALL then
		local excess = math.abs(bTarget) - WALL
		bTarget -= math.sign(bTarget) * excess
		aTarget -= side * excess
	end
	a.x = aTarget
	b.x = bTarget
end

-- Бойцы не могут разойтись дальше MaxSeparation: «лишнее» забирается у того, кто уходит.
local function limitSeparation(sim: Sim)
	local a, b = sim.fighters[1], sim.fighters[2]
	local distance = math.abs(b.x - a.x)
	local excess = distance - Physics.MaxSeparation
	if excess <= 0 then
		return
	end
	local side = if b.x >= a.x then 1 else -1 -- направление от a к b
	local aAway = math.max(0, -side * (a.vx + a.push))
	local bAway = math.max(0, side * (b.vx + b.push))
	local total = aAway + bAway
	local aShare = if total > 0 then aAway / total else 0.5
	a.x += side * excess * aShare
	b.x -= side * excess * (1 - aShare)
end

local function canTurn(fighter: Fighter): boolean
	local state = fighter.state
	return state == "Idle"
		or state == "Walk"
		or state == "Crouch"
		or state == "Landing"
		or state == "Block"
		or state == "PreJump"
		or state == "Intro"
		or state == "WakeUp"
end

local function faceOpponent(sim: Sim)
	for _, fighter in sim.fighters do
		if canTurn(fighter) then
			local opponent = Simulation.opponentOf(sim, fighter)
			local dx = opponent.x - fighter.x
			if math.abs(dx) > 0.05 then
				fighter.facing = if dx > 0 then 1 else -1
			end
		end
	end
end

local function recordHistory(fighter: Fighter)
	local record: Fighter.HurtRecord = { x = fighter.x, y = fighter.y, kind = Fighter.hurtKind(fighter) }
	table.insert(fighter.history, 1, record)
	if #fighter.history > HISTORY_SIZE then
		table.remove(fighter.history)
	end
end

----------------------------------------------------------------------------------------------
-- Попадания
----------------------------------------------------------------------------------------------

type PendingHit = {
	attacker: Fighter,
	defender: Fighter,
	move: MoveData,
	x: number,
	y: number,
	projectile: SimState.Projectile?, -- попадание снарядом (владелец не «застывает» и не получает отмен)
}

local function hitstopFor(damage: number): number
	return math.clamp(
		math.floor(Combat.HitstopBase + damage * Combat.HitstopPerDamage),
		Combat.HitstopBase,
		Combat.HitstopMax
	)
end

local function comboScale(hitsBefore: number): number
	return math.max(Combat.ComboScalingMin, 1 - Combat.ComboScalingPerHit * hitsBefore)
end

--[[
	Точка контакта хитбокса с хартбоксом защитника или nil.
	Компенсация пинга: если нет попадания по текущему положению, проверяются положения
	защитника за последние lagFrames кадров (то, что атакующий видел у себя на экране).
	Неуязвимость защитника проверяется только по ТЕКУЩЕМУ состоянию.
]]
local function findContact(defender: Fighter, rect: Hitbox.Rect, lagFrames: number): (number?, number?)
	local hurt = Hitbox.hurt(defender.x, defender.y, Fighter.hurtKind(defender))
	if hurt == nil then
		return nil, nil -- неуязвим сейчас: отмотка назад не помогает
	end
	if Hitbox.overlaps(rect, hurt) then
		return Hitbox.contactPoint(rect, hurt)
	end
	for index = 1, math.min(lagFrames, #defender.history) do
		local record = defender.history[index]
		local past = Hitbox.hurt(record.x, record.y, record.kind)
		if past and Hitbox.overlaps(rect, past) then
			return Hitbox.contactPoint(rect, past)
		end
	end
	return nil, nil
end

local BLOCKING_STATES: { [string]: boolean } = {
	Idle = true,
	Walk = true,
	Crouch = true,
	Block = true,
	Blockstun = true,
	Landing = true,
}

-- Сможет ли защитник заблокировать удар такого типа прямо сейчас.
local function canBlock(defender: Fighter, attacker: Fighter, guard: Types.GuardType): boolean
	if guard == "Unblockable" or Fighter.isAirborne(defender) or not BLOCKING_STATES[defender.state] then
		return false
	end
	local away = if attacker.x > defender.x then -1 elseif attacker.x < defender.x then 1 else -defender.facing
	if InputBits.horizontal(defender.held) ~= away then
		return false
	end
	local crouching = InputBits.has(defender.held, InputBits.Down)
	if guard == "Low" and not crouching then
		return false
	end
	if guard == "Overhead" and crouching then
		return false
	end
	return true
end

-- Захват нельзя провести по бойцу в воздухе или в оглушении (иначе «бесконечные» захваты в комбо).
local function isGrabImmune(defender: Fighter): boolean
	local state = defender.state
	return Fighter.isAirborne(defender) or state == "Hitstun" or state == "Blockstun" or state == "Juggle"
end

local function collectHits(sim: Sim): { PendingHit }
	local pending: { PendingHit } = {}
	for _, attacker in sim.fighters do
		local move = if attacker.state == "Attack" and attacker.hitstop == 0 then moveOf(attacker) else nil
		local melee = move ~= nil and Specials.usesMeleeHitbox(attacker, attacker.move :: string)
		if move and melee and MoveBook.isActive(move, attacker.moveFrame) then
			local hitsTotal = move.hits or 1
			local interval = math.max(1, math.floor(move.active / hitsTotal))
			local due = math.min(hitsTotal, math.floor((attacker.moveFrame - move.startup) / interval) + 1)
			local defender = Simulation.opponentOf(sim, attacker)
			if attacker.moveHits < due and not (move.guard == "Unblockable" and isGrabImmune(defender)) then
				local id = attacker.move :: string
				local reach = if MoveBook.isNormal(id) then attacker.stats.rangeMultiplier else 1
				local rect = Hitbox.attack(attacker.x, attacker.y, attacker.facing, move.hitbox, reach)
				local x, y = findContact(defender, rect, attacker.lagFrames)
				if x and y then
					table.insert(pending, { attacker = attacker, defender = defender, move = move, x = x, y = y })
				end
			end
		end
	end
	return pending
end

local function startCinematic(sim: Sim, attacker: Fighter, defender: Fighter, move: MoveData)
	local def = CharacterRegistry.get(attacker.characterId)
	local style = if def then def.super.cinematic.style else "Default"
	local seconds = if def then def.super.cinematic.duration else 2
	local hits = if def then def.super.cinematic.hits else 5
	local scale = math.max(0.5, comboScale(defender.comboHits)) * modifierScale(attacker, defender, false)
	local damage = math.max(1, math.floor(move.damage * attacker.stats.damageMultiplier * scale + 0.5))
	local cinematic: Cinematic = {
		attacker = attacker.slot,
		defender = defender.slot,
		frame = 0,
		duration = math.max(1, math.floor(seconds * TICK + 0.5)),
		hits = math.max(1, hits),
		damage = damage,
		dealt = 0,
		hitsDone = 0,
	}
	sim.cinematic = cinematic
	Fighter.setState(defender, "Cinematic")
	defender.vx, defender.vy, defender.push = 0, 0, 0
	defender.move = nil
	attacker.vx, attacker.push = 0, 0
	emit(sim, "CinematicStart", attacker, cinematic.duration, attacker.slot, style)
end

local applyHit: (sim: Sim, hit: PendingHit) -> ()

-- Контратака: стойка перехватила удар — удар гасится, защитник отвечает своим приёмом.
local function counterAttack(sim: Sim, counterer: Fighter, striker: Fighter, hit: PendingHit)
	local behaviour = Specials.behaviour(counterer, counterer.move)
	if behaviour == nil then
		return
	end
	counterer.moveConnected = true
	striker.moveConnected = true
	striker.moveHits = 99 -- этот удар больше не попадёт
	emitAt(sim, "Parry", counterer, hit.x, hit.y, 0, counterer.slot, if behaviour.isSuper then "Super" else nil)
	if behaviour.isSuper then
		startCinematic(sim, counterer, striker, behaviour.move)
		emitAt(sim, "Hit", striker, hit.x, hit.y, 0, counterer.slot, "Super")
		return
	end
	applyHit(sim, {
		attacker = counterer,
		defender = striker,
		move = behaviour.move,
		x = hit.x,
		y = hit.y,
	})
end

function applyHit(sim: Sim, hit: PendingHit)
	local attacker, defender, move = hit.attacker, hit.defender, hit.move
	local projectile = hit.projectile
	local hitsTotal = if projectile then 1 else move.hits or 1
	local perHit = move.damage / hitsTotal
	local perChip = move.chip / hitsTotal
	local direction = if projectile
		then projectile.facing
		elseif defender.x > attacker.x then 1
		elseif defender.x < attacker.x then -1
		else attacker.facing
	local isSuper = projectile == nil and attacker.move == "Super"
	-- Защитник сам атаковал (для брони и контрудара).
	local defenderAttacking = defender.state == "Attack"
	local behaviour = if projectile then nil else Specials.behaviour(attacker, attacker.move)

	-- Стойка контратаки перехватывает удары вплотную (но не снаряды и не захваты).
	if projectile == nil and move.guard ~= "Unblockable" and Specials.isCountering(defender) then
		counterAttack(sim, defender, attacker, hit)
		return
	end

	if projectile == nil then
		attacker.moveConnected = true
		attacker.moveHits += 1
	end

	-- Блок.
	if canBlock(defender, attacker, move.guard) then
		local chip =
			math.floor(perChip * attacker.stats.damageMultiplier * modifierScale(attacker, defender, false) + 0.5)
		if chip > 0 then
			-- Блоком нельзя проиграть, кроме супера.
			defender.health = math.max(if isSuper then 0 else 1, defender.health - chip)
		end
		Fighter.setState(defender, "Blockstun")
		defender.stun = move.blockstun
		defender.vx = 0
		defender.push = direction * move.knockback * PUSH_SCALE * 0.8
		gainMeter(attacker, perHit * Combat.MeterPerDamageDealt * Combat.MeterBlockFactor)
		gainMeter(defender, perHit * Combat.MeterPerDamageTaken * Combat.MeterBlockFactor)
		local stop = math.floor(hitstopFor(perHit) * Combat.BlockHitstopFactor)
		defender.hitstop = stop
		if projectile == nil then
			attacker.hitstop = stop
		end
		emitAt(sim, "Block", defender, hit.x, hit.y, chip, attacker.slot, nil)
		if behaviour then
			Specials.afterHit(attacker, defender, behaviour, true)
		end
		if defender.health <= 0 then
			defender.ko = true
			Fighter.setState(defender, "Juggle")
			defender.vy = 20
			defender.vx = direction * 6
			emit(sim, "KO", defender, 0, attacker.slot, nil)
		end
		return
	end

	-- Броня: удар «впитывается», урон вдвое меньше, приём не прерывается (захват броню пробивает).
	if defender.armor > 0 and defenderAttacking and move.guard ~= "Unblockable" then
		defender.armor -= 1
		local absorbed = math.max(
			1,
			math.floor(perHit * attacker.stats.damageMultiplier * modifierScale(attacker, defender, false) * 0.5 + 0.5)
		)
		defender.health = math.max(1, defender.health - absorbed)
		local stop = hitstopFor(perHit)
		defender.hitstop = stop
		if projectile == nil then
			attacker.hitstop = stop
		end
		emitAt(sim, "Armor", defender, hit.x, hit.y, absorbed, attacker.slot, nil)
		return
	end

	-- Супер: попадание запускает кинематографичную серию (урон — в ней).
	if isSuper then
		startCinematic(sim, attacker, defender, move)
		emitAt(sim, "Hit", defender, hit.x, hit.y, 0, attacker.slot, "Super")
		return
	end

	local counter = defenderAttacking
	local scale = comboScale(defender.comboHits)
	local counterBonus = if counter then Combat.CounterHitDamage else 1
	local modifiers = modifierScale(attacker, defender, true)
	local damage =
		math.max(1, math.floor(perHit * attacker.stats.damageMultiplier * scale * counterBonus * modifiers + 0.5))
	defender.health = math.max(0, defender.health - damage)
	drainLife(attacker, damage)
	defender.comboHits += 1
	defender.comboDamage += damage
	defender.move = nil
	defender.moveConnected = false
	defender.armor = 0
	gainMeter(attacker, damage * Combat.MeterPerDamageDealt)
	gainMeter(defender, damage * Combat.MeterPerDamageTaken)

	local launch = move.launch or 0
	if defender.health <= 0 then
		defender.ko = true
		Fighter.setState(defender, "Juggle")
		defender.vy = 22
		defender.vx = direction * 8
		defender.juggleHits += 1
	elseif Fighter.isAirborne(defender) or launch > 0 then
		Fighter.setState(defender, "Juggle")
		defender.vy = if launch > 0 then launch else Combat.AirHitPop
		defender.vx = direction * move.knockback * 0.6
		defender.juggleHits += 1
		defender.knockdownOnLand = true
	elseif move.knockdown then
		Fighter.setState(defender, "Juggle")
		defender.vy = 12
		defender.vx = direction * move.knockback * 0.6
		defender.knockdownOnLand = true
	else
		Fighter.setState(defender, "Hitstun")
		defender.stun = move.hitstun + (if counter then Combat.CounterHitStun else 0)
		defender.vx = 0
		defender.push = direction * move.knockback * PUSH_SCALE
	end

	if behaviour then
		Specials.afterHit(attacker, defender, behaviour, false)
	end

	local stop = hitstopFor(damage)
	defender.hitstop = stop
	if projectile == nil then
		attacker.hitstop = stop
	end
	local tag = if counter then "Counter" elseif perHit >= 60 then "Heavy" else nil
	emitAt(sim, "Hit", defender, hit.x, hit.y, damage, attacker.slot, tag)
	if defender.ko then
		emit(sim, "KO", defender, damage, attacker.slot, nil)
	end
end

local function updateCinematic(sim: Sim)
	local cinematic = sim.cinematic :: Cinematic
	local attacker = sim.fighters[cinematic.attacker]
	local defender = sim.fighters[cinematic.defender]
	cinematic.frame += 1
	defender.stateFrame = cinematic.frame

	local expected = math.min(cinematic.hits, math.floor(cinematic.frame / cinematic.duration * cinematic.hits + 1e-9))
	while cinematic.hitsDone < expected do
		cinematic.hitsDone += 1
		local part = if cinematic.hitsDone == cinematic.hits
			then cinematic.damage - cinematic.dealt
			else math.floor(cinematic.damage / cinematic.hits)
		cinematic.dealt += part
		defender.health = math.max(0, defender.health - part)
		drainLife(attacker, part)
		defender.comboHits += 1
		defender.comboDamage += part
		gainMeter(defender, part * Combat.MeterPerDamageTaken)
		emit(sim, "CinematicHit", defender, part, attacker.slot, nil)
	end

	if cinematic.frame >= cinematic.duration then
		sim.cinematic = nil
		local direction = if defender.x > attacker.x then 1 elseif defender.x < attacker.x then -1 else attacker.facing
		Fighter.setState(defender, "Juggle")
		defender.vy = 26
		defender.vx = direction * 6
		defender.knockdownOnLand = true
		defender.ko = defender.health <= 0
		finishMove(sim, attacker)
		emit(sim, "CinematicEnd", attacker, cinematic.dealt, attacker.slot, nil)
		if defender.ko then
			emit(sim, "KO", defender, cinematic.dealt, attacker.slot, nil)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Шаг симуляции
----------------------------------------------------------------------------------------------

function Simulation.step(sim: Sim, inputs: { FrameInput })
	sim.frame += 1
	table.clear(sim.events)

	for index, fighter in sim.fighters do
		processInput(sim, fighter, inputs[index] or InputBits.empty())
	end

	-- Вспышка супера: всё замирает.
	if sim.freeze > 0 then
		sim.freeze -= 1
		return
	end
	-- Кинематографичная серия супера: бойцы стоят, идёт только серия ударов.
	if sim.cinematic then
		updateCinematic(sim)
		return
	end

	local frozen: { boolean } = {}
	for index, fighter in sim.fighters do
		if fighter.hitstop > 0 then
			fighter.hitstop -= 1
			frozen[index] = true
		else
			updateState(sim, fighter)
		end
	end

	for index, fighter in sim.fighters do
		if not frozen[index] then
			integrate(sim, fighter)
			if fighter.invulnerable > 0 then
				fighter.invulnerable -= 1
			end
		end
	end

	separate(sim)
	limitSeparation(sim)
	for _, fighter in sim.fighters do
		clampToArena(sim, fighter)
	end
	faceOpponent(sim)

	-- Попадания собираются для обоих бойцов, затем применяются — так возможны размены.
	if sim.freeze == 0 then
		for _, hit in collectHits(sim) do
			if sim.cinematic then
				break
			end
			applyHit(sim, hit)
		end
		-- Снаряды и ловушки: полёт, столкновения, попадания.
		for _, hit in Projectiles.step(sim, Specials.sweepsProjectiles) do
			if sim.cinematic then
				break
			end
			local projectile = hit.projectile
			if table.find(sim.projectiles, projectile) then
				applyHit(sim, {
					attacker = sim.fighters[projectile.owner],
					defender = hit.defender,
					move = projectile.move,
					x = hit.x,
					y = hit.y,
					projectile = projectile,
				})
				Projectiles.consume(sim, projectile)
			end
		end
	end

	for index, fighter in sim.fighters do
		recordHistory(fighter)
		if not frozen[index] then
			fighter.stateFrame += 1
		end
	end
end

return Simulation
