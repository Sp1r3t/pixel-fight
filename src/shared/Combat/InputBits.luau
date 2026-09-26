--!strict
--[[
	Формат ввода. Клиент отправляет на сервер ТОЛЬКО это:
	  • held     — битовая маска удерживаемых кнопок;
	  • counters — упакованные 4-битные счётчики нажатий кнопок действий.

	Счётчики нужны потому, что ввод идёт по ненадёжному каналу: если пакет с моментом нажатия
	потерялся, следующий пакет всё равно покажет, что счётчик вырос, и нажатие не пропадёт.
]]

local InputBits = {}

InputBits.Left = 1
InputBits.Right = 2
InputBits.Up = 4
InputBits.Down = 8
InputBits.Light = 16 -- «Рука»
InputBits.Heavy = 32 -- «Нога»
InputBits.Special = 64
InputBits.Super = 128
InputBits.Dash = 256

InputBits.ALL = 511

-- Кнопки действий со счётчиками нажатий (порядок важен для упаковки).
InputBits.ACTIONS = table.freeze({
	InputBits.Light,
	InputBits.Heavy,
	InputBits.Special,
	InputBits.Super,
	InputBits.Dash,
})

local COUNTER_BITS = 4
local COUNTER_MOD = 2 ^ COUNTER_BITS -- 16
-- Больше нажатий одной кнопки между двумя пакетами не засчитываем (защита от спама).
local MAX_PRESSES_PER_PACKET = 3

export type FrameInput = {
	held: number, -- удерживаемые кнопки
	pressed: number, -- кнопки действий, нажатые в этом кадре
}

function InputBits.has(mask: number, bit: number): boolean
	return bit32.band(mask, bit) ~= 0
end

function InputBits.sanitize(mask: number): number
	if type(mask) ~= "number" or mask ~= mask then
		return 0
	end
	return bit32.band(math.floor(mask), InputBits.ALL)
end

-- Упаковать счётчики (по одному на кнопку из ACTIONS) в одно число.
function InputBits.packCounters(counters: { number }): number
	local packed = 0
	for index = 1, #InputBits.ACTIONS do
		local value = (counters[index] or 0) % COUNTER_MOD
		packed = bit32.bor(packed, bit32.lshift(value, (index - 1) * COUNTER_BITS))
	end
	return packed
end

function InputBits.unpackCounters(packed: number): { number }
	local counters = table.create(#InputBits.ACTIONS, 0)
	local safe = if type(packed) == "number" and packed == packed then math.floor(packed) else 0
	for index = 1, #InputBits.ACTIONS do
		counters[index] = bit32.extract(safe, (index - 1) * COUNTER_BITS, COUNTER_BITS)
	end
	return counters
end

--[[
	Сколько раз нажата каждая кнопка между двумя пакетами.
	Возвращает маску кнопок, нажатых хотя бы раз, и массив количеств.
]]
function InputBits.diffCounters(previous: { number }, current: { number }): (number, { number })
	local mask = 0
	local counts = table.create(#InputBits.ACTIONS, 0)
	for index, bit in InputBits.ACTIONS do
		local delta = ((current[index] or 0) - (previous[index] or 0)) % COUNTER_MOD
		if delta > 0 then
			counts[index] = math.min(delta, MAX_PRESSES_PER_PACKET)
			mask = bit32.bor(mask, bit)
		end
	end
	return mask, counts
end

-- Горизонтальное направление в мировых координатах: -1, 0 или 1.
function InputBits.horizontal(mask: number): number
	local left = InputBits.has(mask, InputBits.Left)
	local right = InputBits.has(mask, InputBits.Right)
	if left == right then
		return 0
	end
	return if right then 1 else -1
end

function InputBits.empty(): FrameInput
	return { held = 0, pressed = 0 }
end

return InputBits
