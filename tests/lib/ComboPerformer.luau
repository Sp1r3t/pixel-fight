--!strict
--[[
	ComboPerformer — «нажимает кнопки» за бойца, чтобы выполнить комбо по жетонам (для тестов).

	Жетон за жетоном: следующую кнопку жмёт каждый кадр, пока не начнётся нужный удар, затем ждёт,
	пока удар попадёт (открылась отмена) — и переходит к следующему. Прыжковые жетоны (jL, jH):
	прыжок к противнику и удар в воздухе через delay кадров — подходящий момент подбирается перебором.
	Противник стоит без ввода (манекен).
]]

local roblox = require("@lune/roblox")
local RobloxRequire = require("./RobloxRequire")

local loader = RobloxRequire.new({
	globals = {
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
	},
})
local function shared(...: string): any
	return loader.require(loader.get("ReplicatedStorage", "Shared", ...))
end

local Simulation = shared("Combat", "Simulation")
local InputBits = shared("Combat", "InputBits")
local GameConfig = shared("Config", "GameConfig")

local ComboPerformer = {}

local BUTTON: { [string]: number } = {
	L = InputBits.Light,
	H = InputBits.Heavy,
	cL = InputBits.Light,
	cH = InputBits.Heavy,
	jL = InputBits.Light,
	jH = InputBits.Heavy,
	S = InputBits.Special,
	SU = InputBits.Super,
}

local MOVES: { [string]: { [string]: boolean } } = {
	L = { Light1 = true, Light2 = true, Light3 = true },
	H = { Heavy = true },
	cL = { CrouchLight = true },
	cH = { CrouchHeavy = true },
	jL = { AirLight = true },
	jH = { AirHeavy = true },
	S = { Special = true },
	SU = { Super = true },
}

type Attempt = { distance: number, delay: number }

-- Жетоны бойца 1 по сериям (каждая серия — пока защитник не пришёл в себя).
local series: { { string } } = {}

-- Одна попытка: вернёт список событий "Combo" (tag) и все события.
local function attempt(characterId: string, tokens: { string }, opponentId: string, try: Attempt): { string }
	local sim = Simulation.new({ characters = { characterId, opponentId } })
	sim.fighters[1].x = -try.distance / 2
	sim.fighters[2].x = try.distance / 2
	local attacker = sim.fighters[1]
	for _, token in tokens do
		if token == "SU" then
			attacker.meter = GameConfig.SuperMeter.Max
		end
	end
	local found: { string } = {}
	table.clear(series)
	local current: { string } = {}
	table.insert(series, current)
	local function step(held: number, pressed: number)
		local log = sim.fighters[2].comboLog
		local before = #log
		Simulation.step(sim, {
			{ held = held, pressed = pressed },
			{ held = 0, pressed = 0 },
		})
		if #log < before or (#log > 0 and before > #log) then
			current = {}
			table.insert(series, current)
		end
		if #log > before then
			for index = before + 1, #log do
				if log[index].slot == 1 then
					table.insert(current, log[index].token)
				end
			end
		elseif #log == 0 and #current > 0 then
			-- Серия закончилась (журнал очищен) — следующая пойдёт в новый список.
			current = {}
			table.insert(series, current)
		end
		for _, event in sim.events do
			if event.kind == "Combo" and event.slot == 1 and event.tag then
				table.insert(found, event.tag)
			end
		end
	end

	local toward = InputBits.Right
	for index, token in tokens do
		local button = BUTTON[token]
		local wanted = MOVES[token]
		local airborneToken = token == "jL" or token == "jH"
		if airborneToken then
			-- Прыжок к противнику, удар в воздухе через delay кадров.
			step(bit32.bor(InputBits.Up, toward), InputBits.Up)
			for _ = 1, try.delay do
				step(toward, 0)
			end
		end
		local held = if token == "cL" or token == "cH" then InputBits.Down else 0
		local started = false
		for _ = 1, 90 do
			if attacker.state == "Attack" and attacker.move and wanted[attacker.move] and attacker.moveFrame <= 1 then
				started = true
				break
			end
			step(held, button)
		end
		if not started then
			return found
		end
		-- Ждём попадания этого удара (или конца приёма).
		local connected = false
		for _ = 1, 120 do
			if attacker.moveConnected or sim.cinematic ~= nil then
				connected = true
				break
			end
			if attacker.state ~= "Attack" and index < #tokens and not airborneToken then
				break
			end
			step(held, 0)
			-- Снаряд мог попасть уже после конца приёма.
			if sim.fighters[2].comboHits > 0 and (token == "S") then
				connected = true
				break
			end
		end
		if not connected and not airborneToken then
			return found
		end
		if airborneToken then
			-- Дождаться попадания в воздухе.
			for _ = 1, 60 do
				if sim.fighters[2].comboHits > 0 then
					break
				end
				step(0, 0)
			end
		end
	end
	-- Досмотреть серию до конца.
	for _ = 1, 400 do
		step(0, 0)
		if #found > 0 and sim.fighters[2].comboHits == 0 then
			break
		end
	end
	return found
end

--[[
	Выполнить комбо: перебирает дистанцию и момент удара в прыжке.
	Возвращает true, если распознано комбо comboId.
]]
function ComboPerformer.perform(characterId: string, tokens: { string }, comboId: string, opponentId: string?): boolean
	local jump = tokens[1] == "jL" or tokens[1] == "jH"
	local distances = if jump then { 6, 7, 8, 8.5, 9, 10 } else { 1.6, 2.2, 3 }
	local delays: { number } = { 0 }
	if jump then
		delays = {}
		for delay = 16, 42, 2 do
			table.insert(delays, delay)
		end
	end
	for _, distance in distances do
		for _, delay in delays do
			local found = attempt(characterId, tokens, opponentId or "rook", { distance = distance, delay = delay })
			for _, tag in found do
				if tag == comboId then
					return true
				end
			end
		end
	end
	return false
end

-- Выполним ли шаблон жетонов (без названия комбо): жетоны серии содержат его подряд.
function ComboPerformer.performPattern(characterId: string, tokens: { string }, opponentId: string?): boolean
	local jump = tokens[1] == "jL" or tokens[1] == "jH"
	local distances = if jump then { 6, 7, 8, 8.5, 9, 10 } else { 1.6, 2.2, 3 }
	local delays: { number } = { 0 }
	if jump then
		delays = {}
		for delay = 20, 42, 2 do
			table.insert(delays, delay)
		end
	end
	for _, distance in distances do
		for _, delay in delays do
			attempt(characterId, tokens, opponentId or "rook", { distance = distance, delay = delay })
			for _, list in series do
				local text = " " .. table.concat(list, " ") .. " "
				if string.find(text, " " .. table.concat(tokens, " ") .. " ", 1, true) then
					return true
				end
			end
		end
	end
	return false
end

return ComboPerformer
