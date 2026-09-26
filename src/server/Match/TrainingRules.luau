--!strict
--[[
	Правила режима «Тренировка»: удобство отработки приёмов.
	  • шкала супера игрока всегда полная;
	  • манекен восстанавливает HP, когда комбо закончилось и он постоял секунду;
	  • после нокаута манекен «оживает» и бойцы возвращаются на старт.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Simulation = require(ReplicatedStorage.Shared.Combat.Simulation)

local Match = require(script.Parent.Match)

local REFILL_AFTER_FRAMES = 60
local RESET_AFTER_KO_FRAMES = 90

local TrainingRules = {}

function TrainingRules.step(match: Match.Match)
	if match.mode ~= "Training" then
		return
	end
	local sim = match.sim
	for slot, controller in match.controllers do
		local fighter = sim.fighters[slot]
		if controller.kind == "Player" then
			fighter.meter = GameConfig.SuperMeter.Max
		elseif fighter.state == "KO" and fighter.stateFrame >= RESET_AFTER_KO_FRAMES then
			Simulation.resetPositions(sim)
			Simulation.restoreHealth(sim)
		elseif fighter.state == "Idle" and fighter.stateFrame >= REFILL_AFTER_FRAMES then
			fighter.health = fighter.maxHealth
		end
	end
end

return TrainingRules
