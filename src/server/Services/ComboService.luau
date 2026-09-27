--!strict
--[[
	ComboService — награды за комбо.

	Комбо распознаёт сама симуляция боя (Combat/Combos → событие "Combo"): клиент подделать его
	не может. После каждого шага боя сервис смотрит, какие комбо сделали игроки, и за ПЕРВОЕ
	выполнение каждого комбо начисляет монеты (DataService.recordCombo) и сообщает игроку
	("ComboUnlocked": id и монеты). Боты и манекен наград не получают.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Transport = require(ReplicatedStorage.Shared.Net.Transport)
local Match = require(script.Parent.Parent.Match.Match)
local MatchService = require(script.Parent.MatchService)
local DataService = require(script.Parent.DataService)

type Match = Match.Match

local ComboService = {
	Name = "ComboService",
}

local function onStep(match: Match)
	for _, event in match.sim.events do
		local comboId = event.tag
		if event.kind == "Combo" and comboId then
			local controller = match.controllers[event.slot]
			local player = if controller and controller.kind == "Player" then controller.player else nil
			if player then
				local coins = DataService.recordCombo(player, comboId)
				if coins > 0 then
					Transport.fireClient("MatchEvent", player, "ComboUnlocked", { id = comboId, coins = coins })
				end
			end
		end
	end
end

function ComboService.Init()
	MatchService.addStepHook(onStep)
end

function ComboService.Start() end

return ComboService
