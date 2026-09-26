--!strict
--[[
	Детерминированный генератор случайных чисел (Лемер / Park–Miller).
	Одинаковое зерно → одинаковая последовательность на сервере, клиенте и в тестах.
	Состояние — одно число, поэтому генератор легко хранить внутри симуляции.
]]

local MODULUS = 2147483647
local MULTIPLIER = 48271

export type Rng = { state: number }

local Rng = {}

function Rng.new(seed: number): Rng
	local state = math.floor(math.abs(seed)) % MODULUS
	if state == 0 then
		state = 1
	end
	return { state = state }
end

-- Число в [0, 1).
function Rng.next(rng: Rng): number
	rng.state = (rng.state * MULTIPLIER) % MODULUS
	return (rng.state - 1) / (MODULUS - 1)
end

function Rng.range(rng: Rng, min: number, max: number): number
	return min + (max - min) * Rng.next(rng)
end

-- Целое в [min, max].
function Rng.integer(rng: Rng, min: number, max: number): number
	return min + math.floor(Rng.next(rng) * (max - min + 1) - 1e-9)
end

function Rng.chance(rng: Rng, probability: number): boolean
	return Rng.next(rng) < probability
end

-- Хэш строки в зерно (например, id арены).
function Rng.seedFromString(text: string): number
	local hash = 5381
	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % MODULUS
	end
	return hash
end

return Rng
