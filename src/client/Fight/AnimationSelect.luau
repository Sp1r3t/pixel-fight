--!strict
--[[
	Выбор анимации по состоянию бойца из снапшота. Чистая функция — легко тестировать.
	  • обычные состояния: время анимации = время в состоянии (stateFrame / TickRate);
	  • удары: кадр анимации — по фреймдате приёма (startup → active → recovery),
	    поэтому «удар» на экране совпадает с активными кадрами хитбокса на сервере.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Snapshot = require(ReplicatedStorage.Shared.Combat.Snapshot)
local MoveBook = require(ReplicatedStorage.Shared.Combat.MoveBook)

export type Choice = {
	name: Types.AnimationName,
	time: number,
	progress: number?, -- для ударов: 0..1 по фреймдате
}

local TICK = GameConfig.TickRate
local IDLE: Types.AnimationName = "Idle"
local CROUCH: Types.AnimationName = "Crouch"

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
}

local MOVE_ANIMATIONS: { [string]: Types.AnimationName } = {
	Light1 = "Light",
	Light2 = "Light",
	Light3 = "Light",
	Heavy = "Heavy",
	CrouchLight = "CrouchLight",
	CrouchHeavy = "CrouchHeavy",
	AirLight = "AirLight",
	AirHeavy = "AirHeavy",
	Special = "Special",
	Super = "Super",
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

function AnimationSelect.choose(fighter: Snapshot.FighterSnapshot, characterId: string): Choice
	local time = fighter.stateFrame / TICK

	if fighter.state == "Attack" then
		local moveId = MoveBook.fromIndex(fighter.move)
		local move = if moveId then MoveBook.get(characterId, moveId) else nil
		if moveId and move then
			local name: Types.AnimationName = MOVE_ANIMATIONS[moveId] or IDLE
			local progress = AnimationSelect.phaseProgress(fighter.moveFrame, move.startup, move.active, move.recovery)
			return { name = name, time = time, progress = progress }
		end
		return { name = IDLE, time = time, progress = nil }
	end

	if fighter.state == "PreJump" or fighter.state == "Landing" then
		-- Короткое приседание: сразу нижняя поза.
		return { name = CROUCH, time = 1, progress = nil }
	end

	local lowBlock = bit32.band(fighter.flags, Snapshot.Flags.LowBlock) ~= 0
	if (fighter.state == "Block" or fighter.state == "Blockstun") and lowBlock then
		return { name = CROUCH, time = 1, progress = nil }
	end

	local name: Types.AnimationName = STATE_ANIMATIONS[fighter.state] or IDLE
	return { name = name, time = time, progress = nil }
end

return AnimationSelect
