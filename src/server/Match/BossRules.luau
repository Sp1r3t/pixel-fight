--!strict
--[[
	Правила боя с боссом: уникальные механики (Types.BossMechanic).

	Механики работают через модификаторы бойца в симуляции (Fighter.modifiers) — симуляция
	остаётся общей и детерминированной, а босс не получает «читерских» прямых правок боя,
	кроме описанных в механике:
	  IronSkin     — первый удар каждой серии по боссу наносит 50% урона;
	  Regeneration — после 3 с без урона восстанавливает 1.5% HP в секунду;
	  Enrage       — ниже 35% HP наносит на 20% больше урона (событие "Mechanic" для эффекта);
	  Vampiric     — лечится на 20% от нанесённого урона;
	  Momentum     — шкала супера растёт на 35% быстрее;
	  SuperStart   — в начале каждого раунда шкала супера полная;
	  Mirror       — сражается персонажем игрока (выбирается при создании матча, см. BossService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Simulation = require(ReplicatedStorage.Shared.Combat.Simulation)

local Match = require(script.Parent.Match)

local TICK = GameConfig.TickRate

local BossRules = {}

BossRules.IRON_SKIN_FACTOR = 0.5
BossRules.REGEN_DELAY_FRAMES = 3 * TICK
BossRules.REGEN_PER_SECOND = 0.015
BossRules.ENRAGE_THRESHOLD = 0.35
BossRules.ENRAGE_DAMAGE = 1.2
BossRules.LIFESTEAL = 0.2
BossRules.MOMENTUM_METER = 1.35

export type BossState = {
	slot: number,
	mechanics: { [string]: boolean }, -- набор Types.BossMechanic
	lastHealth: number,
	calmFrames: number, -- кадров без полученного урона
	regenCarry: number, -- дробная часть восстановления
	enraged: boolean,
	superRound: number, -- в каком раунде уже выдана полная шкала
}

-- Подготовить матч с боссом в слоте slot.
function BossRules.setup(match: Match.Match, slot: number, mechanics: { Types.BossMechanic })
	local set: { [string]: boolean } = {}
	for _, mechanic in mechanics do
		set[mechanic] = true
	end
	local fighter = match.sim.fighters[slot]
	local modifiers = fighter.modifiers
	if set.IronSkin then
		modifiers.firstHitTaken = BossRules.IRON_SKIN_FACTOR
	end
	if set.Vampiric then
		modifiers.lifesteal = BossRules.LIFESTEAL
	end
	if set.Momentum then
		modifiers.meterGain = BossRules.MOMENTUM_METER
	end
	local state: BossState = {
		slot = slot,
		mechanics = set,
		lastHealth = fighter.health,
		calmFrames = 0,
		regenCarry = 0,
		enraged = false,
		superRound = 0,
	}
	match.data.boss = state
end

local function mechanicEvent(match: Match.Match, slot: number, mechanic: string)
	local fighter = match.sim.fighters[slot]
	table.insert(match.pendingEvents, {
		k = "Mechanic",
		s = slot,
		f = match.sim.frame,
		x = fighter.x,
		y = fighter.y,
		t = mechanic,
	})
end

-- Хук шага MatchService: вызывается после каждого шага симуляции.
function BossRules.step(match: Match.Match)
	local state = match.data.boss :: BossState?
	if match.mode ~= "Boss" or state == nil then
		return
	end
	local sim = match.sim
	local flow = match.flow
	local fighter = sim.fighters[state.slot]
	local mechanics = state.mechanics

	-- Новый раунд: HP восстановлено, ярость проходит, «Готов к бою» заряжает супер.
	if flow and flow.phase == "RoundStart" then
		state.lastHealth = fighter.health
		state.calmFrames = 0
		if state.enraged then
			state.enraged = false
			fighter.modifiers.damageDealt = 1
		end
		if mechanics.SuperStart and state.superRound ~= flow.round then
			state.superRound = flow.round
			fighter.meter = GameConfig.SuperMeter.Max
		end
	end

	local fighting = (flow == nil or flow.phase == "Fight" or flow.phase == "RoundStart")
		and sim.inputEnabled
		and not fighter.ko

	if mechanics.Regeneration and fighting then
		if fighter.health < state.lastHealth then
			state.calmFrames = 0
			state.regenCarry = 0
		elseif not Simulation.isPaused(sim) then
			state.calmFrames += 1
		end
		if state.calmFrames >= BossRules.REGEN_DELAY_FRAMES and fighter.health < fighter.maxHealth then
			state.regenCarry += fighter.maxHealth * BossRules.REGEN_PER_SECOND / TICK
			local whole = math.floor(state.regenCarry)
			if whole > 0 then
				state.regenCarry -= whole
				fighter.health = math.min(fighter.maxHealth, fighter.health + whole)
			end
		end
	end

	if mechanics.Enrage and fighting and not state.enraged then
		if fighter.health <= fighter.maxHealth * BossRules.ENRAGE_THRESHOLD then
			state.enraged = true
			fighter.modifiers.damageDealt = BossRules.ENRAGE_DAMAGE
			mechanicEvent(match, state.slot, "Enrage")
		end
	end

	state.lastHealth = fighter.health
end

return BossRules
