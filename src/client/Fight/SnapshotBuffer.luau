--!strict
--[[
	Буфер снапшотов с интерполяцией.

	Клиент показывает мир чуть «в прошлом» (GameConfig.Net.InterpolationDelay), интерполируя
	между двумя соседними снапшотами — движение получается плавным при любой частоте кадров
	и небольших колебаниях сети. Номер кадра сервера оценивается по времени прихода снапшотов.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Snapshot = require(ReplicatedStorage.Shared.Combat.Snapshot)

type Snapshot = Snapshot.Snapshot
type FighterSnapshot = Snapshot.FighterSnapshot

export type Sample = {
	frame: number, -- дробный кадр сервера, который сейчас показываем
	latest: Snapshot,
	fighters: { FighterSnapshot },
	projectiles: { Snapshot.ProjectileSnapshot },
}

export type Buffer = {
	push: (snapshot: Snapshot, now: number) -> (),
	sample: (now: number) -> Sample?,
	reset: () -> (),
	latest: () -> Snapshot?,
}

local TICK = GameConfig.TickRate
local MAX_SNAPSHOTS = 32
local MAX_EXTRAPOLATION = 6 -- кадров

local SnapshotBuffer = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function interpolateFighter(
	a: FighterSnapshot,
	b: FighterSnapshot,
	t: number,
	framesSinceA: number
): FighterSnapshot
	local result = table.clone(a)
	result.x = lerp(a.x, b.x, t)
	result.y = lerp(a.y, b.y, t)
	result.vx = lerp(a.vx, b.vx, t)
	result.vy = lerp(a.vy, b.vy, t)
	if b.state == a.state and b.move == a.move then
		result.stateFrame = a.stateFrame + framesSinceA
		result.moveFrame = a.moveFrame + framesSinceA
	end
	return result
end

local function extrapolateFighter(a: FighterSnapshot, frames: number): FighterSnapshot
	local result = table.clone(a)
	result.x = a.x + a.vx * frames / TICK
	result.y = math.max(0, a.y + a.vy * frames / TICK)
	result.stateFrame = a.stateFrame + frames
	result.moveFrame = a.moveFrame + frames
	return result
end

function SnapshotBuffer.new(delaySeconds: number?): Buffer
	local delayFrames = (delaySeconds or GameConfig.Net.InterpolationDelay) * TICK
	local snapshots: { Snapshot } = {}
	local offset: number? = nil -- оценка (кадр сервера − время клиента × TICK)

	local buffer = {} :: Buffer

	function buffer.reset()
		table.clear(snapshots)
		offset = nil
	end

	function buffer.latest(): Snapshot?
		return snapshots[#snapshots]
	end

	function buffer.push(snapshot: Snapshot, now: number)
		local last = snapshots[#snapshots]
		if last and snapshot.frame <= last.frame then
			return -- устаревший или повторный снапшот
		end
		table.insert(snapshots, snapshot)
		if #snapshots > MAX_SNAPSHOTS then
			table.remove(snapshots, 1)
		end
		local candidate = snapshot.frame - now * TICK
		if offset == nil or candidate > (offset :: number) then
			offset = candidate -- снапшот пришёл «раньше»: задержка меньше, чем думали
		else
			-- Медленно подстраиваемся к более поздним (сеть стала медленнее).
			offset = lerp(offset :: number, candidate, 0.02)
		end
	end

	function buffer.sample(now: number): Sample?
		local count = #snapshots
		if count == 0 or offset == nil then
			return nil
		end
		local target = now * TICK + (offset :: number) - delayFrames
		local first = snapshots[1]
		if target <= first.frame then
			return {
				frame = first.frame,
				latest = snapshots[count],
				fighters = first.fighters,
				projectiles = first.projectiles,
			}
		end

		for index = count - 1, 1, -1 do
			local a = snapshots[index]
			local b = snapshots[index + 1]
			if target >= a.frame and target <= b.frame then
				local span = b.frame - a.frame
				local t = if span > 0 then (target - a.frame) / span else 0
				local framesSinceA = math.floor(target - a.frame)
				local fighters = {}
				for slot, fighter in a.fighters do
					local other = b.fighters[slot]
					fighters[slot] = if other then interpolateFighter(fighter, other, t, framesSinceA) else fighter
				end
				return { frame = target, latest = snapshots[count], fighters = fighters, projectiles = a.projectiles }
			end
		end

		-- Новее последнего снапшота: немного экстраполируем.
		local last = snapshots[count]
		local ahead = math.min(target - last.frame, MAX_EXTRAPOLATION)
		local fighters = {}
		for slot, fighter in last.fighters do
			fighters[slot] = extrapolateFighter(fighter, ahead)
		end
		return { frame = last.frame + ahead, latest = last, fighters = fighters, projectiles = last.projectiles }
	end

	return buffer
end

return SnapshotBuffer
