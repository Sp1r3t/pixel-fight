--!strict
--[[
	Состояние одного бойца в симуляции. Только данные (числа, строки, булевы) —
	поэтому состояние легко копировать, сериализовать и проверять в тестах.
]]

local Types = require(script.Parent.Parent.Types)
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
}

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
	}
end

function Fighter.setState(fighter: Fighter, state: StateName)
	fighter.state = state
	fighter.stateFrame = 0
end

function Fighter.isAirborne(fighter: Fighter): boolean
	return fighter.state == "Air" or fighter.state == "Juggle" or fighter.y > 0
end

function Fighter.isCrouching(fighter: Fighter): boolean
	return fighter.state == "Crouch"
end

-- Вертикальные границы «толкающего» прямоугольника тела (для раздвигания бойцов).
function Fighter.pushExtent(fighter: Fighter): (number, number)
	if fighter.state == "Knockdown" then
		return fighter.y, fighter.y + 1
	elseif Fighter.isAirborne(fighter) then
		return fighter.y + Physics.AirPushBottom, fighter.y + Physics.AirPushTop
	elseif Fighter.isCrouching(fighter) then
		return fighter.y, fighter.y + Physics.CrouchHeight
	end
	return fighter.y, fighter.y + Physics.StandHeight
end

return Fighter
