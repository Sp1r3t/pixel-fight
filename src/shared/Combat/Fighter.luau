--!strict
--[[
	Состояние одного бойца в симуляции. Только данные (числа, строки, булевы) —
	поэтому состояние легко копировать, сериализовать и проверять в тестах.
]]

local Types = require(script.Parent.Parent.Types)
local Hitbox = require(script.Parent.Hitbox)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local CharacterRegistry = require(script.Parent.Parent.Characters.CharacterRegistry)

local Physics = GameConfig.Physics

export type StateName =
	"Intro"
	| "Idle"
	| "Walk"
	| "Crouch"
	| "PreJump"
	| "Air"
	| "Landing"
	| "Dash"
	| "Backdash"
	| "Block"
	| "Attack"
	| "Hitstun"
	| "Blockstun"
	| "Juggle"
	| "Knockdown"
	| "WakeUp"
	| "Cinematic"
	| "KO"
	| "Win"
	| "Lose"

-- Порядок важен: индекс используется в снапшотах.
local STATES: { StateName } = {
	"Intro",
	"Idle",
	"Walk",
	"Crouch",
	"PreJump",
	"Air",
	"Landing",
	"Dash",
	"Backdash",
	"Block",
	"Attack",
	"Hitstun",
	"Blockstun",
	"Juggle",
	"Knockdown",
	"WakeUp",
	"Cinematic",
	"KO",
	"Win",
	"Lose",
}

export type Fighter = {
	slot: number,
	characterId: string,
	stats: Types.DerivedStats,
	hpMultiplier: number, -- умеренный бонус HP боссов (1 у игроков)

	x: number,
	y: number, -- высота ног над полом
	vx: number, -- студ/с
	vy: number,
	facing: number, -- 1 — смотрит вправо, -1 — влево

	state: StateName,
	stateFrame: number, -- сколько кадров боец в текущем состоянии
	jumpDir: number, -- направление прыжка в мире: -1, 0, 1
	dashDir: number,

	health: number,
	maxHealth: number,
	meter: number,

	-- Ввод.
	held: number,
	prevHeld: number,
	buffer: { [number]: number }, -- бит кнопки → сколько кадров нажатие ещё «помнится»
	dashRequest: number, -- запрошенный рывок: направление в мире или 0
	dashRequestFrames: number,
	tapDir: number, -- последнее нажатое направление (для двойного нажатия)
	tapFrame: number,

	invulnerable: number, -- кадры неуязвимости к ударам

	-- Атака.
	move: string?, -- текущий приём ("Light1", "Heavy", "Special", "Super", ...)
	moveFrame: number, -- кадр внутри приёма (с 0)
	moveConnected: boolean, -- попал или был заблокирован (открывает отмены в следующий удар)
	moveHits: number, -- сколько ударов приёма уже засчитано (для многоударных)
	airAttackUsed: boolean,
	specialCooldown: number,
	armor: number, -- сколько ударов ещё «впитает» броня (особые приёмы)

	-- Реакция на удары.
	stun: number, -- оставшиеся кадры хитстана/блокстана/нокдауна
	hitstop: number, -- кадры «замирания» после удара
	push: number, -- скорость отбрасывания, студ/с (затухает)
	comboHits: number, -- сколько ударов подряд пропустил
	comboDamage: number,
	juggleHits: number, -- ударов в воздухе за одно подбрасывание
	knockdownOnLand: boolean,
	ko: boolean,

	-- Компенсация пинга: на сколько кадров назад можно «отмотать» противника для атак этого бойца.
	lagFrames: number,
	-- Недавние хартбоксы бойца (новые — в начале); не передаются по сети.
	history: { HurtRecord },
}

export type HurtRecord = { x: number, y: number, kind: Hitbox.HurtKind }

local Fighter = {}

Fighter.STATES = table.freeze(STATES)

local stateIndex: { [string]: number } = {}
for index, name in STATES do
	stateIndex[name] = index
end

function Fighter.stateToIndex(state: StateName): number
	return stateIndex[state]
end

function Fighter.indexToState(index: number): StateName?
	return STATES[index]
end

function Fighter.new(slot: number, characterId: string, hpMultiplier: number?): Fighter
	local def = CharacterRegistry.get(characterId)
	assert(def, `Неизвестный персонаж: {characterId}`)
	local stats = CharacterRegistry.getDerivedStats(def)
	local multiplier = hpMultiplier or 1
	local maxHealth = math.floor(stats.maxHealth * multiplier + 0.5)
	return {
		slot = slot,
		characterId = characterId,
		stats = stats,
		hpMultiplier = multiplier,
		x = 0,
		y = 0,
		vx = 0,
		vy = 0,
		facing = if slot == 1 then 1 else -1,
		state = "Idle",
		stateFrame = 0,
		jumpDir = 0,
		dashDir = 0,
		health = maxHealth,
		maxHealth = maxHealth,
		meter = 0,
		held = 0,
		prevHeld = 0,
		buffer = {},
		dashRequest = 0,
		dashRequestFrames = 0,
		tapDir = 0,
		tapFrame = -1000,
		invulnerable = 0,
		move = nil,
		moveFrame = 0,
		moveConnected = false,
		moveHits = 0,
		airAttackUsed = false,
		specialCooldown = 0,
		armor = 0,
		stun = 0,
		hitstop = 0,
		push = 0,
		comboHits = 0,
		comboDamage = 0,
		juggleHits = 0,
		knockdownOnLand = false,
		ko = false,
		lagFrames = 0,
		history = {},
	}
end

function Fighter.setState(fighter: Fighter, state: StateName)
	fighter.state = state
	fighter.stateFrame = 0
end

function Fighter.isAirborne(fighter: Fighter): boolean
	return fighter.state == "Air" or fighter.state == "Juggle" or fighter.y > 0
end

local InputDown = 8 -- InputBits.Down (без require, чтобы избежать цикла зависимостей)

function Fighter.isCrouching(fighter: Fighter): boolean
	local state = fighter.state
	if state == "Crouch" then
		return true
	end
	if state == "Attack" then
		return fighter.move == "CrouchLight" or fighter.move == "CrouchHeavy"
	end
	if state == "Block" or state == "Blockstun" then
		return bit32.band(fighter.held, InputDown) ~= 0
	end
	return false
end

-- Может ли боец сейчас получить удар и какой формы его тело.
function Fighter.hurtKind(fighter: Fighter): Hitbox.HurtKind
	local state = fighter.state
	if fighter.invulnerable > 0 or fighter.ko then
		return "None"
	end
	if state == "Knockdown" or state == "WakeUp" or state == "KO" or state == "Intro" then
		return "None"
	end
	if state == "Juggle" and fighter.juggleHits >= 3 then
		return "None" -- защита от бесконечных комбо в воздухе
	end
	if Fighter.isAirborne(fighter) then
		return "Air"
	end
	if Fighter.isCrouching(fighter) then
		return "Crouch"
	end
	return "Stand"
end

-- Вертикальные границы «толкающего» прямоугольника тела (для раздвигания бойцов).
function Fighter.pushExtent(fighter: Fighter): (number, number)
	if fighter.state == "Knockdown" or fighter.state == "KO" then
		return fighter.y, fighter.y + 1
	elseif Fighter.isAirborne(fighter) then
		return fighter.y + Physics.AirPushBottom, fighter.y + Physics.AirPushTop
	elseif Fighter.isCrouching(fighter) then
		return fighter.y, fighter.y + Physics.CrouchHeight
	end
	return fighter.y, fighter.y + Physics.StandHeight
end

return Fighter
