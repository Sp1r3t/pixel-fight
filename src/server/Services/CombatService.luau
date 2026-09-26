--!strict
--[[
	CombatService — серверный надзор за боем.

	Сама боевая логика (удары, блок, урон, хитбоксы) — в детерминированной симуляции
	Shared/Combat/Simulation, которая крутится ТОЛЬКО на сервере внутри MatchService.
	Этот сервис отвечает за то, что зависит от сети и игроков:

	  • компенсация пинга: каждому игроку — допуск на задержку по его пингу
	    (Player:GetNetworkPing), не больше GameConfig.Combat.MaxLagCompensationFrames;
	  • античит: игрок, заваливающий сервер некорректными/лишними пакетами ввода,
	    отключается (все пакеты и так проверяются в InputService, кик — последняя мера).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Simulation = require(ReplicatedStorage.Shared.Combat.Simulation)

local MatchService = require(script.Parent.MatchService)
local InputService = require(script.Parent.InputService)

local ABUSE_CHECK_INTERVAL = 5 -- секунд
local ABUSE_REJECTED_LIMIT = 400 -- отброшенных пакетов за интервал

local CombatService = {
	Name = "CombatService",
}

local lastRejected: { [Player]: number } = {}
local lastAbuseCheck = 0

-- Кадры компенсации пинга для игрока (половина RTT — время, за которое его ввод дошёл).
function CombatService.lagFramesFor(player: Player): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	if not ok or type(ping) ~= "number" or ping ~= ping then
		return 0
	end
	local frames = math.floor(ping * GameConfig.TickRate + 0.5)
	return math.clamp(frames, 0, GameConfig.Combat.MaxLagCompensationFrames)
end

local function updateLagCompensation(match: any)
	for slot, controller in match.controllers do
		if controller.kind == "Player" and controller.player then
			Simulation.setLagFrames(match.sim, slot, CombatService.lagFramesFor(controller.player))
		else
			Simulation.setLagFrames(match.sim, slot, 0)
		end
	end
end

local function checkAbuse(now: number)
	if now - lastAbuseCheck < ABUSE_CHECK_INTERVAL then
		return
	end
	lastAbuseCheck = now
	for _, player in Players:GetPlayers() do
		local rejected = InputService.getRejectedCount(player)
		local previous = lastRejected[player] or 0
		lastRejected[player] = rejected
		if rejected - previous > ABUSE_REJECTED_LIMIT then
			warn(
				`[CombatService] {player.Name}: слишком много некорректных пакетов ввода — отключение`
			)
			player:Kick("Обнаружена подозрительная активность сети.")
		end
	end
end

function CombatService.Init()
	MatchService.addStepHook(function(match)
		-- Пинг меняется медленно: обновляем раз в 30 кадров.
		if match.sim.frame % 30 == 1 then
			updateLagCompensation(match)
		end
		checkAbuse(os.clock())
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRejected[player] = nil
	end)
end

function CombatService.Start() end

return CombatService
