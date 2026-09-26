--!strict
--[[
	InputService — приём ввода от клиентов.

	Клиент присылает ТОЛЬКО (seq, held, counters):
	  • seq      — номер пакета (старые/повторные пакеты отбрасываются);
	  • held     — маска удерживаемых кнопок (лишние биты вырезаются);
	  • counters — упакованные счётчики нажатий (нажатие не теряется при потере пакета).

	Защита:
	  • лимит пакетов в секунду на игрока (GameConfig.Input.MaxPacketsPerSecond);
	  • строгая проверка типов и диапазонов аргументов;
	  • если пакетов нет дольше STALE_TIMEOUT, удерживаемые кнопки сбрасываются
	    (игрок с оборванной связью не «залипает» в ходьбе).
	Всё, что игрок может сделать, дальше проверяет симуляция боя (кулдауны, фреймдата, дистанция).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local InputBits = require(ReplicatedStorage.Shared.Combat.InputBits)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local STALE_TIMEOUT = 0.5 -- секунды без пакетов → считаем, что кнопки отпущены
local MAX_SEQ = 2 ^ 31

type PlayerInput = {
	held: number,
	counters: { number },
	pending: { number }, -- неиспользованные нажатия по кнопкам ACTIONS
	lastSeq: number,
	lastPacketAt: number,
	windowStart: number,
	windowCount: number,
	rejected: number, -- сколько пакетов отброшено (для аналитики/античита)
}

local InputService = {
	Name = "InputService",
}

local inputs: { [Player]: PlayerInput } = {}

local function newPlayerInput(): PlayerInput
	return {
		held = 0,
		counters = table.create(#InputBits.ACTIONS, 0),
		pending = table.create(#InputBits.ACTIONS, 0),
		lastSeq = -1,
		lastPacketAt = 0,
		windowStart = 0,
		windowCount = 0,
		rejected = 0,
	}
end

local function getState(player: Player): PlayerInput
	local state = inputs[player]
	if state == nil then
		state = newPlayerInput()
		inputs[player] = state
	end
	return state
end

local function isValidNumber(value: unknown, min: number, max: number): boolean
	return type(value) == "number" and value == value and value >= min and value <= max and value % 1 == 0
end

-- Обработать пакет ввода. Возвращает false, если пакет отброшен. now — os.clock().
function InputService.receive(player: Player, seq: unknown, held: unknown, counters: unknown, now: number): boolean
	local state = getState(player)

	-- Лимит частоты.
	if now - state.windowStart >= 1 then
		state.windowStart = now
		state.windowCount = 0
	end
	state.windowCount += 1
	if state.windowCount > GameConfig.Input.MaxPacketsPerSecond then
		state.rejected += 1
		return false
	end

	if
		not isValidNumber(seq, 0, MAX_SEQ)
		or not isValidNumber(held, 0, InputBits.ALL)
		or not isValidNumber(counters, 0, 2 ^ 20 - 1)
	then
		state.rejected += 1
		return false
	end
	local seqNumber = seq :: number
	if seqNumber <= state.lastSeq then
		return false -- устаревший или повторный пакет (ненадёжный канал может переставлять пакеты)
	end
	state.lastSeq = seqNumber
	state.lastPacketAt = now
	state.held = InputBits.sanitize(held :: number)

	local newCounters = InputBits.unpackCounters(counters :: number)
	local _, presses = InputBits.diffCounters(state.counters, newCounters)
	state.counters = newCounters
	for index, count in presses do
		state.pending[index] = math.min(state.pending[index] + count, 3)
	end
	return true
end

--[[
	Ввод игрока на текущий кадр симуляции. Каждое нажатие выдаётся ровно один раз;
	несколько нажатий одной кнопки между кадрами раздаются по одному за кадр.
]]
function InputService.consume(player: Player, now: number): InputBits.FrameInput
	local state = inputs[player]
	if state == nil then
		return InputBits.empty()
	end
	local pressed = 0
	for index, bit in InputBits.ACTIONS do
		if state.pending[index] > 0 then
			state.pending[index] -= 1
			pressed = bit32.bor(pressed, bit)
		end
	end
	local held = if now - state.lastPacketAt > STALE_TIMEOUT then 0 else state.held
	return { held = held, pressed = pressed }
end

-- Сбросить накопленные нажатия (например, в начале раунда).
function InputService.clearPending(player: Player)
	local state = inputs[player]
	if state then
		table.clear(state.pending)
		for index = 1, #InputBits.ACTIONS do
			state.pending[index] = 0
		end
	end
end

function InputService.getRejectedCount(player: Player): number
	local state = inputs[player]
	return if state then state.rejected else 0
end

function InputService.Init()
	Transport.onServerEvent("Input", function(player: Player, seq: unknown, held: unknown, counters: unknown)
		InputService.receive(player, seq, held, counters, os.clock())
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		inputs[player] = nil
	end)
end

function InputService.Start() end

return InputService
