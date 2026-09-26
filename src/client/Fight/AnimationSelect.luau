--!strict
--[[
	Выбор анимации по состоянию бойца из снапшота. Чистая функция — легко тестировать.
	Время анимации = время в текущем состоянии (stateFrame / TickRate), поэтому
	картинка всегда синхронна с серверной симуляцией.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Snapshot = require(ReplicatedStorage.Shared.Combat.Snapshot)

export type Choice = {
	name: Types.AnimationName,
	time: number,
	progress: number?, -- для ударов: 0..1 по фреймдате
}

local TICK = GameConfig.TickRate
local IDLE: Types.AnimationName = "Idle"

local STATE_ANIMATIONS: { [string]: Types.AnimationName } = {
	Intro = "Idle",
	Idle = "Idle",
	Walk = "Walk",
	Crouch = "Crouch",
	PreJump = "Crouch",
	Air = "Jump",
	Landing = "Crouch",
	Dash = "Dash",
	Backdash = "Dash",
	Block = "Block",
	Blockstun = "Block",
	Hitstun = "Hit",
	Juggle = "Hit",
	Knockdown = "Knockdown",
	WakeUp = "Crouch",
	Cinematic = "Hit",
	KO = "Knockdown",
	Win = "Win",
	Lose = "Lose",
	Attack = "Light",
}

local AnimationSelect = {}

--[[
	Прогресс удара с «растяжкой» фаз: startup → [0, 1/3], active → [1/3, 2/3], recovery → [2/3, 1].
	Так активные кадры удара всегда совпадают с кадрами «удара» в анимации.
]]
function AnimationSelect.phaseProgress(frame: number, startup: number, active: number, recovery: number): number
	if frame < startup then
		return (frame / math.max(startup, 1)) / 3
	elseif frame < startup + active then
		return 1 / 3 + ((frame - startup) / math.max(active, 1)) / 3
	end
	local into = frame - startup - active
	return math.min(1, 2 / 3 + (into / math.max(recovery, 1)) / 3)
end

function AnimationSelect.choose(fighter: Snapshot.FighterSnapshot): Choice
	local name: Types.AnimationName = STATE_ANIMATIONS[fighter.state] or IDLE
	local time = fighter.stateFrame / TICK
	if fighter.state == "PreJump" or fighter.state == "Landing" then
		-- Короткое приседание: сразу нижняя поза.
		return { name = name, time = 1, progress = nil }
	end
	return { name = name, time = time, progress = nil }
end

return AnimationSelect
