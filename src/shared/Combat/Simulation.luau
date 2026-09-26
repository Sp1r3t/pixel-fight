--!strict
--[[
	Детерминированная симуляция поединка 1 на 1 с фиксированным шагом (GameConfig.TickRate).
	Чистый Luau без Roblox API: одна и та же симуляция работает на сервере (авторитетно)
	и в тестах. Сервер вызывает Simulation.step() 60 раз в секунду, подавая ввод игроков/ИИ.

	Порядок кадра:
	  1. обработка ввода (буфер нажатий, двойное нажатие для рывка);
	  2. логика состояний (движение, прыжки, рывки);
	  3. интеграция позиций и приземление;
	  4. раздвигание бойцов, границы арены, максимальная дистанция;
	  5. поворот к противнику.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local InputBits = require(script.Parent.InputBits)
local Fighter = require(script.Parent.Fighter)

type Fighter = Fighter.Fighter
type FrameInput = InputBits.FrameInput

local Physics = GameConfig.Physics
local TICK = GameConfig.TickRate
local DT = 1 / TICK

export type SimEvent = {
	kind: string, -- "Jump" | "Land" | "Dash" | "Backdash" | ...
	slot: number,
	x: number?,
	y: number?,
	value: number?,
}

export type Sim = {
	frame: number,
	fighters: { Fighter },
	inputEnabled: boolean, -- false во время заставок раунда
	events: { SimEvent }, -- события последнего шага (для эффектов на клиенте)
}

export type SimOptions = {
	characters: { string }, -- два id персонажей
	hpMultipliers: { number }?,
}

local Simulation = {}

local function emit(sim: Sim, kind: string, fighter: Fighter, value: number?)
	table.insert(sim.events, { kind = kind, slot = fighter.slot, x = fighter.x, y = fighter.y, value = value })
end

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
	}
	Simulation.resetPositions(sim)
	return sim
end

-- Расставить бойцов на стартовые позиции (начало раунда).
function Simulation.resetPositions(sim: Sim)
	local half = Physics.StartDistance / 2
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
		Fighter.setState(fighter, "Idle")
	end
end

-- Заменить бойца в слоте (эстафета 2 на 2): новый боец выходит на позицию старого.
function Simulation.replaceFighter(sim: Sim, slot: number, characterId: string, hpMultiplier: number?): Fighter
	local old = sim.fighters[slot]
	local fighter = Fighter.new(slot, characterId, hpMultiplier)
	fighter.x = old.x
	fighter.facing = old.facing
	sim.fighters[slot] = fighter
	return fighter
end

function Simulation.opponentOf(sim: Sim, fighter: Fighter): Fighter
	return sim.fighters[3 - fighter.slot]
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
	for bit, frames in fighter.buffer do
		if frames > 1 then
			fighter.buffer[bit] = frames - 1
		else
			fighter.buffer[bit] = nil
		end
	end
	for _, bit in InputBits.ACTIONS do
		if InputBits.has(pressed, bit) and bit ~= InputBits.Dash then
			fighter.buffer[bit] = GameConfig.Input.BufferFrames
		end
	end

	if fighter.dashRequestFrames > 0 then
		fighter.dashRequestFrames -= 1
		if fighter.dashRequestFrames == 0 then
			fighter.dashRequest = 0
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
	if tap ~= 0 and not InputBits.has(held, InputBits.Down) then
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

local function groundControl(sim: Sim, fighter: Fighter)
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

local function updateState(sim: Sim, fighter: Fighter)
	local state = fighter.state

	if isGroundActionable(fighter) then
		groundControl(sim, fighter)
	elseif state == "PreJump" then
		local direction = InputBits.horizontal(fighter.held)
		if direction ~= 0 then
			fighter.jumpDir = direction
		end
		if fighter.stateFrame >= Physics.JumpSquatFrames then
			Fighter.setState(fighter, "Air")
			fighter.vy = Physics.JumpVelocity
			fighter.vx = fighter.jumpDir * fighter.stats.walkSpeed * Physics.JumpForwardSpeedFactor
			emit(sim, "Jump", fighter)
		end
	elseif state == "Air" then
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
	end
end

local function integrate(sim: Sim, fighter: Fighter)
	fighter.x += fighter.vx * DT
	if fighter.state == "Air" or fighter.y > 0 or fighter.vy > 0 then
		fighter.y += fighter.vy * DT
		if fighter.y <= 0 and fighter.vy <= 0 then
			fighter.y = 0
			fighter.vy = 0
			if fighter.state == "Air" then
				fighter.vx = 0
				Fighter.setState(fighter, "Landing")
				emit(sim, "Land", fighter)
			end
		end
	end
end

----------------------------------------------------------------------------------------------
-- Пространство: раздвигание, границы, дистанция, поворот
----------------------------------------------------------------------------------------------

local WALL = Physics.ArenaHalfWidth - Physics.PushWidth / 2

local function clampToArena(fighter: Fighter)
	fighter.x = math.clamp(fighter.x, -WALL, WALL)
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
	local aAway = math.max(0, -side * a.vx)
	local bAway = math.max(0, side * b.vx)
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

----------------------------------------------------------------------------------------------
-- Шаг симуляции
----------------------------------------------------------------------------------------------

function Simulation.step(sim: Sim, inputs: { FrameInput })
	sim.frame += 1
	table.clear(sim.events)

	for index, fighter in sim.fighters do
		processInput(sim, fighter, inputs[index] or InputBits.empty())
	end

	for _, fighter in sim.fighters do
		updateState(sim, fighter)
	end

	for _, fighter in sim.fighters do
		integrate(sim, fighter)
		if fighter.invulnerable > 0 then
			fighter.invulnerable -= 1
		end
	end

	separate(sim)
	limitSeparation(sim)
	for _, fighter in sim.fighters do
		clampToArena(fighter)
	end
	faceOpponent(sim)

	for _, fighter in sim.fighters do
		fighter.stateFrame += 1
	end
end

return Simulation
